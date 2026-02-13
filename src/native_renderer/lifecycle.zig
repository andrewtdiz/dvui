const std = @import("std");

const luaz = @import("luaz");
const luau_ui = @import("luau_ui");

const retained = @import("retained");
const solidluau_embedded = @import("solidluau_embedded");
const types = @import("types.zig");
const utils = @import("utils.zig");
const Renderer = types.Renderer;

const lua_script_paths = [_][]const u8{
    "luau/index.luau",
};
const max_lua_script_bytes: usize = 1024 * 1024;
const max_lua_error_len: usize = 120;
var require_cache_key: u8 = 0;

// ============================================================
// Logging
// ============================================================

pub fn logMessage(renderer: *Renderer, level: u8, comptime fmt: []const u8, args: anytype) void {
    if (renderer.pending_destroy or renderer.destroy_started) return;
    if (renderer.log_cb) |log_fn| {
        var buffer: [512]u8 = undefined;
        const msg = std.fmt.bufPrint(&buffer, fmt, args) catch return;
        const msg_ptr: [*]const u8 = @ptrCast(msg.ptr);
        renderer.callback_depth += 1;
        defer {
            renderer.callback_depth -= 1;
            tryFinalize(renderer);
        }
        log_fn(level, msg_ptr, msg.len);
    }
}

// ============================================================
// Event Dispatch
// ============================================================

pub fn sendFrameEvent(renderer: *Renderer) void {
    if (renderer.event_cb) |event_fn| {
        var payload: [8]u8 = undefined;
        std.mem.writeInt(u32, payload[0..4], 0, .little);
        std.mem.writeInt(u32, payload[4..], @intCast(renderer.headers.items.len), .little);
        const name = "frame";
        renderer.callback_depth += 1;
        defer {
            renderer.callback_depth -= 1;
            tryFinalize(renderer);
        }
        event_fn(name, name.len, &payload, payload.len);
    }
}

// ============================================================
// Luau Lifecycle
// ============================================================

pub fn isLuaFuncPresent(lua: *luaz.Lua, name: []const u8) bool {
    const globals = lua.globals();
    const lua_func = globals.get(name, luaz.Lua.Function) catch return false;
    lua_func.deinit();
    return true;
}

pub fn logLuaError(renderer: *Renderer, label: []const u8, err: anyerror) void {
    const err_name = @errorName(err);
    const err_msg = if (err_name.len > max_lua_error_len) err_name[0..max_lua_error_len] else err_name;
    logMessage(renderer, 3, "lua {s} failed: {s}", .{ label, err_msg });
}

const Json5Error = std.mem.Allocator.Error || error{
    UnterminatedString,
    UnterminatedComment,
    InvalidEscape,
    InvalidUnicodeEscape,
};

const Json5ContainerKind = enum { object, array };
const Json5Expect = enum { key_or_end, colon, value_or_end, comma_or_end };
const Json5Container = struct { kind: Json5ContainerKind, expect: Json5Expect };

fn json5SkipSpaceAndComments(src: []const u8, start: usize) Json5Error!usize {
    var i = start;
    while (i < src.len) {
        const c = src[i];
        if (std.ascii.isWhitespace(c)) {
            i += 1;
            continue;
        }

        if (c == '/' and i + 1 < src.len) {
            const next = src[i + 1];
            if (next == '/') {
                i += 2;
                while (i < src.len and src[i] != '\n' and src[i] != '\r') : (i += 1) {}
                continue;
            }
            if (next == '*') {
                i += 2;
                while (i + 1 < src.len and !(src[i] == '*' and src[i + 1] == '/')) : (i += 1) {}
                if (i + 1 >= src.len) return error.UnterminatedComment;
                i += 2;
                continue;
            }
        }
        break;
    }
    return i;
}

fn json5IsIdentStart(c: u8) bool {
    return (c >= 'A' and c <= 'Z') or (c >= 'a' and c <= 'z') or c == '_' or c == '$';
}

fn json5IsIdentContinue(c: u8) bool {
    return json5IsIdentStart(c) or (c >= '0' and c <= '9');
}

fn json5IsHexDigit(c: u8) bool {
    return (c >= '0' and c <= '9') or (c >= 'a' and c <= 'f') or (c >= 'A' and c <= 'F');
}

fn json5HexValue(c: u8) u4 {
    if (c >= '0' and c <= '9') return @intCast(c - '0');
    if (c >= 'a' and c <= 'f') return @intCast(10 + (c - 'a'));
    return @intCast(10 + (c - 'A'));
}

