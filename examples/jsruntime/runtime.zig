const std = @import("std");

const quickjs = @import("quickjs");

const alloc = @import("../alloc.zig");
const console = @import("console.zig");
const event_ops = @import("events.zig");
const frame_ops = @import("frame.zig");
const hot_reload = @import("hotreload.zig");
const types = @import("types.zig");
pub const FrameData = types.FrameData;
pub const FrameResult = types.FrameResult;
pub const FrameCommand = types.FrameCommand;
pub const SelectionColor = types.SelectionColor;
pub const MouseSnapshot = types.MouseSnapshot;
pub const MouseEvent = types.MouseEvent;
pub const MouseEventKind = types.MouseEventKind;
pub const MouseButton = types.MouseButton;
pub const KeyEvent = types.KeyEvent;
pub const KeyEventKind = types.KeyEventKind;
pub const KeyCode = types.KeyCode;

const bootstrap_script_path = "examples/resources/js/runtime.js";
const CommandSlot = struct {
    command: ?FrameCommand = null,
    selection_color: ?SelectionColor = null,
};

var g_command_slot: ?*CommandSlot = null;

pub const EvalResult = struct {
    success: bool,
    result: []u8,
};

pub const ConsoleSink = console.ConsoleSink;

pub const JSRuntime = @This();

allocator: std.mem.Allocator,
handle: *quickjs.js_app,
command_slot: *CommandSlot,

pub const Error = error{
    RuntimeInitFailed,
    ScriptLoadFailed,
    CallFailed,
    InvalidResponse,
};

pub fn init(script_path: []const u8) Error!JSRuntime {
    const allocator = alloc.allocator();

    const runtime = quickjs.js_app_new(-1, -1) orelse return error.RuntimeInitFailed;
    errdefer quickjs.js_app_free(runtime);

    const slot = allocator.create(CommandSlot) catch return error.RuntimeInitFailed;
    errdefer allocator.destroy(slot);
    slot.* = .{};

    g_command_slot = slot;
    errdefer if (g_command_slot) |curr_slot| {
        if (curr_slot == slot) g_command_slot = null;
    };

    var instance = JSRuntime{
        .allocator = allocator,
        .handle = runtime,
        .command_slot = slot,
    };

    try evalScriptFile(allocator, runtime, bootstrap_script_path);
    try instance.installNativeBindings();
    try evalScriptFile(allocator, runtime, script_path);
    try hot_reload.enable(script_path);

    return instance;
}

pub fn deinit(self: *JSRuntime) void {
    if (g_command_slot == self.command_slot) {
        g_command_slot = null;
    }
    self.allocator.destroy(self.command_slot);
    quickjs.js_app_free(self.handle);
}

pub fn runFrame(self: *JSRuntime, frame_data: FrameData) Error!FrameResult {
    return frame_ops.runFrame(self, frame_data);
}

pub fn updateMouse(self: *JSRuntime, mouse: MouseSnapshot) Error!void {
    return event_ops.updateMouse(self, mouse);
}

pub fn emitMouseEvent(self: *JSRuntime, event: MouseEvent) Error!void {
    return event_ops.emitMouseEvent(self, event);
}

pub fn emitKeyEvent(self: *JSRuntime, event: KeyEvent) Error!void {
    return event_ops.emitKeyEvent(self, event);
}

pub fn setFloatProperty(
    self: *JSRuntime,
    ctx: *quickjs.JSContext,
    target: quickjs.JSValueConst,
    comptime name: []const u8,
    value: f64,
) Error!void {
    const property_value = quickjs.JS_NewFloat64(ctx, value);
    const prop_name = name ++ "\x00";
    const prop_ptr: [*c]const u8 = @ptrCast(prop_name.ptr);
    if (quickjs.JS_SetPropertyStr(ctx, target, prop_ptr, property_value) < 0) {
        quickjs.JS_FreeValue(ctx, property_value);
        self.warnLastException(name);
        return error.CallFailed;
    }
}

pub fn setIntProperty(
    self: *JSRuntime,
    ctx: *quickjs.JSContext,
    target: quickjs.JSValueConst,
    comptime name: []const u8,
    value: i32,
) Error!void {
    const property_value = quickjs.JS_NewInt32(ctx, value);
    const prop_name = name ++ "\x00";
    const prop_ptr: [*c]const u8 = @ptrCast(prop_name.ptr);
    if (quickjs.JS_SetPropertyStr(ctx, target, prop_ptr, property_value) < 0) {
        quickjs.JS_FreeValue(ctx, property_value);
        self.warnLastException(name);
        return error.CallFailed;
    }
}

