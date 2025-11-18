const std = @import("std");
const quickjs = @import("quickjs");

const jsruntime = @import("../mod.zig");
const types = @import("types.zig");

const log = std.log.scoped(.solid_bridge);

const HostLookup = struct {
    value: quickjs.JSValue,
    const_value: quickjs.JSValueConst,
};

pub fn syncOps(runtime: *jsruntime.JSRuntime, store: *types.NodeStore) !bool {
    const ctx = try runtime.acquireContext();

    const global = quickjs.JS_GetGlobalObject(ctx);
    defer quickjs.JS_FreeValue(ctx, global);
    const global_const = quickjs.asValueConst(global);

    const host = try lookupHost(ctx, global_const);
    defer quickjs.JS_FreeValue(ctx, host.value);

    const flush = try lookupHostFunction(ctx, host.const_value, "flushOps");
    defer quickjs.JS_FreeValue(ctx, flush.value);

    const ops_value = quickjs.JS_Call(ctx, flush.const_value, host.const_value, 0, null);
    defer quickjs.JS_FreeValue(ctx, ops_value);
    const ops_const = quickjs.asValueConst(ops_value);
    if (quickjs.JS_IsException(ops_const)) {
        runtime.warnLastException("SolidHost.flushOps");
        return error.CallFailed;
    }
    if (!quickjs.JS_IsArray(ops_const)) return false;

    var scratch_arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer scratch_arena.deinit();
    const scratch = scratch_arena.allocator();

    const len = try arrayLength(ctx, ops_const);
    if (len == 0) {
        return false;
    }
    log.info("SolidHost applying {d} ops", .{len});
    var index_buf: [32]u8 = undefined;
    var idx: usize = 0;
    while (idx < len) : (idx += 1) {
        const entry_value = try arrayEntry(ctx, ops_const, idx, &index_buf);
        defer quickjs.JS_FreeValue(ctx, entry_value);
        const entry_const = quickjs.asValueConst(entry_value);
        if (!quickjs.JS_IsObject(entry_const)) continue;
        applyOp(ctx, scratch, entry_const, store) catch |err| {
            log.err("Solid op failed: {s}", .{@errorName(err)});
        };
    }

    if (store.node(0)) |root| {
        log.info("Solid store root children: {any}", .{root.children.items});
    } else {
        log.warn("Solid store missing root node", .{});
    }

    return true;
}

pub fn dispatchEvent(
    runtime: *jsruntime.JSRuntime,
    node_id: u32,
    event: []const u8,
    detail: ?[]const u8,
) !void {
    const ctx = try runtime.acquireContext();

    const global = quickjs.JS_GetGlobalObject(ctx);
    defer quickjs.JS_FreeValue(ctx, global);
    const global_const = quickjs.asValueConst(global);

    const host = try lookupHost(ctx, global_const);
    defer quickjs.JS_FreeValue(ctx, host.value);

    const dispatch = try lookupHostFunction(ctx, host.const_value, "dispatchEvent");
    defer quickjs.JS_FreeValue(ctx, dispatch.value);

    const id_value = quickjs.JS_NewInt32(ctx, @intCast(node_id));
    const id_const = quickjs.asValueConst(id_value);
    if (quickjs.JS_IsException(id_const)) {
        quickjs.JS_FreeValue(ctx, id_value);
        runtime.warnLastException("SolidHost.dispatchEvent.id");
        return error.CallFailed;
    }

    const type_value = quickjs.JS_NewStringLen(ctx, @ptrCast(event.ptr), event.len);
    const type_const = quickjs.asValueConst(type_value);
    if (quickjs.JS_IsException(type_const)) {
        quickjs.JS_FreeValue(ctx, id_value);
        quickjs.JS_FreeValue(ctx, type_value);
        runtime.warnLastException("SolidHost.dispatchEvent.type");
        return error.CallFailed;
    }

    const detail_value = if (detail) |payload| blk: {
        const js_value = quickjs.JS_NewStringLen(ctx, @ptrCast(payload.ptr), payload.len);
        const js_const = quickjs.asValueConst(js_value);
        if (quickjs.JS_IsException(js_const)) {
            quickjs.JS_FreeValue(ctx, id_value);
            quickjs.JS_FreeValue(ctx, type_value);
            quickjs.JS_FreeValue(ctx, js_value);
            runtime.warnLastException("SolidHost.dispatchEvent.detail");
            return error.CallFailed;
        }
        break :blk js_value;
    } else quickjs.JS_GetUndefined();
    const detail_const = quickjs.asValueConst(detail_value);

    var argv = [_]quickjs.JSValueConst{
        id_const,
        type_const,
        detail_const,
    };
    const result = quickjs.JS_Call(ctx, dispatch.const_value, host.const_value, argv.len, &argv);
    const result_const = quickjs.asValueConst(result);
    quickjs.JS_FreeValue(ctx, id_value);
    quickjs.JS_FreeValue(ctx, type_value);
    if (detail) |_| {
        quickjs.JS_FreeValue(ctx, detail_value);
    }
    if (quickjs.JS_IsException(result_const)) {
        quickjs.JS_FreeValue(ctx, result);
        runtime.warnLastException("SolidHost.dispatchEvent.call");
        return error.CallFailed;
    }
    quickjs.JS_FreeValue(ctx, result);

    const rc = quickjs.js_app_execute_jobs(runtime.handle, 0);
    if (rc < 0) {
        runtime.warnLastException("SolidHost.jobs");
        return error.CallFailed;
    }
}

