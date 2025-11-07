const std = @import("std");
const quickjs = @import("quickjs");

const types = @import("types.zig");

const FrameData = types.FrameData;
const FrameResult = types.FrameResult;

pub fn runFrame(runtime: anytype, frame_data: FrameData) !FrameResult {
    const ctx = try runtime.acquireContext();

    const global = quickjs.JS_GetGlobalObject(ctx);
    defer quickjs.JS_FreeValue(ctx, global);
    const global_const = quickjs.asValueConst(global);

    const run_frame_name = "runFrame\x00";
    const run_frame_ptr: [*c]const u8 = @ptrCast(run_frame_name.ptr);
    const func = quickjs.JS_GetPropertyStr(ctx, global_const, run_frame_ptr);
    const func_const: quickjs.JSValueConst = quickjs.asValueConst(func);
    if (quickjs.JS_IsException(func_const)) {
        runtime.warnLastException("runFrame.lookup");
        return error.CallFailed;
    }
    defer quickjs.JS_FreeValue(ctx, func);

    if (!quickjs.JS_IsFunction(ctx, func_const)) {
        std.log.err("QuickJS runFrame missing or not callable", .{});
        return error.InvalidResponse;
    }

    const frame_prop = "__frame_args\x00";
    const frame_prop_ptr: [*c]const u8 = @ptrCast(frame_prop.ptr);
    const frame_obj = quickjs.JS_GetPropertyStr(ctx, global_const, frame_prop_ptr);
    const frame_obj_const = quickjs.asValueConst(frame_obj);
    if (quickjs.JS_IsException(frame_obj_const)) {
        runtime.warnLastException("runFrame.frameArgs.lookup");
        return error.CallFailed;
    }
    if (!quickjs.JS_IsObject(frame_obj_const)) {
        quickjs.JS_FreeValue(ctx, frame_obj);
        std.log.err("QuickJS __frame_args missing or not an object", .{});
        return error.InvalidResponse;
    }
    defer quickjs.JS_FreeValue(ctx, frame_obj);

    const position_f64: f64 = @floatCast(frame_data.position);
    try runtime.setFloatProperty(ctx, frame_obj_const, "position", position_f64);

    const dt_f64: f64 = @floatCast(frame_data.dt);
    try runtime.setFloatProperty(ctx, frame_obj_const, "dt", dt_f64);

    runtime.clearFrameCommand();

    var argv = [_]quickjs.JSValueConst{frame_obj_const};
    const argc = @as(c_int, @intCast(argv.len));
    const argv_ptr: [*c]quickjs.JSValueConst = @ptrCast(&argv[0]);
    const result_value = quickjs.JS_Call(
        ctx,
        func_const,
        global_const,
        argc,
        argv_ptr,
    );
    const result_const: quickjs.JSValueConst = quickjs.asValueConst(result_value);
    if (quickjs.JS_IsException(result_const)) {
        runtime.warnLastException("runFrame.call");
        quickjs.JS_FreeValue(ctx, result_value);
        return error.CallFailed;
    }
    defer quickjs.JS_FreeValue(ctx, result_value);

    if (runtime.takeFrameCommand()) |command| {
        switch (command) {
            .set_animated_position => |value| {
                if (!std.math.isFinite(value)) return error.InvalidResponse;
                return .{ .new_position = value };
            },
        }
    }

    return .{ .new_position = frame_data.position };
}
