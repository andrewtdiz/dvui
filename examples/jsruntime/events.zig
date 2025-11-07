const std = @import("std");
const quickjs = @import("quickjs");

const types = @import("types.zig");

const MouseSnapshot = types.MouseSnapshot;
const MouseEvent = types.MouseEvent;
const MouseEventKind = types.MouseEventKind;
const MouseButton = types.MouseButton;
const KeyEvent = types.KeyEvent;
const KeyEventKind = types.KeyEventKind;
const KeyCode = types.KeyCode;

pub fn updateMouse(runtime: anytype, mouse: MouseSnapshot) !void {
    const ctx = try runtime.acquireContext();

    const global = quickjs.JS_GetGlobalObject(ctx);
    defer quickjs.JS_FreeValue(ctx, global);
    const global_const = quickjs.asValueConst(global);

    const mouse_prop = "mouse\x00";
    const mouse_prop_ptr: [*c]const u8 = @ptrCast(mouse_prop.ptr);

    const current = quickjs.JS_GetPropertyStr(ctx, global_const, mouse_prop_ptr);
    const current_const = quickjs.asValueConst(current);
    if (quickjs.JS_IsException(current_const)) {
        runtime.warnLastException("mouse.lookup");
        return error.CallFailed;
    }

    const is_object = quickjs.JS_IsObject(current_const);
    const needs_create = quickjs.JS_IsUndefined(current_const) or quickjs.JS_IsNull(current_const) or !is_object;
    if (needs_create) {
        quickjs.JS_FreeValue(ctx, current);

        const mouse_obj = quickjs.JS_NewObject(ctx);
        const mouse_obj_const = quickjs.asValueConst(mouse_obj);
        if (quickjs.JS_IsException(mouse_obj_const)) {
            runtime.warnLastException("mouse.alloc");
            return error.CallFailed;
        }

        const x_value_new: f64 = @floatFromInt(mouse.x);
        runtime.setFloatProperty(ctx, mouse_obj_const, "x", x_value_new) catch |err| {
            quickjs.JS_FreeValue(ctx, mouse_obj);
            return err;
        };

        const y_value_new: f64 = @floatFromInt(mouse.y);
        runtime.setFloatProperty(ctx, mouse_obj_const, "y", y_value_new) catch |err| {
            quickjs.JS_FreeValue(ctx, mouse_obj);
            return err;
        };

        if (quickjs.JS_SetPropertyStr(ctx, global_const, mouse_prop_ptr, mouse_obj) < 0) {
            quickjs.JS_FreeValue(ctx, mouse_obj);
            runtime.warnLastException("mouse.set");
            return error.CallFailed;
        }
        return;
    }

    defer quickjs.JS_FreeValue(ctx, current);

    const x_value: f64 = @floatFromInt(mouse.x);
    try runtime.setFloatProperty(ctx, current_const, "x", x_value);

    const y_value: f64 = @floatFromInt(mouse.y);
    try runtime.setFloatProperty(ctx, current_const, "y", y_value);
}

pub fn emitMouseEvent(runtime: anytype, event: MouseEvent) !void {
    const ctx = try runtime.acquireContext();

    const global = quickjs.JS_GetGlobalObject(ctx);
    defer quickjs.JS_FreeValue(ctx, global);
    const global_const = quickjs.asValueConst(global);

    const dispatch = try lookupWindowDispatcher(runtime, ctx, global_const);
    defer quickjs.JS_FreeValue(ctx, dispatch.func);

    const type_label = mouseEventTypeString(event.kind);
    const type_value = quickjs.JS_NewStringLen(ctx, @ptrCast(type_label.ptr), type_label.len);
    const type_const = quickjs.asValueConst(type_value);
    if (quickjs.JS_IsException(type_const)) {
        runtime.warnLastException("mouseEvent.type");
        return error.CallFailed;
    }
    defer quickjs.JS_FreeValue(ctx, type_value);

    const detail_prop = "__mouseEvent\x00";
    const detail_prop_ptr: [*c]const u8 = @ptrCast(detail_prop.ptr);
    const detail_value = quickjs.JS_GetPropertyStr(ctx, global_const, detail_prop_ptr);
    const detail_const = quickjs.asValueConst(detail_value);
    if (quickjs.JS_IsException(detail_const)) {
        runtime.warnLastException("mouseEvent.detail.lookup");
        return error.CallFailed;
    }
    if (!quickjs.JS_IsObject(detail_const)) {
        quickjs.JS_FreeValue(ctx, detail_value);
        std.log.err("QuickJS __mouseEvent missing or not an object", .{});
        return error.InvalidResponse;
    }
    defer quickjs.JS_FreeValue(ctx, detail_value);

    try runtime.setStringProperty(ctx, detail_const, "button", mouseButtonString(event.button));
    try runtime.setIntProperty(ctx, detail_const, "x", event.x);
    try runtime.setIntProperty(ctx, detail_const, "y", event.y);

    var argv = [_]quickjs.JSValueConst{ type_const, detail_const };
    const argc = @as(c_int, @intCast(argv.len));
    const argv_ptr: [*c]quickjs.JSValueConst = @ptrCast(&argv[0]);
    const result_value = quickjs.JS_Call(
        ctx,
        dispatch.func_const,
        global_const,
        argc,
        argv_ptr,
    );
    const result_const = quickjs.asValueConst(result_value);
    if (quickjs.JS_IsException(result_const)) {
        runtime.warnLastException("mouseEvent.call");
        quickjs.JS_FreeValue(ctx, result_value);
        return error.CallFailed;
    }
    quickjs.JS_FreeValue(ctx, result_value);
}