pub fn updateSolidStateI32(runtime: *jsruntime.JSRuntime, key: []const u8, value: i32) !void {
    try updateSolidState(runtime, key, .{ .integer = value });
}

pub fn updateSolidStateString(
    runtime: *jsruntime.JSRuntime,
    key: []const u8,
    value: []const u8,
) !void {
    try updateSolidState(runtime, key, .{ .string = value });
}

pub fn readSolidStateI32(runtime: *jsruntime.JSRuntime, key: []const u8) !i32 {
    const ctx = try runtime.acquireContext();

    const global = quickjs.JS_GetGlobalObject(ctx);
    defer quickjs.JS_FreeValue(ctx, global);
    const global_const = quickjs.asValueConst(global);

    const host = try lookupHost(ctx, global_const);
    defer quickjs.JS_FreeValue(ctx, host.value);

    const getter = try lookupHostFunction(ctx, host.const_value, "getSignalValue");
    defer quickjs.JS_FreeValue(ctx, getter.value);

    const key_value = quickjs.JS_NewStringLen(ctx, @ptrCast(key.ptr), key.len);
    const key_const = quickjs.asValueConst(key_value);
    if (quickjs.JS_IsException(key_const)) {
        quickjs.JS_FreeValue(ctx, key_value);
        runtime.warnLastException("SolidHost.getSignalValue.key");
        return error.CallFailed;
    }

    var argv = [_]quickjs.JSValueConst{key_const};
    const result_value = quickjs.JS_Call(ctx, getter.const_value, host.const_value, argv.len, &argv);
    quickjs.JS_FreeValue(ctx, key_value);
    const result_const = quickjs.asValueConst(result_value);
    if (quickjs.JS_IsException(result_const)) {
        quickjs.JS_FreeValue(ctx, result_value);
        runtime.warnLastException("SolidHost.getSignalValue.call");
        return error.CallFailed;
    }
    if (quickjs.JS_IsUndefined(result_const) or quickjs.JS_IsNull(result_const)) {
        quickjs.JS_FreeValue(ctx, result_value);
        return error.SignalMissing;
    }

    var read_value: i32 = 0;
    if (quickjs.JS_ToInt32(ctx, &read_value, result_const) < 0) {
        quickjs.JS_FreeValue(ctx, result_value);
        runtime.warnLastException("SolidHost.getSignalValue.i32");
        return error.CallFailed;
    }
    quickjs.JS_FreeValue(ctx, result_value);

    const rc = quickjs.js_app_execute_jobs(runtime.handle, 0);
    if (rc < 0) {
        runtime.warnLastException("SolidHost.jobs");
        return error.CallFailed;
    }

    return read_value;
}