fn json5EmitUnicodeScalar(out: *std.ArrayList(u8), allocator: std.mem.Allocator, scalar: u21) !void {
    if (scalar == '"') {
        try out.appendSlice(allocator, "\\\"");
        return;
    }
    if (scalar == '\\') {
        try out.appendSlice(allocator, "\\\\");
        return;
    }
    if (scalar == '\n') {
        try out.appendSlice(allocator, "\\n");
        return;
    }
    if (scalar == '\r') {
        try out.appendSlice(allocator, "\\r");
        return;
    }
    if (scalar == '\t') {
        try out.appendSlice(allocator, "\\t");
        return;
    }
    if (scalar == 0x08) {
        try out.appendSlice(allocator, "\\b");
        return;
    }
    if (scalar == 0x0C) {
        try out.appendSlice(allocator, "\\f");
        return;
    }
    if (scalar < 0x20) {
        try out.writer(allocator).print("\\u{X:0>4}", .{@as(u16, @intCast(scalar))});
        return;
    }

    var buf: [4]u8 = undefined;
    const len_u3 = std.unicode.utf8Encode(scalar, &buf) catch {
        try out.appendSlice(allocator, "\xEF\xBF\xBD");
        return;
    };
    const len: usize = @intCast(len_u3);
    try out.appendSlice(allocator, buf[0..len]);
}

fn json5ParseHex(src: []const u8, start: usize, count: usize) Json5Error!struct { value: u32, end: usize } {
    if (start + count > src.len) return error.InvalidUnicodeEscape;
    var value: u32 = 0;
    var i = start;
    while (i < start + count) : (i += 1) {
        const c = src[i];
        if (!json5IsHexDigit(c)) return error.InvalidUnicodeEscape;
        value = (value << 4) | json5HexValue(c);
    }
    return .{ .value = value, .end = start + count };
}

fn json5ParseUnicodeEscape(src: []const u8, start: usize) Json5Error!struct { scalar: u21, end: usize } {
    if (start >= src.len) return error.InvalidUnicodeEscape;

    if (src[start] == '{') {
        var i = start + 1;
        if (i >= src.len) return error.InvalidUnicodeEscape;
        var value: u32 = 0;
        var digits: usize = 0;
        while (i < src.len and src[i] != '}') : (i += 1) {
            const c = src[i];
            if (!json5IsHexDigit(c)) return error.InvalidUnicodeEscape;
            value = (value << 4) | json5HexValue(c);
            digits += 1;
            if (digits > 6) return error.InvalidUnicodeEscape;
        }
        if (i >= src.len or src[i] != '}') return error.InvalidUnicodeEscape;
        const scalar: u21 = @intCast(value);
        return .{ .scalar = scalar, .end = i + 1 };
    }

    const parsed = try json5ParseHex(src, start, 4);
    const scalar: u21 = @intCast(parsed.value);
    return .{ .scalar = scalar, .end = parsed.end };
}

fn json5ParseString(out: *std.ArrayList(u8), allocator: std.mem.Allocator, src: []const u8, start: usize) Json5Error!usize {
    const delim = src[start];
    var i = start + 1;
    try out.append(allocator, '"');

    while (i < src.len) {
        const c = src[i];
        if (c == delim) {
            try out.append(allocator, '"');
            return i + 1;
        }
        if (c == '\\') {
            i += 1;
            if (i >= src.len) return error.InvalidEscape;
            const esc = src[i];
            if (esc == '\n') {
                i += 1;
                continue;
            }
            if (esc == '\r') {
                if (i + 1 < src.len and src[i + 1] == '\n') {
                    i += 2;
                } else {
                    i += 1;
                }
                continue;
            }

            switch (esc) {
                '"', '\\', '/' => try json5EmitUnicodeScalar(out, allocator, @intCast(esc)),
                '\'' => try json5EmitUnicodeScalar(out, allocator, '\''),
                'b' => try json5EmitUnicodeScalar(out, allocator, 0x08),
                'f' => try json5EmitUnicodeScalar(out, allocator, 0x0C),
                'n' => try json5EmitUnicodeScalar(out, allocator, '\n'),
                'r' => try json5EmitUnicodeScalar(out, allocator, '\r'),
                't' => try json5EmitUnicodeScalar(out, allocator, '\t'),
                'v' => try json5EmitUnicodeScalar(out, allocator, 0x0B),
                '0' => try json5EmitUnicodeScalar(out, allocator, 0x00),
                'x' => {
                    const parsed = try json5ParseHex(src, i + 1, 2);
                    try json5EmitUnicodeScalar(out, allocator, @intCast(parsed.value));
                    i = parsed.end - 1;
                },
                'u' => {
                    const ustart = i + 1;
                    const parsed = try json5ParseUnicodeEscape(src, ustart);
                    var scalar = parsed.scalar;
                    var end = parsed.end;

                    if (scalar >= 0xD800 and scalar <= 0xDBFF and end + 1 < src.len and src[end] == '\\' and src[end + 1] == 'u') {
                        const next_parsed = json5ParseUnicodeEscape(src, end + 2) catch null;
                        if (next_parsed) |np| {
                            const low = np.scalar;
                            if (low >= 0xDC00 and low <= 0xDFFF) {
                                const high_ten: u32 = @intCast(scalar - 0xD800);
                                const low_ten: u32 = @intCast(low - 0xDC00);
                                const combined: u32 = 0x10000 + ((high_ten << 10) | low_ten);
                                scalar = @intCast(combined);
                                end = np.end;
                            }
                        }
                    }

                    try json5EmitUnicodeScalar(out, allocator, scalar);
                    i = end - 1;
                },
                else => try json5EmitUnicodeScalar(out, allocator, @intCast(esc)),
            }

            i += 1;
            continue;
        }

        try json5EmitUnicodeScalar(out, allocator, @intCast(c));
        i += 1;
    }

    return error.UnterminatedString;
}

