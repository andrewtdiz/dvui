const std = @import("std");

const Allocator = std.mem.Allocator;

const CodegenError = Allocator.Error || error{
    InvalidArgs,
    InvalidSchema,
    MissingTag,
    MissingRoot,
    InvalidKey,
    DuplicateKey,
    KeyMismatch,
    UnknownField,
};

const Json5Error = Allocator.Error || error{
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

const Child = union(enum) {
    primitive: std.json.Value,
    node: *Node,
};

const Node = struct {
    tag: []const u8,
    key: ?[]const u8,
    class: ?[]const u8,
    props: ?std.json.Value,
    scale: ?std.json.Value,
    visual: ?std.json.Value,
    transform: ?std.json.Value,
    scroll: ?std.json.Value,
    anchor: ?std.json.Value,
    image: ?std.json.Value,
    src: ?std.json.Value,
    listen: ?std.json.Value,
    children: []Child,
};

const Link = struct {
    parent_key: []const u8,
    child_key: []const u8,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const gpa_allocator = gpa.allocator();

    var arena = std.heap.ArenaAllocator.init(gpa_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const args = try std.process.argsAlloc(gpa_allocator);
    defer std.process.argsFree(gpa_allocator, args);

    if (args.len != 3) {
        std.debug.print("usage: {s} <input_json_path> <output_luau_path>\n", .{args[0]});
        return error.InvalidArgs;
    }

    const input_path = args[1];
    const output_path = args[2];

    const input_bytes = try std.fs.cwd().readFileAlloc(gpa_allocator, input_path, 1024 * 1024 * 8);
    defer gpa_allocator.free(input_bytes);

    const normalized = try normalizeJson5(gpa_allocator, input_bytes);
    defer gpa_allocator.free(normalized);

    const parsed = try std.json.parseFromSlice(std.json.Value, gpa_allocator, normalized, .{ .allocate = .alloc_always });
    defer parsed.deinit();

    var key_set: std.StringHashMapUnmanaged(void) = .empty;
    defer key_set.deinit(allocator);

    var keys: std.ArrayList([]const u8) = .empty;
    defer keys.deinit(allocator);

    var links: std.ArrayList(Link) = .empty;
    defer links.deinit(allocator);

    const root = try parseRoot(parsed.value, allocator, &key_set, &keys, &links);

    if (keys.items.len > 1) {
        std.sort.pdq([]const u8, keys.items, {}, lessThanString);
    }
    if (links.items.len > 1) {
        std.sort.pdq(Link, links.items, {}, lessThanLink);
    }

    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(gpa_allocator);

    try emitModule(allocator, out.writer(gpa_allocator), root, keys.items, links.items);

    if (std.fs.path.dirname(output_path)) |dir| {
        try std.fs.cwd().makePath(dir);
    }

    var out_file = try std.fs.cwd().createFile(output_path, .{ .truncate = true });
    defer out_file.close();
    try out_file.writeAll(out.items);
}

fn lessThanString(_: void, a: []const u8, b: []const u8) bool {
    return std.mem.lessThan(u8, a, b);
}

fn lessThanLink(_: void, a: Link, b: Link) bool {
    if (std.mem.eql(u8, a.parent_key, b.parent_key)) {
        return std.mem.lessThan(u8, a.child_key, b.child_key);
    }
    return std.mem.lessThan(u8, a.parent_key, b.parent_key);
}

fn isLuauIdent(name: []const u8) bool {
    if (name.len == 0) return false;
    if (!isIdentStart(name[0])) return false;
    for (name[1..]) |c| {
        if (!isIdentContinue(c)) return false;
    }
    return !isKeyword(name);
}

fn isIdentStart(c: u8) bool {
    return (c >= 'A' and c <= 'Z') or (c >= 'a' and c <= 'z') or c == '_';
}

fn isIdentContinue(c: u8) bool {
    return isIdentStart(c) or (c >= '0' and c <= '9');
}

fn isKeyword(name: []const u8) bool {
    const keywords = [_][]const u8{
        "and",
        "break",
        "do",
        "else",
        "elseif",
        "end",
        "false",
        "for",
        "function",
        "if",
        "in",
        "local",
        "nil",
        "not",
        "or",
        "repeat",
        "return",
        "then",
        "true",
        "until",
        "while",
    };

    for (keywords) |kw| {
        if (std.mem.eql(u8, name, kw)) return true;
    }
    return false;
}

fn isReservedKey(name: []const u8) bool {
    const reserved = [_][]const u8{
        "__kind",
        "parent",
        "children",
        "class",
        "key",
        "props",
        "scale",
        "tag",
        "onBlur",
        "onClick",
        "onEnter",
        "onFocus",
        "onInput",
        "onMouseDown",
        "onMouseEnter",
        "onMouseLeave",
        "onMouseUp",
    };

    for (reserved) |r| {
        if (std.mem.eql(u8, name, r)) return true;
    }
    return false;
}

fn validateKey(name: []const u8) CodegenError!void {
    if (!isLuauIdent(name)) return error.InvalidKey;
    if (isReservedKey(name)) return error.InvalidKey;
}

fn parseRoot(
    value: std.json.Value,
    allocator: Allocator,
    key_set: *std.StringHashMapUnmanaged(void),
    keys: *std.ArrayList([]const u8),
    links: *std.ArrayList(Link),
) CodegenError!*Node {
    if (value != .object) return error.InvalidSchema;
    const obj = value.object;

    if (obj.get("tag") != null) {
        const node = try parseNodeSpec(value, allocator, key_set, keys, links, "root");
        if (node.key == null) return error.MissingRoot;
        return node;
    }

    if (obj.count() != 1) return error.InvalidSchema;
    var it = obj.iterator();
    const entry = it.next() orelse return error.InvalidSchema;
    const root_key = entry.key_ptr.*;
    try validateKey(root_key);
    return parseNodeSpec(entry.value_ptr.*, allocator, key_set, keys, links, root_key);
}

fn parseChild(
    value: std.json.Value,
    allocator: Allocator,
    key_set: *std.StringHashMapUnmanaged(void),
    keys: *std.ArrayList([]const u8),
    links: *std.ArrayList(Link),
    parent_key: ?[]const u8,
) CodegenError!?Child {
    switch (value) {
        .null => return null,
        .string, .integer, .float, .number_string, .bool => return Child{ .primitive = value },
        .object => |obj| {
            if (obj.get("tag") != null) {
                const node = try parseNodeSpec(value, allocator, key_set, keys, links, null);
                return Child{ .node = node };
            }

            if (obj.count() != 1) return error.InvalidSchema;
            var it = obj.iterator();
            const entry = it.next() orelse return error.InvalidSchema;
            const child_key = entry.key_ptr.*;
            try validateKey(child_key);

            const node = try parseNodeSpec(entry.value_ptr.*, allocator, key_set, keys, links, child_key);
            if (parent_key) |pk| {
                try links.append(allocator, .{ .parent_key = pk, .child_key = child_key });
            }
            return Child{ .node = node };
        },
        else => return error.InvalidSchema,
    }
}

fn parseNodeSpec(
    value: std.json.Value,
    allocator: Allocator,
    key_set: *std.StringHashMapUnmanaged(void),
    keys: *std.ArrayList([]const u8),
    links: *std.ArrayList(Link),
    forced_key: ?[]const u8,
) CodegenError!*Node {
    if (value != .object) return error.InvalidSchema;
    const obj = value.object;

    const tag_value = obj.get("tag") orelse return error.MissingTag;
    if (tag_value != .string) return error.InvalidSchema;

    var node_key: ?[]const u8 = forced_key;
    if (obj.get("key")) |key_value| {
        if (key_value != .string) return error.InvalidSchema;
        const k = key_value.string;
        if (forced_key) |fk| {
            if (!std.mem.eql(u8, k, fk)) return error.KeyMismatch;
        }
        node_key = k;
    }

    if (node_key) |k| {
        try validateKey(k);
        if (key_set.contains(k)) return error.DuplicateKey;
        try key_set.putNoClobber(allocator, k, {});
        try keys.append(allocator, k);
    }

    var class_value: ?[]const u8 = null;
    if (obj.get("class")) |v| {
        if (v == .string) {
            class_value = v.string;
        }
    }

    var props_value: ?std.json.Value = null;
    if (obj.get("props")) |v| {
        if (v == .object) {
            props_value = v;
        }
    }

    var scale_value: ?std.json.Value = null;
    if (obj.get("scale")) |v| {
        switch (v) {
            .integer, .float, .number_string => scale_value = v,
            else => {},
        }
    }

    var visual_value: ?std.json.Value = null;
    if (obj.get("visual")) |v| {
        if (v == .object) {
            visual_value = v;
        }
    }

    var transform_value: ?std.json.Value = null;
    if (obj.get("transform")) |v| {
        if (v == .object) {
            transform_value = v;
        }
    }

    var scroll_value: ?std.json.Value = null;
    if (obj.get("scroll")) |v| {
        if (v == .object) {
            scroll_value = v;
        }
    }

    var anchor_value: ?std.json.Value = null;
    if (obj.get("anchor")) |v| {
        if (v == .object) {
            anchor_value = v;
        }
    }

    var image_value: ?std.json.Value = null;
    if (obj.get("image")) |v| {
        if (v == .object) {
            image_value = v;
        }
    }

    var src_value: ?std.json.Value = null;
    if (obj.get("src")) |v| {
        if (v == .string) {
            src_value = v;
        }
    }

    var listen_value: ?std.json.Value = null;
    if (obj.get("listen")) |v| {
        if (v == .array) {
            listen_value = v;
        }
    }

    var children_list: std.ArrayList(Child) = .empty;
    defer children_list.deinit(allocator);

    if (obj.get("children")) |children_value| {
        if (children_value != .array) return error.InvalidSchema;
        const pk = node_key;
        for (children_value.array.items) |child_value| {
            if (try parseChild(child_value, allocator, key_set, keys, links, pk)) |child| {
                try children_list.append(allocator, child);
            }
        }
    }

    const node_ptr = try allocator.create(Node);
    node_ptr.* = .{
        .tag = tag_value.string,
        .key = node_key,
        .class = class_value,
        .props = props_value,
        .scale = scale_value,
        .visual = visual_value,
        .transform = transform_value,
        .scroll = scroll_value,
        .anchor = anchor_value,
        .image = image_value,
        .src = src_value,
        .listen = listen_value,
        .children = try children_list.toOwnedSlice(allocator),
    };
    return node_ptr;
}

fn emitModule(
    allocator: Allocator,
    writer: anytype,
    root: *Node,
    keys: []const []const u8,
    links: []const Link,
) CodegenError!void {
    try writer.writeAll("local Types = require(\"ui/types\")\n\n");
    try emitKeyType(writer, keys);
    try writer.writeAll("\n");
    var emitted_types: std.StringHashMapUnmanaged(void) = .empty;
    defer emitted_types.deinit(allocator);

    try emitNodeTypeDecls(allocator, writer, root, &emitted_types, links);

    const root_key = root.key orelse return error.MissingRoot;
    try writer.writeAll("export type Root = Node_");
    try writer.writeAll(root_key);
    try writer.writeAll("\n\n");
    try writer.writeAll("return {}\n");
}

fn emitNodeDecls(
    allocator: Allocator,
    writer: anytype,
    node: *Node,
    emitted: *std.StringHashMapUnmanaged(void),
    indent: usize,
) CodegenError!void {
    for (node.children) |child| {
        switch (child) {
            .node => |child_node| try emitNodeDecls(allocator, writer, child_node, emitted, indent),
            else => {},
        }
    }

    const key = node.key orelse return;
    if (emitted.contains(key)) return;
    try emitted.putNoClobber(allocator, key, {});

    try emitIndent(writer, indent);
    try writer.writeAll("local ");
    try emitNodeVar(writer, key);
    try writer.writeAll(" = ");
    try emitNodeLua(allocator, writer, node, indent + 1);
    try writer.writeAll("\n\n");
}

fn emitNodeTypeDecls(
    allocator: Allocator,
    writer: anytype,
    node: *Node,
    emitted: *std.StringHashMapUnmanaged(void),
    links: []const Link,
) CodegenError!void {
    for (node.children) |child| {
        switch (child) {
            .node => |child_node| try emitNodeTypeDecls(allocator, writer, child_node, emitted, links),
            else => {},
        }
    }

    const key = node.key orelse return;
    if (emitted.contains(key)) return;
    try emitted.putNoClobber(allocator, key, {});

    try writer.writeAll("export type Node_");
    try writer.writeAll(key);
    try writer.writeAll(" = Types.UINode & {\n");
    try writer.writeAll("  parent: Types.UINode?,\n");

    for (links) |link| {
        if (!std.mem.eql(u8, link.parent_key, key)) continue;
        try writer.writeAll("  ");
        try writer.writeAll(link.child_key);
        try writer.writeAll(": Node_");
        try writer.writeAll(link.child_key);
        try writer.writeAll(",\n");
    }

    try writer.writeAll("}\n\n");
}

fn emitKeyType(writer: anytype, keys: []const []const u8) CodegenError!void {
    if (keys.len == 0) {
        try writer.writeAll("export type Key = string\n");
        return;
    }

    try writer.writeAll("export type Key = ");
    var first = true;
    for (keys) |k| {
        if (!first) {
            try writer.writeAll(" | ");
        }
        first = false;
        try emitLuaString(writer, k);
    }
    try writer.writeAll("\n");
}

fn emitNodeVar(writer: anytype, key: []const u8) CodegenError!void {
    try writer.writeAll("node_");
    try writer.writeAll(key);
}

fn emitNodeLua(allocator: Allocator, writer: anytype, node: *Node, indent: usize) CodegenError!void {
    try writer.writeAll("{\n");

    try emitIndent(writer, indent);
    try writer.writeAll("tag = ");
    try emitLuaString(writer, node.tag);
    try writer.writeAll(",\n");

    if (node.key) |k| {
        try emitIndent(writer, indent);
        try writer.writeAll("key = ");
        try emitLuaString(writer, k);
        try writer.writeAll(",\n");
    }

    if (node.class) |c| {
        try emitIndent(writer, indent);
        try writer.writeAll("class = ");
        try emitLuaString(writer, c);
        try writer.writeAll(",\n");
    }

    if (node.props) |p| {
        try emitIndent(writer, indent);
        try writer.writeAll("props = ");
        try emitJsonToLua(allocator, writer, p, indent);
        try writer.writeAll(",\n");
    }

    if (node.scale) |s| {
        try emitIndent(writer, indent);
        try writer.writeAll("scale = ");
        try emitJsonToLua(allocator, writer, s, indent);
        try writer.writeAll(",\n");
    }

    if (node.visual) |v| {
        try emitIndent(writer, indent);
        try writer.writeAll("visual = ");
        try emitJsonToLua(allocator, writer, v, indent);
        try writer.writeAll(",\n");
    }

    if (node.transform) |v| {
        try emitIndent(writer, indent);
        try writer.writeAll("transform = ");
        try emitJsonToLua(allocator, writer, v, indent);
        try writer.writeAll(",\n");
    }

    if (node.scroll) |v| {
        try emitIndent(writer, indent);
        try writer.writeAll("scroll = ");
        try emitJsonToLua(allocator, writer, v, indent);
        try writer.writeAll(",\n");
    }

    if (node.anchor) |v| {
        try emitIndent(writer, indent);
        try writer.writeAll("anchor = ");
        try emitJsonToLua(allocator, writer, v, indent);
        try writer.writeAll(",\n");
    }

    if (node.image) |v| {
        try emitIndent(writer, indent);
        try writer.writeAll("image = ");
        try emitJsonToLua(allocator, writer, v, indent);
        try writer.writeAll(",\n");
    }

    if (node.src) |v| {
        try emitIndent(writer, indent);
        try writer.writeAll("src = ");
        try emitJsonToLua(allocator, writer, v, indent);
        try writer.writeAll(",\n");
    }

    if (node.listen) |v| {
        try emitIndent(writer, indent);
        try writer.writeAll("listen = ");
        try emitJsonToLua(allocator, writer, v, indent);
        try writer.writeAll(",\n");
    }

    if (node.children.len > 0) {
        try emitIndent(writer, indent);
        try writer.writeAll("children = ");
        try emitChildrenLua(allocator, writer, node.children, indent);
        try writer.writeAll(",\n");
    }

    try emitIndent(writer, indent - 1);
    try writer.writeAll("}");
}

fn emitChildrenLua(allocator: Allocator, writer: anytype, children: []const Child, indent: usize) CodegenError!void {
    try writer.writeAll("{\n");
    for (children) |child| {
        try emitIndent(writer, indent + 1);
        switch (child) {
            .primitive => |v| try emitJsonToLua(allocator, writer, v, indent + 2),
            .node => |n| {
                if (n.key) |k| {
                    try emitNodeVar(writer, k);
                } else {
                    try emitNodeLua(allocator, writer, n, indent + 2);
                }
            },
        }
        try writer.writeAll(",\n");
    }
    try emitIndent(writer, indent);
    try writer.writeAll("}");
}

fn emitJsonToLua(allocator: Allocator, writer: anytype, value: std.json.Value, indent: usize) CodegenError!void {
    switch (value) {
        .null => try writer.writeAll("nil"),
        .bool => |b| try writer.writeAll(if (b) "true" else "false"),
        .integer => |i| try writer.print("{d}", .{i}),
        .float => |f| try writer.print("{d}", .{f}),
        .number_string => |s| try writer.writeAll(s),
        .string => |s| try emitLuaString(writer, s),
        .array => |arr| try emitArrayLua(allocator, writer, arr.items, indent),
        .object => |obj| try emitObjectLua(allocator, writer, obj, indent),
    }
}

fn emitArrayLua(allocator: Allocator, writer: anytype, items: []const std.json.Value, indent: usize) CodegenError!void {
    if (items.len == 0) {
        try writer.writeAll("{}");
        return;
    }

    try writer.writeAll("{\n");
    for (items) |item| {
        try emitIndent(writer, indent + 1);
        try emitJsonToLua(allocator, writer, item, indent + 1);
        try writer.writeAll(",\n");
    }
    try emitIndent(writer, indent);
    try writer.writeAll("}");
}

fn emitObjectLua(allocator: Allocator, writer: anytype, obj: std.json.ObjectMap, indent: usize) CodegenError!void {
    if (obj.count() == 0) {
        try writer.writeAll("{}");
        return;
    }

    const key_list = try allocator.alloc([]const u8, obj.count());
    defer allocator.free(key_list);

    var i: usize = 0;
    var it = obj.iterator();
    while (it.next()) |entry| {
        key_list[i] = entry.key_ptr.*;
        i += 1;
    }
    if (key_list.len > 1) {
        std.sort.pdq([]const u8, key_list, {}, lessThanString);
    }

    try writer.writeAll("{\n");
    for (key_list) |k| {
        try emitIndent(writer, indent + 1);
        if (isLuauIdent(k)) {
            try writer.writeAll(k);
        } else {
            try writer.writeAll("[");
            try emitLuaString(writer, k);
            try writer.writeAll("]");
        }
        try writer.writeAll(" = ");
        const v = obj.get(k) orelse return error.InvalidSchema;
        try emitJsonToLua(allocator, writer, v, indent + 1);
        try writer.writeAll(",\n");
    }
    try emitIndent(writer, indent);
    try writer.writeAll("}");
}

fn emitIndent(writer: anytype, n: usize) CodegenError!void {
    for (0..n) |_| {
        try writer.writeAll("  ");
    }
}

fn emitLuaString(writer: anytype, s: []const u8) CodegenError!void {
    try writer.writeByte('"');
    for (s) |c| {
        switch (c) {
            '\\' => try writer.writeAll("\\\\"),
            '"' => try writer.writeAll("\\\""),
            '\n' => try writer.writeAll("\\n"),
            '\r' => try writer.writeAll("\\r"),
            '\t' => try writer.writeAll("\\t"),
            else => {
                if (c < 0x20) {
                    try writer.print("\\{d:0>3}", .{c});
                } else {
                    try writer.writeByte(c);
                }
            },
        }
    }
    try writer.writeByte('"');
}