pub fn readSolidStateString(
    runtime: *jsruntime.JSRuntime,
    allocator: std.mem.Allocator,
    key: []const u8,
) ![]u8 {
    const ctx = try runtime.acquireContext();

    const global = quickjs.JS_GetGlobalObject(ctx);
    defer quickjs.JS_FreeValue(ctx, global);
    const global_const = quickjs.asValueConst(global);

    const host = try lookupHost(ctx, global_const);
    defer quickjs.JS_FreeValue(ctx, host.value);

    const getter = try lookupHostFunction(ctx, host.const_value, "getSignalValue");
    defer quickjs.JS_FreeValue(ctx, getter.value);

    const key_value = quickjs.JS_NewStringLen(ctx, @ptrCast(key.ptr), key.len);
    const key_const = quickjs.asValueConst(key_value);
    if (quickjs.JS_IsException(key_const)) {
        quickjs.JS_FreeValue(ctx, key_value);
        runtime.warnLastException("SolidHost.getSignalValue.key");
        return error.CallFailed;
    }

    var argv = [_]quickjs.JSValueConst{key_const};
    const result_value = quickjs.JS_Call(ctx, getter.const_value, host.const_value, argv.len, &argv);
    quickjs.JS_FreeValue(ctx, key_value);
    const result_const = quickjs.asValueConst(result_value);
    if (quickjs.JS_IsException(result_const)) {
        quickjs.JS_FreeValue(ctx, result_value);
        runtime.warnLastException("SolidHost.getSignalValue.call");
        return error.CallFailed;
    }
    if (quickjs.JS_IsUndefined(result_const) or quickjs.JS_IsNull(result_const)) {
        quickjs.JS_FreeValue(ctx, result_value);
        return error.SignalMissing;
    }

    var length: usize = 0;
    const cstr_ptr = quickjs.JS_ToCStringLen(ctx, &length, result_const) orelse {
        quickjs.JS_FreeValue(ctx, result_value);
        runtime.warnLastException("SolidHost.getSignalValue.string");
        return error.CallFailed;
    };
    defer quickjs.JS_FreeCString(ctx, cstr_ptr);

    const slice = cstr_ptr[0..length];
    const owned = try allocator.dupe(u8, slice);
    quickjs.JS_FreeValue(ctx, result_value);

    const rc = quickjs.js_app_execute_jobs(runtime.handle, 0);
    if (rc < 0) {
        runtime.warnLastException("SolidHost.jobs");
        allocator.free(owned);
        return error.CallFailed;
    }

    return owned;
}

const UpdateValue = union(enum) {
    integer: i32,
    string: []const u8,
};

fn updateSolidState(runtime: *jsruntime.JSRuntime, key: []const u8, update: UpdateValue) !void {
    const ctx = try runtime.acquireContext();

    const global = quickjs.JS_GetGlobalObject(ctx);
    defer quickjs.JS_FreeValue(ctx, global);
    const global_const = quickjs.asValueConst(global);

    const host = try lookupHost(ctx, global_const);
    defer quickjs.JS_FreeValue(ctx, host.value);

    const update_fn = try lookupHostFunction(ctx, host.const_value, "updateState");
    defer quickjs.JS_FreeValue(ctx, update_fn.value);

    const key_value = quickjs.JS_NewStringLen(ctx, @ptrCast(key.ptr), key.len);
    const key_const = quickjs.asValueConst(key_value);
    if (quickjs.JS_IsException(key_const)) {
        quickjs.JS_FreeValue(ctx, key_value);
        runtime.warnLastException("SolidHost.updateState.key");
        return error.CallFailed;
    }

    const value_value = createUpdateValue(ctx, runtime, update) catch |err| {
        quickjs.JS_FreeValue(ctx, key_value);
        return err;
    };
    const value_const = quickjs.asValueConst(value_value);

    var argv = [_]quickjs.JSValueConst{
        key_const,
        value_const,
    };
    const result = quickjs.JS_Call(ctx, update_fn.const_value, host.const_value, argv.len, &argv);
    const result_const = quickjs.asValueConst(result);
    quickjs.JS_FreeValue(ctx, key_value);
    quickjs.JS_FreeValue(ctx, value_value);
    if (quickjs.JS_IsException(result_const)) {
        quickjs.JS_FreeValue(ctx, result);
        runtime.warnLastException("SolidHost.updateState.call");
        return error.CallFailed;
    }
    quickjs.JS_FreeValue(ctx, result);

    const rc = quickjs.js_app_execute_jobs(runtime.handle, 0);
    if (rc < 0) {
        runtime.warnLastException("SolidHost.jobs");
        return error.CallFailed;
    }
}