fn json5ParseNumberToken(src: []const u8, start: usize) usize {
    var i = start;
    if (i < src.len and (src[i] == '+' or src[i] == '-')) i += 1;
    if (i + 1 < src.len and src[i] == '0' and (src[i + 1] == 'x' or src[i + 1] == 'X')) {
        i += 2;
        while (i < src.len and json5IsHexDigit(src[i])) : (i += 1) {}
        return i;
    }
    if (i < src.len and src[i] == '.') {
        i += 1;
        while (i < src.len and std.ascii.isDigit(src[i])) : (i += 1) {}
    } else {
        while (i < src.len and std.ascii.isDigit(src[i])) : (i += 1) {}
        if (i < src.len and src[i] == '.') {
            i += 1;
            while (i < src.len and std.ascii.isDigit(src[i])) : (i += 1) {}
        }
    }
    if (i < src.len and (src[i] == 'e' or src[i] == 'E')) {
        i += 1;
        if (i < src.len and (src[i] == '+' or src[i] == '-')) i += 1;
        while (i < src.len and std.ascii.isDigit(src[i])) : (i += 1) {}
    }
    return i;
}

fn json5EmitNumber(out: *std.ArrayList(u8), allocator: std.mem.Allocator, token: []const u8) !void {
    var s = token;
    if (s.len == 0) {
        try out.appendSlice(allocator, "0");
        return;
    }
    if (s[0] == '+') s = s[1..];

    var negative = false;
    if (s.len > 0 and s[0] == '-') {
        negative = true;
        s = s[1..];
    }

    if (s.len >= 2 and s[0] == '0' and (s[1] == 'x' or s[1] == 'X')) {
        const digits = s[2..];
        const value = std.fmt.parseInt(u64, digits, 16) catch 0;
        if (negative) {
            try out.writer(allocator).print("-{d}", .{value});
        } else {
            try out.writer(allocator).print("{d}", .{value});
        }
        return;
    }

    if (s.len >= 1 and s[0] == '.') {
        try out.append(allocator, if (negative) '-' else '0');
        if (negative) {
            try out.append(allocator, '0');
        }
        try out.appendSlice(allocator, s);
        return;
    }
    if (s.len >= 2 and s[0] == '0' and s[1] == '.') {
        if (negative) try out.append(allocator, '-');
        try out.appendSlice(allocator, s);
        if (s[s.len - 1] == '.') try out.append(allocator, '0');
        return;
    }

    if (s.len > 0 and s[s.len - 1] == '.') {
        if (negative) try out.append(allocator, '-');
        try out.appendSlice(allocator, s);
        try out.append(allocator, '0');
        return;
    }

    const is_float = std.mem.indexOfScalar(u8, s, '.') != null or std.mem.indexOfAny(u8, s, "eE") != null;
    if (is_float) {
        const parsed = std.fmt.parseFloat(f64, if (negative) token else s) catch 0.0;
        try out.writer(allocator).print("{d}", .{parsed});
        return;
    }

    const full = if (negative) token else s;
    const parsed = std.fmt.parseInt(i64, full, 10) catch 0;
    try out.writer(allocator).print("{d}", .{parsed});
}