pub fn setBoolProperty(
    self: *JSRuntime,
    ctx: *quickjs.JSContext,
    target: quickjs.JSValueConst,
    comptime name: []const u8,
    value: bool,
) Error!void {
    const property_value = quickjs.JS_NewBool(ctx, value);
    const prop_name = name ++ "\x00";
    const prop_ptr: [*c]const u8 = @ptrCast(prop_name.ptr);
    if (quickjs.JS_SetPropertyStr(ctx, target, prop_ptr, property_value) < 0) {
        quickjs.JS_FreeValue(ctx, property_value);
        self.warnLastException(name);
        return error.CallFailed;
    }
}

pub fn setStringProperty(
    self: *JSRuntime,
    ctx: *quickjs.JSContext,
    target: quickjs.JSValueConst,
    comptime name: []const u8,
    value: []const u8,
) Error!void {
    const property_value = quickjs.JS_NewStringLen(ctx, @ptrCast(value.ptr), value.len);
    const property_const = quickjs.asValueConst(property_value);
    if (quickjs.JS_IsException(property_const)) {
        self.warnLastException(name);
        return error.CallFailed;
    }
    const prop_name = name ++ "\x00";
    const prop_ptr: [*c]const u8 = @ptrCast(prop_name.ptr);
    if (quickjs.JS_SetPropertyStr(ctx, target, prop_ptr, property_value) < 0) {
        quickjs.JS_FreeValue(ctx, property_value);
        self.warnLastException(name);
        return error.CallFailed;
    }
}

pub fn populateWindowEventCommon(
    self: *JSRuntime,
    ctx: *quickjs.JSContext,
    target: quickjs.JSValueConst,
    event_type: []const u8,
) Error!void {
    return self.setStringProperty(ctx, target, "type", event_type);
}

pub fn acquireContext(self: *JSRuntime) Error!*quickjs.JSContext {
    const ctx_ptr = quickjs.js_app_get_context(self.handle) orelse {
        self.warnLastException("context");
        return error.CallFailed;
    };
    return @ptrCast(ctx_ptr);
}

pub fn warnLastException(self: *JSRuntime, context: []const u8) void {
    warnLastExceptionHandle(self.handle, context);
}

fn copyLastException(self: *JSRuntime) ![]u8 {
    var buffer: [512]u8 = undefined;
    @memset(buffer[0..], 0);
    const rc = quickjs.js_app_last_exception(self.handle, &buffer, buffer.len);
    if (rc == 0) {
        const slice = std.mem.sliceTo(buffer[0..], 0);
        return self.allocator.dupe(u8, slice);
    }
    return self.allocator.dupe(u8, "QuickJS exception (unavailable)");
}

fn valueToOwnedString(self: *JSRuntime, ctx: *quickjs.JSContext, value: quickjs.JSValueConst) ![]u8 {
    var length: usize = 0;
    const cstr_ptr = quickjs.JS_ToCStringLen(ctx, &length, value) orelse {
        return self.allocator.dupe(u8, "undefined");
    };
    defer quickjs.JS_FreeCString(ctx, cstr_ptr);

    const span = cstr_ptr[0..length];
    return self.allocator.dupe(u8, span);
}

pub fn clearFrameCommand(self: *JSRuntime) void {
    self.command_slot.command = null;
}

pub fn takeFrameCommand(self: *JSRuntime) ?FrameCommand {
    const cmd = self.command_slot.command;
    self.command_slot.command = null;
    return cmd;
}

pub fn takeSelectionColor(self: *JSRuntime) ?SelectionColor {
    const color = self.command_slot.selection_color;
    self.command_slot.selection_color = null;
    return color;
}

pub fn setConsoleSink(sink: ConsoleSink) void {
    console.setSink(sink);
}

pub fn clearConsoleSink() void {
    console.clearSink();
}

pub fn freeEvalResult(self: *JSRuntime, buffer: []u8) void {
    self.allocator.free(buffer);
}

pub fn evalImmediate(self: *JSRuntime, code: []const u8) !EvalResult {
    const ctx = try self.acquireContext();

    const code_copy = self.allocator.allocSentinel(u8, code.len, 0) catch return error.CallFailed;
    defer self.allocator.free(code_copy);
    @memcpy(code_copy[0..code.len], code);

    const label = "<terminal>\x00";
    const label_ptr: [*c]const u8 = @ptrCast(label.ptr);

    const eval_value = quickjs.JS_Eval(ctx, @ptrCast(code_copy.ptr), code.len, label_ptr, 0);
    defer quickjs.JS_FreeValue(ctx, eval_value);
    const eval_const = quickjs.asValueConst(eval_value);

    if (quickjs.JS_IsException(eval_const)) {
        const message = try self.copyLastException();
        return .{ .success = false, .result = message };
    }

    const pending_jobs = quickjs.js_app_execute_jobs(self.handle, 0);
    if (pending_jobs < 0) {
        const message = try self.copyLastException();
        return .{ .success = false, .result = message };
    }

    const rendered = try self.valueToOwnedString(ctx, eval_const);

    return .{ .success = true, .result = rendered };
}