fn createUpdateValue(
    ctx: *quickjs.JSContext,
    runtime: *jsruntime.JSRuntime,
    update: UpdateValue,
) !quickjs.JSValue {
    return switch (update) {
        .integer => |val| createIntValue(ctx, runtime, val),
        .string => |slice| createStringValue(ctx, runtime, slice),
    };
}

fn createIntValue(
    ctx: *quickjs.JSContext,
    runtime: *jsruntime.JSRuntime,
    value: i32,
) !quickjs.JSValue {
    const js_value = quickjs.JS_NewInt32(ctx, value);
    const js_const = quickjs.asValueConst(js_value);
    if (quickjs.JS_IsException(js_const)) {
        quickjs.JS_FreeValue(ctx, js_value);
        runtime.warnLastException("SolidHost.updateState.value");
        return error.CallFailed;
    }
    return js_value;
}

fn createStringValue(
    ctx: *quickjs.JSContext,
    runtime: *jsruntime.JSRuntime,
    value: []const u8,
) !quickjs.JSValue {
    const js_value = quickjs.JS_NewStringLen(ctx, @ptrCast(value.ptr), value.len);
    const js_const = quickjs.asValueConst(js_value);
    if (quickjs.JS_IsException(js_const)) {
        quickjs.JS_FreeValue(ctx, js_value);
        runtime.warnLastException("SolidHost.updateState.value");
        return error.CallFailed;
    }
    return js_value;
}

fn lookupHost(ctx: *quickjs.JSContext, global_const: quickjs.JSValueConst) !HostLookup {
    const name = "SolidHost\x00";
    const value = quickjs.JS_GetPropertyStr(ctx, global_const, @ptrCast(name.ptr));
    const const_value = quickjs.asValueConst(value);
    if (quickjs.JS_IsException(const_value) or !quickjs.JS_IsObject(const_value)) {
        quickjs.JS_FreeValue(ctx, value);
        return error.HostMissing;
    }
    return .{ .value = value, .const_value = const_value };
}

const HostFunction = struct {
    value: quickjs.JSValue,
    const_value: quickjs.JSValueConst,
};

fn lookupHostFunction(
    ctx: *quickjs.JSContext,
    host_const: quickjs.JSValueConst,
    comptime name: []const u8,
) !HostFunction {
    const prop = name ++ "\x00";
    const value = quickjs.JS_GetPropertyStr(ctx, host_const, @ptrCast(prop.ptr));
    const const_value = quickjs.asValueConst(value);
    if (quickjs.JS_IsException(const_value) or !quickjs.JS_IsFunction(ctx, const_value)) {
        quickjs.JS_FreeValue(ctx, value);
        return error.HostMissing;
    }
    return .{ .value = value, .const_value = const_value };
}

fn arrayLength(ctx: *quickjs.JSContext, array_const: quickjs.JSValueConst) !usize {
    const name = "length\x00";
    const value = quickjs.JS_GetPropertyStr(ctx, array_const, @ptrCast(name.ptr));
    defer quickjs.JS_FreeValue(ctx, value);
    const value_const = quickjs.asValueConst(value);
    if (quickjs.JS_IsException(value_const)) return error.CallFailed;
    var raw: u32 = 0;
    if (quickjs.JS_ToUint32(ctx, &raw, value_const) < 0) return error.CallFailed;
    if (raw <= 0) return 0;
    return @intCast(raw);
}

fn arrayEntry(
    ctx: *quickjs.JSContext,
    array_const: quickjs.JSValueConst,
    index: usize,
    buffer: *[32]u8,
) !quickjs.JSValue {
    const label = try std.fmt.bufPrintZ(buffer, "{d}", .{index});
    const value = quickjs.JS_GetPropertyStr(ctx, array_const, @ptrCast(label.ptr));
    const value_const = quickjs.asValueConst(value);
    if (quickjs.JS_IsException(value_const)) {
        quickjs.JS_FreeValue(ctx, value);
        return error.CallFailed;
    }
    return value;
}