fn normalizeJson5(allocator: std.mem.Allocator, src: []const u8) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);

    var stack: std.ArrayList(Json5Container) = .empty;
    defer stack.deinit(allocator);

    var i: usize = 0;
    if (src.len >= 3 and src[0] == 0xEF and src[1] == 0xBB and src[2] == 0xBF) {
        i = 3;
    }

    while (true) {
        i = try json5SkipSpaceAndComments(src, i);
        if (i >= src.len) break;
        const c = src[i];

        const has_ctx = stack.items.len > 0;
        const top_index = if (has_ctx) stack.items.len - 1 else 0;
        const in_object_key = has_ctx and stack.items[top_index].kind == .object and stack.items[top_index].expect == .key_or_end;

        if (c == '"' or c == '\'') {
            i = try json5ParseString(&out, allocator, src, i);
            if (in_object_key) {
                stack.items[top_index].expect = .colon;
            } else if (has_ctx) {
                stack.items[top_index].expect = .comma_or_end;
            }
            continue;
        }

        if (c == ',' and has_ctx) {
            const next_i = try json5SkipSpaceAndComments(src, i + 1);
            if (next_i < src.len and (src[next_i] == '}' or src[next_i] == ']')) {
                i += 1;
                continue;
            }
            try out.append(allocator, ',');
            stack.items[top_index].expect = if (stack.items[top_index].kind == .object) .key_or_end else .value_or_end;
            i += 1;
            continue;
        }

        if (c == ':' and has_ctx and stack.items[top_index].kind == .object) {
            try out.append(allocator, ':');
            stack.items[top_index].expect = .value_or_end;
            i += 1;
            continue;
        }

        if (c == '{') {
            if (has_ctx and !in_object_key) {
                stack.items[top_index].expect = .comma_or_end;
            }
            try out.append(allocator, '{');
            try stack.append(allocator, .{ .kind = .object, .expect = .key_or_end });
            i += 1;
            continue;
        }

        if (c == '[') {
            if (has_ctx and !in_object_key) {
                stack.items[top_index].expect = .comma_or_end;
            }
            try out.append(allocator, '[');
            try stack.append(allocator, .{ .kind = .array, .expect = .value_or_end });
            i += 1;
            continue;
        }

        if (c == '}' or c == ']') {
            try out.append(allocator, c);
            if (has_ctx) {
                _ = stack.pop();
            }
            i += 1;
            continue;
        }

        if (c == '+' or c == '-' or c == '.' or std.ascii.isDigit(c)) {
            const end = json5ParseNumberToken(src, i);
            const token = src[i..end];
            try json5EmitNumber(&out, allocator, token);
            if (in_object_key) {
                stack.items[top_index].expect = .colon;
            } else if (has_ctx) {
                stack.items[top_index].expect = .comma_or_end;
            }
            i = end;
            continue;
        }

        if (json5IsIdentStart(c)) {
            var end = i + 1;
            while (end < src.len and json5IsIdentContinue(src[end])) : (end += 1) {}
            const ident = src[i..end];

            if (in_object_key) {
                try out.append(allocator, '"');
                try out.appendSlice(allocator, ident);
                try out.append(allocator, '"');
                stack.items[top_index].expect = .colon;
                i = end;
                continue;
            }

            if (std.mem.eql(u8, ident, "true") or std.mem.eql(u8, ident, "false") or std.mem.eql(u8, ident, "null")) {
                try out.appendSlice(allocator, ident);
            } else if (std.mem.eql(u8, ident, "Infinity") or std.mem.eql(u8, ident, "NaN") or std.mem.eql(u8, ident, "undefined")) {
                try out.appendSlice(allocator, "null");
            } else {
                try out.append(allocator, '"');
                try out.appendSlice(allocator, ident);
                try out.append(allocator, '"');
            }

            if (has_ctx) {
                stack.items[top_index].expect = .comma_or_end;
            }
            i = end;
            continue;
        }

        try out.append(allocator, c);
        i += 1;
    }

    return out.toOwnedSlice(allocator);
}

fn pushJsonValue(lua: luaz.Lua, value: std.json.Value) void {
    lua.state.rawCheckStack(8);
    switch (value) {
        .null => lua.state.pushNil(),
        .bool => |b| lua.state.pushBoolean(b),
        .integer => |i| {
            const min_i: i64 = @intCast(std.math.minInt(luaz.State.Integer));
            const max_i: i64 = @intCast(std.math.maxInt(luaz.State.Integer));
            if (i >= min_i and i <= max_i) {
                lua.state.pushInteger(@intCast(i));
            } else {
                lua.state.pushNumber(@floatFromInt(i));
            }
        },
        .float => |f| lua.state.pushNumber(f),
        .number_string => |s| {
            const parsed = std.fmt.parseFloat(f64, s) catch null;
            if (parsed) |n| {
                lua.state.pushNumber(n);
            } else {
                lua.state.pushLString(s);
            }
        },
        .string => |s| lua.state.pushLString(s),
        .array => |arr| {
            const n: u32 = std.math.cast(u32, arr.items.len) orelse std.math.maxInt(u32);
            lua.state.createTable(n, 0);
            for (arr.items, 0..) |item, idx| {
                pushJsonValue(lua, item);
                const lua_index = std.math.cast(i32, idx + 1);
                if (lua_index) |n_idx| {
                    lua.state.rawSetI(-2, n_idx);
                } else {
                    lua.state.pop(1);
                    break;
                }
            }
        },
        .object => |obj| {
            const n: u32 = std.math.cast(u32, obj.count()) orelse std.math.maxInt(u32);
            lua.state.createTable(0, n);
            var it = obj.iterator();
            while (it.next()) |entry| {
                lua.state.pushLString(entry.key_ptr.*);
                pushJsonValue(lua, entry.value_ptr.*);
                lua.state.setTable(-3);
            }
        },
    }
}

