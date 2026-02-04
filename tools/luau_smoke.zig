const std = @import("std");
const luaz = @import("luaz");
const solidluau_embedded = @import("solidluau_embedded");

const RequireCtx = struct {
    allocator: std.mem.Allocator,
};

var require_cache_key: u8 = 0;

fn requireImpl(state_opt: ?luaz.State.LuaState) callconv(.c) c_int {
    const lua = luaz.Lua.fromState(state_opt.?);
    const base_top = lua.state.getTop();

    const ctx_ptr = lua.state.toLightUserdata(luaz.State.upvalueIndex(1)) orelse {
        lua.state.setTop(base_top);
        lua.state.pushLString("require missing ctx");
        lua.state.raiseError();
    };
    const ctx: *RequireCtx = @ptrCast(@alignCast(ctx_ptr));

    const module_z = lua.state.checkString(1);
    const module_full: []const u8 = module_z;
    const module_id = if (std.mem.endsWith(u8, module_full, ".luau")) module_full[0 .. module_full.len - 5] else module_full;

    lua.state.pushLightUserdata(@ptrCast(&require_cache_key));
    _ = lua.state.getTable(luaz.State.REGISTRYINDEX);
    if (lua.state.isNil(-1)) {
        lua.state.pop(1);
        lua.state.createTable(0, 64);
        lua.state.pushLightUserdata(@ptrCast(&require_cache_key));
        lua.state.pushValue(-2);
        lua.state.setTable(luaz.State.REGISTRYINDEX);
    }

    lua.state.pushLString(module_id);
    _ = lua.state.rawGet(-2);
    if (!lua.state.isNil(-1)) {
        lua.state.remove(-2);
        return 1;
    }
    lua.state.pop(1);

    const embedded_source = solidluau_embedded.get(module_id);
    var owned_source: ?[]u8 = null;
    defer if (owned_source) |bytes| ctx.allocator.free(bytes);

    const source_bytes: []const u8 = blk: {
        if (embedded_source) |src| break :blk src;

        var path_buf: [512]u8 = undefined;
        const path = if (std.mem.endsWith(u8, module_full, ".luau"))
            module_full
        else
            std.fmt.bufPrint(&path_buf, "{s}.luau", .{module_full}) catch {
                lua.state.setTop(base_top);
                lua.state.pushLString("require invalid module id");
                lua.state.raiseError();
            };

        var file = std.fs.cwd().openFile(path, .{ .mode = .read_only }) catch |err| {
            lua.state.setTop(base_top);
            lua.state.pushLString("require(");
            lua.state.pushLString(module_id);
            lua.state.pushLString(") open failed: ");
            lua.state.pushLString(@errorName(err));
            lua.state.concat(4);
            lua.state.raiseError();
        };
        defer file.close();

        const bytes = file.readToEndAlloc(ctx.allocator, 8 * 1024 * 1024) catch |err| {
            lua.state.setTop(base_top);
            lua.state.pushLString("require(");
            lua.state.pushLString(module_id);
            lua.state.pushLString(") read failed: ");
            lua.state.pushLString(@errorName(err));
            lua.state.concat(4);
            lua.state.raiseError();
        };

        owned_source = bytes;
        break :blk bytes;
    };

    const compile_result = luaz.Compiler.compile(source_bytes, .{}) catch |err| {
        lua.state.setTop(base_top);
        lua.state.pushLString("require(");
        lua.state.pushLString(module_id);
        lua.state.pushLString(") compile failed: ");
        lua.state.pushLString(@errorName(err));
        lua.state.concat(4);
        lua.state.raiseError();
    };
    defer compile_result.deinit();

    if (compile_result == .err) {
        const message = compile_result.err;
        lua.state.setTop(base_top);
        lua.state.pushLString("require(");
        lua.state.pushLString(module_id);
        lua.state.pushLString(") compile error: ");
        lua.state.pushLString(message);
        lua.state.concat(4);
        lua.state.raiseError();
    }

    const load_status = lua.state.load(module_z, compile_result.ok, 0);
    switch (load_status) {
        .ok => {},
        else => {
            lua.state.setTop(base_top);
            lua.state.pushLString("require(");
            lua.state.pushLString(module_id);
            lua.state.pushLString(") load error: ");
            lua.state.pushLString(@tagName(load_status));
            lua.state.concat(4);
            lua.state.raiseError();
        },
    }

    const call_status = lua.state.pcall(0, 1, 0);
    switch (call_status) {
        .ok => {},
        else => {
            const err_z = lua.state.toString(-1) orelse "(non-string error)";
            const err_message: []const u8 = err_z;
            lua.state.setTop(base_top);
            lua.state.pushLString("require(");
            lua.state.pushLString(module_id);
            lua.state.pushLString(") runtime error: ");
            lua.state.pushLString(err_message);
            lua.state.concat(4);
            lua.state.raiseError();
        },
    }

    if (lua.state.isNil(-1)) {
        lua.state.pop(1);
        lua.state.pushBoolean(true);
    }

    lua.state.pushLString(module_id);
    lua.state.pushValue(-2);
    lua.state.rawSet(-4);
    lua.state.remove(-2);

    return 1;
}

fn requireModule(lua: *luaz.Lua, id: []const u8) !void {
    const base_top = lua.state.getTop();
    defer lua.state.setTop(base_top);

    _ = lua.state.getGlobal("require");
    lua.state.pushLString(id);
    const status = lua.state.pcall(1, 1, 0);
    if (status != .ok) {
        const msg = lua.state.toString(-1) orelse "(non-string error)";
        std.debug.print("{s}\n", .{msg});
        return error.LuaRuntime;
    }
}

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    var lua = try luaz.Lua.init(&allocator);
    defer lua.deinit();

    lua.openLibs();

    var ctx: RequireCtx = .{ .allocator = allocator };
    lua.state.pushLightUserdata(@ptrCast(&ctx));
    lua.state.pushCClosureK(requireImpl, null, 1, null);
    lua.state.setGlobal("require");

    try requireModule(&lua, "luau/_smoke/ui_refs");
    try requireModule(&lua, "luau/_smoke/health_bar");
}