fn applyOp(
    ctx: *quickjs.JSContext,
    allocator: std.mem.Allocator,
    obj: quickjs.JSValueConst,
    store: *types.NodeStore,
) !void {
    const name = try readStringProperty(ctx, allocator, obj, "op");
    log.info("Solid op '{s}'", .{name});

    if (std.mem.eql(u8, name, "create")) {
        try applyCreate(ctx, allocator, obj, store);
        return;
    }
    if (std.mem.eql(u8, name, "slot")) {
        try applySlot(ctx, obj, store);
        return;
    }
    if (std.mem.eql(u8, name, "text")) {
        try applyText(ctx, allocator, obj, store);
        return;
    }
    if (std.mem.eql(u8, name, "insert")) {
        try applyInsert(ctx, obj, store);
        return;
    }
    if (std.mem.eql(u8, name, "remove")) {
        try applyRemove(ctx, obj, store);
        return;
    }
    if (std.mem.eql(u8, name, "listen")) {
        try applyListen(ctx, allocator, obj, store);
        return;
    }
    if (std.mem.eql(u8, name, "set")) {
        try applySet(ctx, allocator, obj, store);
        return;
    }
    if (std.mem.eql(u8, name, "nativeSetStyle")) {
        try applyNativeStyle(ctx, allocator, obj, store);
        return;
    }

    log.debug("Unhandled Solid op: {s}", .{name});
}

fn applyCreate(
    ctx: *quickjs.JSContext,
    allocator: std.mem.Allocator,
    obj: quickjs.JSValueConst,
    store: *types.NodeStore,
) !void {
    const id = try readIntProperty(ctx, obj, "id");
    const tag = try readStringProperty(ctx, allocator, obj, "tag");
    try store.upsertElement(@intCast(id), tag);
    log.info("  create id={d} tag={s}", .{ id, tag });
}

fn applySlot(ctx: *quickjs.JSContext, obj: quickjs.JSValueConst, store: *types.NodeStore) !void {
    const id = try readIntProperty(ctx, obj, "id");
    try store.upsertSlot(@intCast(id));
}

fn applyText(
    ctx: *quickjs.JSContext,
    allocator: std.mem.Allocator,
    obj: quickjs.JSValueConst,
    store: *types.NodeStore,
) !void {
    const id = try readIntProperty(ctx, obj, "id");
    const text = try readStringProperty(ctx, allocator, obj, "text");
    defer allocator.free(text);
    try store.setTextNode(@intCast(id), text);
    log.info("  text id={d} len={d} value='{s}'", .{ id, text.len, text });
}

fn applyInsert(ctx: *quickjs.JSContext, obj: quickjs.JSValueConst, store: *types.NodeStore) !void {
    const parent_id = try readIntProperty(ctx, obj, "parent");
    const child_id = try readIntProperty(ctx, obj, "id");
    const before_raw = try readOptionalIntProperty(ctx, obj, "before");
    const before_id: ?u32 = if (before_raw) |value| blk: {
        if (value == 0) break :blk null;
        break :blk @intCast(value);
    } else null;
    try store.insert(@intCast(parent_id), @intCast(child_id), before_id);
    log.info("  insert parent={d} child={d} before={?d}", .{ parent_id, child_id, before_id });
}

fn applyRemove(ctx: *quickjs.JSContext, obj: quickjs.JSValueConst, store: *types.NodeStore) !void {
    const id = try readIntProperty(ctx, obj, "id");
    store.remove(@intCast(id));
    log.info("  remove id={d}", .{id});
}

fn applyListen(
    ctx: *quickjs.JSContext,
    allocator: std.mem.Allocator,
    obj: quickjs.JSValueConst,
    store: *types.NodeStore,
) !void {
    const id = try readIntProperty(ctx, obj, "id");
    const event = try readStringProperty(ctx, allocator, obj, "type");
    try store.addListener(@intCast(id), event);
    log.info("  listen id={d} type={s}", .{ id, event });
}