fn dvuiDofile(state_opt: ?luaz.State.LuaState) callconv(.c) c_int {
    const lua = luaz.Lua.fromState(state_opt.?);
    const base_top = lua.state.getTop();

    const renderer_ptr = lua.state.toLightUserdata(luaz.State.upvalueIndex(1)) orelse {
        lua.state.setTop(base_top);
        lua.state.pushNil();
        lua.state.pushString("dvui_dofile missing renderer");
        return 2;
    };
    const renderer: *Renderer = @ptrCast(@alignCast(renderer_ptr));

    const path_z = lua.state.checkString(1);
    const path: []const u8 = path_z;

    var file = std.fs.cwd().openFile(path, .{ .mode = .read_only }) catch |err| {
        lua.state.setTop(base_top);
        lua.state.pushNil();
        lua.state.pushString("dofile(");
        lua.state.pushLString(path);
        lua.state.pushString(") open failed: ");
        lua.state.pushLString(@errorName(err));
        lua.state.concat(4);
        return 2;
    };
    defer file.close();

    const script_bytes = file.readToEndAlloc(renderer.allocator, max_lua_script_bytes) catch |err| {
        lua.state.setTop(base_top);
        lua.state.pushNil();
        lua.state.pushString("dofile(");
        lua.state.pushLString(path);
        lua.state.pushString(") read failed: ");
        lua.state.pushLString(@errorName(err));
        lua.state.concat(4);
        return 2;
    };
    defer renderer.allocator.free(script_bytes);

    const compile_result = luaz.Compiler.compile(script_bytes, .{}) catch |err| {
        lua.state.setTop(base_top);
        lua.state.pushNil();
        lua.state.pushString("dofile(");
        lua.state.pushLString(path);
        lua.state.pushString(") compile failed: ");
        lua.state.pushLString(@errorName(err));
        lua.state.concat(4);
        return 2;
    };
    defer compile_result.deinit();

    if (compile_result == .err) {
        const message = compile_result.err;
        const trimmed = if (message.len > max_lua_error_len) message[0..max_lua_error_len] else message;

        lua.state.setTop(base_top);
        lua.state.pushNil();
        lua.state.pushString("dofile(");
        lua.state.pushLString(path);
        lua.state.pushString(") compile error: ");
        lua.state.pushLString(trimmed);
        lua.state.concat(4);
        return 2;
    }

    const load_status = lua.state.load(path_z, compile_result.ok, 0);
    switch (load_status) {
        .ok => {},
        .errmem => {
            lua.state.setTop(base_top);
            lua.state.pushNil();
            lua.state.pushString("dofile(");
            lua.state.pushLString(path);
            lua.state.pushString(") load out of memory");
            lua.state.concat(3);
            return 2;
        },
        else => {
            lua.state.setTop(base_top);
            lua.state.pushNil();
            lua.state.pushString("dofile(");
            lua.state.pushLString(path);
            lua.state.pushString(") load failed");
            lua.state.concat(3);
            return 2;
        },
    }

    const call_status = lua.state.pcall(0, 1, 0);
    switch (call_status) {
        .ok => {
            const new_top = lua.state.getTop();
            return @intCast(new_top - base_top);
        },
        else => {
            var err_message_buf: [max_lua_error_len]u8 = undefined;
            var err_message: []const u8 = @tagName(call_status);

            if (lua.state.getTop() > base_top) {
                if (lua.state.toString(-1)) |err_z| {
                    const err_raw: []const u8 = err_z;
                    const n: usize = @min(err_raw.len, max_lua_error_len);
                    std.mem.copyForwards(u8, err_message_buf[0..n], err_raw[0..n]);
                    err_message = err_message_buf[0..n];
                }
            }

            lua.state.setTop(base_top);
            lua.state.pushNil();
            lua.state.pushString("dofile(");
            lua.state.pushLString(path);
            lua.state.pushString(") runtime error: ");
            lua.state.pushLString(err_message);
            lua.state.concat(4);
            return 2;
        },
    }
}