fn installNativeBindings(self: *JSRuntime) Error!void {
    const ctx = try self.acquireContext();

    const global = quickjs.JS_GetGlobalObject(ctx);
    defer quickjs.JS_FreeValue(ctx, global);
    const global_const = quickjs.asValueConst(global);

    const engine_obj = quickjs.JS_NewObject(ctx);
    const engine_const = quickjs.asValueConst(engine_obj);
    if (quickjs.JS_IsException(engine_const)) {
        quickjs.JS_FreeValue(ctx, engine_obj);
        self.warnLastException("engine.alloc");
        return error.CallFailed;
    }

    installEngineMethod(self, ctx, engine_const, "setAnimatedPosition", engineSetAnimatedPosition, 1) catch |err| {
        quickjs.JS_FreeValue(ctx, engine_obj);
        return err;
    };
    installEngineMethod(self, ctx, engine_const, "setSelectionBorderColor", engineSetSelectionBorderColor, 1) catch |err| {
        quickjs.JS_FreeValue(ctx, engine_obj);
        return err;
    };

    const engine_prop = "engine\x00";
    const engine_prop_ptr: [*c]const u8 = @ptrCast(engine_prop.ptr);
    if (quickjs.JS_SetPropertyStr(ctx, global_const, engine_prop_ptr, engine_obj) < 0) {
        quickjs.JS_FreeValue(ctx, engine_obj);
        self.warnLastException("engine.global");
        return error.CallFailed;
    }

    try console.installBindings(self, ctx, global_const);
}

fn evalScriptFile(
    allocator: std.mem.Allocator,
    runtime: *quickjs.js_app,
    path: []const u8,
) Error!void {
    const script_c = allocator.allocSentinel(u8, path.len, 0) catch return error.ScriptLoadFailed;
    defer allocator.free(script_c);

    @memcpy(script_c[0..path.len], path);

    if (quickjs.js_app_eval_file(runtime, script_c.ptr) != 0) {
        warnLastExceptionHandle(runtime, path);
        return error.ScriptLoadFailed;
    }
}

fn installEngineMethod(
    self: *JSRuntime,
    ctx: *quickjs.JSContext,
    engine_const: quickjs.JSValueConst,
    comptime name: []const u8,
    func: *const quickjs.JSCFunction,
    argc: c_int,
) !void {
    const method_name = name ++ "\x00";
    const method_ptr: [*c]const u8 = @ptrCast(method_name.ptr);
    const func_value = quickjs.JS_NewCFunction(ctx, func, method_ptr, argc);
    const func_const = quickjs.asValueConst(func_value);
    if (quickjs.JS_IsException(func_const)) {
        quickjs.JS_FreeValue(ctx, func_value);
        self.warnLastException("engine.method");
        return error.CallFailed;
    }

    if (quickjs.JS_SetPropertyStr(ctx, engine_const, method_ptr, func_value) < 0) {
        quickjs.JS_FreeValue(ctx, func_value);
        self.warnLastException("engine.install");
        return error.CallFailed;
    }
}

fn warnLastExceptionHandle(runtime: *quickjs.js_app, context: []const u8) void {
    var buffer: [512]u8 = undefined;
    @memset(buffer[0..], 0);
    const rc = quickjs.js_app_last_exception(runtime, &buffer, buffer.len);
    if (rc == 0) {
        const message = std.mem.sliceTo(buffer[0..], 0);
        std.log.err("QuickJS {s}: {s}", .{ context, message });
    } else {
        std.log.err("QuickJS {s}: <exception unavailable>", .{context});
    }
}

fn engineSetAnimatedPosition(
    ctx: *quickjs.JSContext,
    _: quickjs.JSValueConst,
    argc: c_int,
    argv: [*c]quickjs.JSValueConst,
) callconv(.c) quickjs.JSValue {
    if (g_command_slot) |slot| {
        if (argc > 0 and argv != null) {
            var value_f64: f64 = 0;
            if (quickjs.JS_ToFloat64(ctx, &value_f64, argv[0]) >= 0 and std.math.isFinite(value_f64)) {
                const value_f32: f32 = @floatCast(value_f64);
                slot.command = .{ .set_animated_position = value_f32 };
            }
        }
    }
    return quickjs.JS_GetUndefined();
}

fn engineSetSelectionBorderColor(
    ctx: *quickjs.JSContext,
    _: quickjs.JSValueConst,
    argc: c_int,
    argv: [*c]quickjs.JSValueConst,
) callconv(.c) quickjs.JSValue {
    if (g_command_slot) |slot| {
        if (argc > 0 and argv != null) {
            var value_u32: u32 = 0;
            if (quickjs.JS_ToUint32(ctx, &value_u32, argv[0]) >= 0) {
                slot.selection_color = value_u32;
            }
        }
    }
    return quickjs.JS_GetUndefined();
}