fn applySet(
    ctx: *quickjs.JSContext,
    allocator: std.mem.Allocator,
    obj: quickjs.JSValueConst,
    store: *types.NodeStore,
) !void {
    const id = try readIntProperty(ctx, obj, "id");
    const name = try readStringProperty(ctx, allocator, obj, "name");
    defer allocator.free(name);

    if (std.mem.eql(u8, name, "class") or std.mem.eql(u8, name, "className")) {
        const value = try readStringProperty(ctx, allocator, obj, "value");
        defer allocator.free(value);
        try store.setClassName(@intCast(id), value);
        log.info("  class id={d} value='{s}'", .{ id, value });
        return;
    }

    if (std.mem.eql(u8, name, "src")) {
        const value = try readStringProperty(ctx, allocator, obj, "value");
        defer allocator.free(value);
        try store.setImageSource(@intCast(id), value);
        log.info("  src id={d} value='{s}'", .{ id, value });
        return;
    }

    if (std.mem.eql(u8, name, "value")) {
        const value = try readStringProperty(ctx, allocator, obj, "value");
        defer allocator.free(value);
        try store.setInputValue(@intCast(id), value);
        log.info("  value id={d} len={d}", .{ id, value.len });
        return;
    }
}

fn applyNativeStyle(
    ctx: *quickjs.JSContext,
    allocator: std.mem.Allocator,
    obj: quickjs.JSValueConst,
    store: *types.NodeStore,
) !void {
    const id = try readIntProperty(ctx, obj, "id");
    const name = try readStringProperty(ctx, allocator, obj, "name");
    defer allocator.free(name);
    const value = try readStringProperty(ctx, allocator, obj, "value");
    defer allocator.free(value);

    store.setStyle(@intCast(id), name, value);
    log.info("  style id={d} name={s} value={s}", .{ id, name, value });
}

fn readIntProperty(
    ctx: *quickjs.JSContext,
    obj: quickjs.JSValueConst,
    comptime name: []const u8,
) !i64 {
    const prop = name ++ "\x00";
    const value = quickjs.JS_GetPropertyStr(ctx, obj, @ptrCast(prop.ptr));
    defer quickjs.JS_FreeValue(ctx, value);
    const value_const = quickjs.asValueConst(value);
    if (quickjs.JS_IsException(value_const)) return error.CallFailed;
    var out: u32 = 0;
    if (quickjs.JS_ToUint32(ctx, &out, value_const) < 0) return error.CallFailed;
    return out;
}

fn readOptionalIntProperty(
    ctx: *quickjs.JSContext,
    obj: quickjs.JSValueConst,
    comptime name: []const u8,
) !?i64 {
    const prop = name ++ "\x00";
    const value = quickjs.JS_GetPropertyStr(ctx, obj, @ptrCast(prop.ptr));
    defer quickjs.JS_FreeValue(ctx, value);
    const value_const = quickjs.asValueConst(value);
    if (quickjs.JS_IsException(value_const)) return error.CallFailed;
    if (quickjs.JS_IsUndefined(value_const) or quickjs.JS_IsNull(value_const)) {
        return null;
    }
    var out: u32 = 0;
    if (quickjs.JS_ToUint32(ctx, &out, value_const) < 0) return error.CallFailed;
    return out;
}

fn readStringProperty(
    ctx: *quickjs.JSContext,
    allocator: std.mem.Allocator,
    obj: quickjs.JSValueConst,
    comptime name: []const u8,
) ![]u8 {
    const prop = name ++ "\x00";
    const value = quickjs.JS_GetPropertyStr(ctx, obj, @ptrCast(prop.ptr));
    defer quickjs.JS_FreeValue(ctx, value);
    const value_const = quickjs.asValueConst(value);
    if (quickjs.JS_IsException(value_const)) return error.CallFailed;
    if (!quickjs.JS_IsString(value_const)) return error.InvalidResponse;
    var length: usize = 0;
    const cstr = quickjs.JS_ToCStringLen(ctx, &length, value_const) orelse return error.CallFailed;
    defer quickjs.JS_FreeCString(ctx, cstr);
    return try allocator.dupe(u8, cstr[0..length]);
}