fn dvuiRequire(state_opt: ?luaz.State.LuaState) callconv(.c) c_int {
    const lua = luaz.Lua.fromState(state_opt.?);
    const base_top = lua.state.getTop();

    const renderer_ptr = lua.state.toLightUserdata(luaz.State.upvalueIndex(1)) orelse {
        lua.state.setTop(base_top);
        lua.state.pushLString("require missing renderer");
        lua.state.raiseError();
    };
    const renderer: *Renderer = @ptrCast(@alignCast(renderer_ptr));

    const module_z = lua.state.checkString(1);
    const module_full: []const u8 = module_z;
    const module_is_luau = std.mem.endsWith(u8, module_full, ".luau");
    const module_is_json = std.mem.endsWith(u8, module_full, ".json") or std.mem.endsWith(u8, module_full, ".json5");
    const module_id = if (module_is_luau) module_full[0 .. module_full.len - 5] else module_full;

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
    defer if (owned_source) |bytes| renderer.allocator.free(bytes);

    const source_bytes: []const u8 = blk: {
        if (embedded_source) |src| break :blk src;

        var path_buf: [512]u8 = undefined;
        const path = if (module_is_luau or module_is_json)
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

        const bytes = file.readToEndAlloc(renderer.allocator, max_lua_script_bytes) catch |err| {
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

    if (module_is_json) {
        const normalized = normalizeJson5(renderer.allocator, source_bytes) catch |err| {
            lua.state.setTop(base_top);
            lua.state.pushLString("require(");
            lua.state.pushLString(module_id);
            lua.state.pushLString(") json5 normalize failed: ");
            lua.state.pushLString(@errorName(err));
            lua.state.concat(4);
            lua.state.raiseError();
        };
        defer renderer.allocator.free(normalized);

        const parsed = std.json.parseFromSlice(std.json.Value, renderer.allocator, normalized, .{ .allocate = .alloc_always }) catch |err| {
            lua.state.setTop(base_top);
            lua.state.pushLString("require(");
            lua.state.pushLString(module_id);
            lua.state.pushLString(") json5 parse failed: ");
            lua.state.pushLString(@errorName(err));
            lua.state.concat(4);
            lua.state.raiseError();
        };
        defer parsed.deinit();

        pushJsonValue(lua, parsed.value);
        if (lua.state.isNil(-1)) {
            lua.state.pop(1);
            lua.state.pushBoolean(true);
        }
        lua.state.pushLString(module_id);
        lua.state.pushValue(-2);
        lua.state.setTable(-4);
        lua.state.remove(-2);
        return 1;
    }

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
        const trimmed = if (message.len > max_lua_error_len) message[0..max_lua_error_len] else message;
        lua.state.setTop(base_top);
        lua.state.pushLString("require(");
        lua.state.pushLString(module_id);
        lua.state.pushLString(") compile error: ");
        lua.state.pushLString(trimmed);
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
            var err_message_buf: [max_lua_error_len]u8 = undefined;
            var err_message: []const u8 = @tagName(call_status);
            if (lua.state.getTop() > base_top) {
                if (lua.state.toString(-1)) |err_z| {
                    const err_raw: []const u8 = err_z;
                    const n: usize = @min(err_raw.len, max_lua_error_len);
                    std.mem.copyForwards(u8, err_message_buf[0..n], err_raw[0..n]);
                    err_message = err_message_buf[0..n];
                }
            }
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
    lua.state.setTable(-4);
    lua.state.remove(-2);
    return 1;
}

fn registerLuaFileLoader(renderer: *Renderer, lua: *luaz.Lua) void {
    lua.state.pushLightUserdata(@ptrCast(renderer));
    lua.state.pushCClosureK(dvuiDofile, "dvui_dofile", 1, null);
    lua.state.setGlobal("dvui_dofile");
    lua.state.pushLightUserdata(@ptrCast(renderer));
    lua.state.pushCClosureK(dvuiRequire, "require", 1, null);
    lua.state.setGlobal("require");
}

fn loadLuaScript(renderer: *Renderer) bool {
    var file_opt: ?std.fs.File = null;
    var chosen_path: []const u8 = "";

    if (renderer.lua_entry_path) |entry_path| {
        file_opt = if (std.fs.path.isAbsolute(entry_path))
            std.fs.openFileAbsolute(entry_path, .{ .mode = .read_only }) catch |err| {
                logMessage(renderer, 3, "lua script open failed: {s} ({s})", .{ entry_path, @errorName(err) });
                return false;
            }
        else
            std.fs.cwd().openFile(entry_path, .{ .mode = .read_only }) catch |err| {
                logMessage(renderer, 3, "lua script open failed: {s} ({s})", .{ entry_path, @errorName(err) });
                return false;
            };
        chosen_path = entry_path;
    } else {
        for (lua_script_paths) |candidate| {
            file_opt = std.fs.cwd().openFile(candidate, .{ .mode = .read_only }) catch null;
            if (file_opt != null) {
                chosen_path = candidate;
                break;
            }
        }

        if (file_opt == null) {
            logMessage(renderer, 3, "lua script open failed (no candidate found)", .{});
            return false;
        }
    }

    var file = file_opt.?;
    defer file.close();

    const script_bytes = file.readToEndAlloc(renderer.allocator, max_lua_script_bytes) catch |err| {
        logLuaError(renderer, "script read", err);
        return false;
    };
    defer renderer.allocator.free(script_bytes);

    if (renderer.lua_state) |lua_state| {
        logMessage(renderer, 1, "lua script: {s}", .{chosen_path});
        const compile_result = luaz.Compiler.compile(script_bytes, .{}) catch |err| {
            logLuaError(renderer, "script compile", err);
            return false;
        };
        defer compile_result.deinit();
        if (compile_result == .err) {
            const message = compile_result.err;
            const trimmed = if (message.len > max_lua_error_len) message[0..max_lua_error_len] else message;
            logMessage(renderer, 3, "lua script compile error: {s}", .{trimmed});
            return false;
        }
        if (renderer.lua_app_module) |app_module| {
            lua_state.state.pushLString(app_module);
            lua_state.state.setGlobal("__dvui_app_module");
        }
        const exec_result = lua_state.exec(compile_result.ok, void) catch |err| {
            logLuaError(renderer, "script exec", err);
            return false;
        };
        switch (exec_result) {
            .ok => return true,
            else => {
                logMessage(renderer, 3, "lua script exec did not complete", .{});
                return false;
            },
        }
    }

    logMessage(renderer, 3, "lua state missing", .{});
    return false;
}

fn callLuaInit(renderer: *Renderer) bool {
    if (renderer.lua_state) |lua_state| {
        if (!isLuaFuncPresent(lua_state, "init")) {
            return true;
        }
        const globals = lua_state.globals();
        const call_result = globals.call("init", .{}, void) catch |err| {
            logLuaError(renderer, "init", err);
            return false;
        };
        switch (call_result) {
            .ok => return true,
            else => {
                logMessage(renderer, 3, "lua init did not complete", .{});
                return false;
            },
        }
    }
    return false;
}

pub fn teardownLua(renderer: *Renderer) void {
    if (renderer.lua_ready) {
        if (renderer.lua_ui) |lua_ui| {
            lua_ui.deinit();
        }
        renderer.lua_ready = false;
    }
    if (renderer.lua_ui) |lua_ui| {
        renderer.allocator.destroy(lua_ui);
        renderer.lua_ui = null;
    }
    if (renderer.lua_state) |lua_state| {
        lua_state.deinit();
        renderer.allocator.destroy(lua_state);
        renderer.lua_state = null;
    }
}

pub fn ensureRetainedStore(renderer: *Renderer) !*retained.NodeStore {
    if (renderer.retained_store_ready) {
        if (utils.retainedStore(renderer)) |store| {
            return store;
        }
        renderer.retained_store_ready = false;
    }

    const store = blk: {
        if (utils.retainedStore(renderer)) |existing| {
            break :blk existing;
        }
        const allocated = renderer.allocator.create(retained.NodeStore) catch {
            logMessage(renderer, 3, "retained store alloc failed", .{});
            return error.OutOfMemory;
        };
        renderer.retained_store_ptr = allocated;
        break :blk allocated;
    };

    store.init(renderer.allocator) catch |err| {
        logMessage(renderer, 3, "retained store init failed: {s}", .{@errorName(err)});
        return err;
    };
    renderer.retained_store_ready = true;
    return store;
}


fn initLua(renderer: *Renderer) void {
    if (renderer.lua_ready) return;

    const store = ensureRetainedStore(renderer) catch |err| {
        logLuaError(renderer, "retained store", err);
        return;
    };

    const lua_ptr = renderer.allocator.create(luaz.Lua) catch |err| {
        logLuaError(renderer, "state alloc", err);
        return;
    };
    lua_ptr.* = luaz.Lua.init(&renderer.allocator) catch |err| {
        renderer.allocator.destroy(lua_ptr);
        logLuaError(renderer, "state init", err);
        return;
    };
    lua_ptr.openLibs();
    registerLuaFileLoader(renderer, lua_ptr);

    const lua_ui_ptr = renderer.allocator.create(luau_ui.LuaUi) catch |err| {
        lua_ptr.deinit();
        renderer.allocator.destroy(lua_ptr);
        logLuaError(renderer, "ui alloc", err);
        return;
    };
    lua_ui_ptr.init(store, lua_ptr, renderer.log_cb) catch |err| {
        renderer.allocator.destroy(lua_ui_ptr);
        lua_ptr.deinit();
        renderer.allocator.destroy(lua_ptr);
        logLuaError(renderer, "ui init", err);
        return;
    };

    renderer.lua_state = lua_ptr;
    renderer.lua_ui = lua_ui_ptr;

    if (!loadLuaScript(renderer)) {
        teardownLua(renderer);
        return;
    }
    if (!callLuaInit(renderer)) {
        teardownLua(renderer);
        return;
    }

    renderer.lua_ready = true;
    logMessage(renderer, 1, "lua ready", .{});
}

pub fn sendWindowClosedEvent(renderer: *Renderer) void {
    if (renderer.event_cb) |event_fn| {
        var payload: [4]u8 = .{ 0, 0, 0, 0 };
        const name = "window_closed";
        renderer.callback_depth += 1;
        defer {
            renderer.callback_depth -= 1;
            tryFinalize(renderer);
        }
        event_fn(name, name.len, &payload, payload.len);
    }
}

pub fn sendWindowResizeEvent(renderer: *Renderer, width: u32, height: u32, pixel_width: u32, pixel_height: u32) void {
    if (renderer.event_cb) |event_fn| {
        var payload: [16]u8 = undefined;
        std.mem.writeInt(u32, payload[0..4], width, .little);
        std.mem.writeInt(u32, payload[4..8], height, .little);
        std.mem.writeInt(u32, payload[8..12], pixel_width, .little);
        std.mem.writeInt(u32, payload[12..16], pixel_height, .little);
        const name = "window_resize";
        renderer.callback_depth += 1;
        defer {
            renderer.callback_depth -= 1;
            tryFinalize(renderer);
        }
        event_fn(name, name.len, &payload, payload.len);
    }
}

// ============================================================
// Finalization & Destruction
// ============================================================

pub fn tryFinalize(renderer: *Renderer) void {
    if (!renderer.pending_destroy) return;
    if (renderer.busy) return;
    if (renderer.callback_depth > 0) return;
    finalizeDestroy(renderer);
}

pub fn deinitRenderer(renderer: *Renderer) void {
    const had_window = renderer.window != null;
    @import("window.zig").teardownWindow(renderer);
    if (!had_window) {
        retained.deinit();
    }
    renderer.headers.deinit(renderer.allocator);
    renderer.payload.deinit(renderer.allocator);
    renderer.frame_arena.deinit();
    teardownLua(renderer);
    if (renderer.retained_store_ready) {
        if (utils.retainedStore(renderer)) |store| {
            store.deinit();
        }
        renderer.retained_store_ready = false;
    }
    if (utils.retainedStore(renderer)) |store| {
        renderer.allocator.destroy(store);
        renderer.retained_store_ptr = null;
    }
    if (renderer.retained_event_ring_ready) {
        if (utils.retainedEventRing(renderer)) |ring| {
            ring.deinit();
        }
        renderer.retained_event_ring_ready = false;
    }
    if (utils.retainedEventRing(renderer)) |ring| {
        renderer.allocator.destroy(ring);
        renderer.retained_event_ring_ptr = null;
    }
}

pub fn finalizeDestroy(renderer: *Renderer) void {
    if (renderer.destroy_started) return;
    renderer.destroy_started = true;
    deinitRenderer(renderer);
    _ = renderer.gpa_instance.deinit();
    std.heap.c_allocator.destroy(renderer);
}

// ============================================================
// Renderer Creation
// ============================================================

pub fn createRendererImpl(log_cb: ?*const types.LogFn, event_cb: ?*const types.EventFn) ?*Renderer {
    return createRendererWithLuaEntryAndAppImpl(log_cb, event_cb, null, null);
}

pub fn createRendererWithLuaEntryImpl(log_cb: ?*const types.LogFn, event_cb: ?*const types.EventFn, lua_entry_path: ?[]const u8) ?*Renderer {
    return createRendererWithLuaEntryAndAppImpl(log_cb, event_cb, lua_entry_path, null);
}

pub fn createRendererWithLuaEntryAndAppImpl(
    log_cb: ?*const types.LogFn,
    event_cb: ?*const types.EventFn,
    lua_entry_path: ?[]const u8,
    lua_app_module: ?[]const u8,
) ?*Renderer {
    const renderer = std.heap.c_allocator.create(Renderer) catch return null;

    renderer.* = .{
        .gpa_instance = std.heap.GeneralPurposeAllocator(.{}){},
        .allocator = undefined,
        .backend = null,
        .window = null,
        .webgpu = null,
        .log_cb = log_cb,
        .event_cb = event_cb,
        .headers = .{},
        .payload = .{},
        .frame_arena = undefined,
        .size = .{ 0, 0 },
        .pixel_size = .{ 0, 0 },
        .window_ready = false,
        .busy = false,
        .callback_depth = 0,
        .pending_destroy = false,
        .destroy_started = false,
        .frame_count = 0,
        .profiler = .{},
        .retained_store_ready = false,
        .retained_store_ptr = null,
        .retained_event_ring_ptr = null,
        .retained_event_ring_ready = false,
        .lua_entry_path = lua_entry_path,
        .lua_app_module = lua_app_module,
        .lua_state = null,
        .lua_ui = null,
        .lua_ready = false,
        .screenshot_key_enabled = false,
        .screenshot_index = 0,
    };

    renderer.allocator = renderer.gpa_instance.allocator();
    renderer.frame_arena = std.heap.ArenaAllocator.init(renderer.allocator);

    const retained_ring_instance = renderer.allocator.create(retained.EventRing) catch {
        renderer.frame_arena.deinit();
        _ = renderer.gpa_instance.deinit();
        std.heap.c_allocator.destroy(renderer);
        return null;
    };
    renderer.retained_event_ring_ptr = retained_ring_instance;
    retained_ring_instance.* = retained.EventRing.init(renderer.allocator) catch {
        renderer.allocator.destroy(retained_ring_instance);
        renderer.retained_event_ring_ptr = null;
        renderer.retained_event_ring_ready = false;
        renderer.frame_arena.deinit();
        _ = renderer.gpa_instance.deinit();
        std.heap.c_allocator.destroy(renderer);
        return null;
    };
    renderer.retained_event_ring_ready = true;

    retained.init();
    initLua(renderer);
    return renderer;
}

pub fn destroyRendererImpl(renderer: ?*Renderer) void {
    if (renderer) |ptr| {
        if (ptr.destroy_started) return;
        ptr.log_cb = null;
        ptr.event_cb = null;
        ptr.pending_destroy = true;
        tryFinalize(ptr);
    }
}
