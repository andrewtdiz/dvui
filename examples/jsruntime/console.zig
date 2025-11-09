const std = @import("std");
const quickjs = @import("quickjs");

pub const ConsoleSink = struct {
    context: ?*anyopaque,
    send: *const fn (context: ?*anyopaque, level: []const u8, message: []const u8) void,
};

var g_console_sink: ?ConsoleSink = null;

pub fn setSink(sink: ConsoleSink) void {
    g_console_sink = sink;
}

pub fn clearSink() void {
    g_console_sink = null;
}

pub fn installBindings(
    runtime: anytype,
    ctx: *quickjs.JSContext,
    global_const: quickjs.JSValueConst,
) !void {
    const console_obj = quickjs.JS_NewObject(ctx);
    const console_const = quickjs.asValueConst(console_obj);
    if (quickjs.JS_IsException(console_const)) {
        quickjs.JS_FreeValue(ctx, console_obj);
        runtime.warnLastException("console.alloc");
        return error.CallFailed;
    }

    try installMethod(runtime, ctx, console_const, "log", engineConsoleLog);
    try installMethod(runtime, ctx, console_const, "info", engineConsoleInfo);
    try installMethod(runtime, ctx, console_const, "debug", engineConsoleDebug);
    try installMethod(runtime, ctx, console_const, "warn", engineConsoleWarn);
    try installMethod(runtime, ctx, console_const, "error", engineConsoleError);

    const console_prop = "console\x00";
    const console_prop_ptr: [*c]const u8 = @ptrCast(console_prop.ptr);
    if (quickjs.JS_SetPropertyStr(ctx, global_const, console_prop_ptr, console_obj) < 0) {
        quickjs.JS_FreeValue(ctx, console_obj);
        runtime.warnLastException("console.global");
        return error.CallFailed;
    }
}

fn installMethod(
    runtime: anytype,
    ctx: *quickjs.JSContext,
    console_const: quickjs.JSValueConst,
    comptime name: []const u8,
    func: *const quickjs.JSCFunction,
) !void {
    const name_c = name ++ "\x00";
    const name_ptr: [*c]const u8 = @ptrCast(name_c.ptr);
    const func_value = quickjs.JS_NewCFunction(ctx, func, name_ptr, -1);
    const func_const = quickjs.asValueConst(func_value);
    if (quickjs.JS_IsException(func_const)) {
        quickjs.JS_FreeValue(ctx, func_value);
        runtime.warnLastException("console.method");
        return error.CallFailed;
    }

    if (quickjs.JS_SetPropertyStr(ctx, console_const, name_ptr, func_value) < 0) {
        quickjs.JS_FreeValue(ctx, func_value);
        runtime.warnLastException("console.set");
        return error.CallFailed;
    }
}

fn runtimeConsoleCallback(
    level: []const u8,
    ctx: *quickjs.JSContext,
    argc: c_int,
    argv: [*c]quickjs.JSValueConst,
) void {
    const sink = g_console_sink orelse return;

    const message = stringifyConsoleArgs(ctx, argc, argv) catch return;
    defer std.heap.c_allocator.free(message);

    sink.send(sink.context, level, message);
}

fn stringifyConsoleArgs(
    ctx: *quickjs.JSContext,
    argc: c_int,
    argv: [*c]quickjs.JSValueConst,
) ![]u8 {
    const allocator = std.heap.c_allocator;
    var parts = std.ArrayList(u8).empty;
    errdefer parts.deinit(allocator);

    if (argc <= 0 or argv == null) {
        return parts.toOwnedSlice(allocator);
    }

    const total: usize = @intCast(argc);
    var index: usize = 0;
    while (index < total) : (index += 1) {
        var len: usize = 0;
        const cstr_opt = quickjs.JS_ToCStringLen(ctx, &len, argv[index]);
        if (cstr_opt) |cptr| {
            defer quickjs.JS_FreeCString(ctx, cptr);
            try parts.appendSlice(allocator, cptr[0..len]);
        } else {
            try parts.appendSlice(allocator, "<unprintable>");
        }

        if (index + 1 < total) {
            try parts.append(allocator, ' ');
        }
    }

    return parts.toOwnedSlice(allocator);
}

fn engineConsoleLog(
    ctx: *quickjs.JSContext,
    _: quickjs.JSValueConst,
    argc: c_int,
    argv: [*c]quickjs.JSValueConst,
) callconv(.c) quickjs.JSValue {
    runtimeConsoleCallback("log", ctx, argc, argv);
    return quickjs.JS_GetUndefined();
}

fn engineConsoleInfo(
    ctx: *quickjs.JSContext,
    _: quickjs.JSValueConst,
    argc: c_int,
    argv: [*c]quickjs.JSValueConst,
) callconv(.c) quickjs.JSValue {
    runtimeConsoleCallback("info", ctx, argc, argv);
    return quickjs.JS_GetUndefined();
}

fn engineConsoleDebug(
    ctx: *quickjs.JSContext,
    _: quickjs.JSValueConst,
    argc: c_int,
    argv: [*c]quickjs.JSValueConst,
) callconv(.c) quickjs.JSValue {
    runtimeConsoleCallback("debug", ctx, argc, argv);
    return quickjs.JS_GetUndefined();
}

fn engineConsoleWarn(
    ctx: *quickjs.JSContext,
    _: quickjs.JSValueConst,
    argc: c_int,
    argv: [*c]quickjs.JSValueConst,
) callconv(.c) quickjs.JSValue {
    runtimeConsoleCallback("warn", ctx, argc, argv);
    return quickjs.JS_GetUndefined();
}

fn engineConsoleError(
    ctx: *quickjs.JSContext,
    _: quickjs.JSValueConst,
    argc: c_int,
    argv: [*c]quickjs.JSValueConst,
) callconv(.c) quickjs.JSValue {
    runtimeConsoleCallback("error", ctx, argc, argv);
    return quickjs.JS_GetUndefined();
}