pub fn emitKeyEvent(runtime: anytype, event: KeyEvent) !void {
    const ctx = try runtime.acquireContext();

    const global = quickjs.JS_GetGlobalObject(ctx);
    defer quickjs.JS_FreeValue(ctx, global);
    const global_const = quickjs.asValueConst(global);

    const dispatch = try lookupWindowDispatcher(runtime, ctx, global_const);
    defer quickjs.JS_FreeValue(ctx, dispatch.func);

    const type_label = keyEventTypeString(event.kind);
    const type_value = quickjs.JS_NewStringLen(ctx, @ptrCast(type_label.ptr), type_label.len);
    const type_const = quickjs.asValueConst(type_value);
    if (quickjs.JS_IsException(type_const)) {
        runtime.warnLastException("keyEvent.type");
        return error.CallFailed;
    }
    defer quickjs.JS_FreeValue(ctx, type_value);

    const detail_prop = "__keyEvent\x00";
    const detail_prop_ptr: [*c]const u8 = @ptrCast(detail_prop.ptr);
    const detail_value = quickjs.JS_GetPropertyStr(ctx, global_const, detail_prop_ptr);
    const detail_const = quickjs.asValueConst(detail_value);
    if (quickjs.JS_IsException(detail_const)) {
        runtime.warnLastException("keyEvent.detail.lookup");
        return error.CallFailed;
    }
    if (!quickjs.JS_IsObject(detail_const)) {
        quickjs.JS_FreeValue(ctx, detail_value);
        std.log.err("QuickJS __keyEvent missing or not an object", .{});
        return error.InvalidResponse;
    }
    defer quickjs.JS_FreeValue(ctx, detail_value);

    try runtime.setStringProperty(ctx, detail_const, "code", keyCodeString(event.code));
    try runtime.setBoolProperty(ctx, detail_const, "repeat", event.repeat);

    var argv = [_]quickjs.JSValueConst{ type_const, detail_const };
    const argc = @as(c_int, @intCast(argv.len));
    const argv_ptr: [*c]quickjs.JSValueConst = @ptrCast(&argv[0]);
    const result_value = quickjs.JS_Call(
        ctx,
        dispatch.func_const,
        global_const,
        argc,
        argv_ptr,
    );
    const result_const = quickjs.asValueConst(result_value);
    if (quickjs.JS_IsException(result_const)) {
        runtime.warnLastException("keyEvent.call");
        quickjs.JS_FreeValue(ctx, result_value);
        return error.CallFailed;
    }
    quickjs.JS_FreeValue(ctx, result_value);
}

const WindowDispatcher = struct {
    func: quickjs.JSValue,
    func_const: quickjs.JSValueConst,
};

fn lookupWindowDispatcher(
    runtime: anytype,
    ctx: *quickjs.JSContext,
    global_const: quickjs.JSValueConst,
) !WindowDispatcher {
    const dispatch_name = "__dispatchWindowEvent\x00";
    const dispatch_ptr: [*c]const u8 = @ptrCast(dispatch_name.ptr);
    const func = quickjs.JS_GetPropertyStr(ctx, global_const, dispatch_ptr);
    const func_const = quickjs.asValueConst(func);
    if (quickjs.JS_IsException(func_const)) {
        runtime.warnLastException("window.dispatch.lookup");
        return error.CallFailed;
    }
    if (!quickjs.JS_IsFunction(ctx, func_const)) {
        quickjs.JS_FreeValue(ctx, func);
        std.log.err("QuickJS __dispatchWindowEvent missing or not callable", .{});
        return error.InvalidResponse;
    }
    return .{ .func = func, .func_const = func_const };
}

fn mouseEventTypeString(kind: MouseEventKind) []const u8 {
    return switch (kind) {
        .down => "mousedown",
        .up => "mouseup",
        .click => "click",
    };
}

fn mouseButtonString(button: MouseButton) []const u8 {
    return switch (button) {
        .left => "left",
        .right => "right",
    };
}

fn keyEventTypeString(kind: KeyEventKind) []const u8 {
    return switch (kind) {
        .down => "keydown",
        .up => "keyup",
        .press => "keypress",
    };
}

fn keyCodeString(code: KeyCode) []const u8 {
    return switch (code) {
        .g => "KeyG",
        .r => "KeyR",
        .s => "KeyS",
    };
}
