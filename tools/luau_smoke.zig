const std = @import("std");
const luaz = @import("luaz");
const solidluau_embedded = @import("solidluau_embedded");

const RequireCtx = struct {
    allocator: std.mem.Allocator,
};

var require_cache_key: u8 = 0;

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
        if (negative) {
            try out.appendSlice(allocator, "-0");
        } else {
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
    defer if (owned_source) |bytes| ctx.allocator.free(bytes);

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

    if (module_is_json) {
        const normalized = normalizeJson5(ctx.allocator, source_bytes) catch |err| {
            lua.state.setTop(base_top);
            lua.state.pushLString("require(");
            lua.state.pushLString(module_id);
            lua.state.pushLString(") json5 normalize failed: ");
            lua.state.pushLString(@errorName(err));
            lua.state.concat(4);
            lua.state.raiseError();
        };
        defer ctx.allocator.free(normalized);

        const parsed = std.json.parseFromSlice(std.json.Value, ctx.allocator, normalized, .{ .allocate = .alloc_always }) catch |err| {
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
        lua.state.rawSet(-4);
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
}
