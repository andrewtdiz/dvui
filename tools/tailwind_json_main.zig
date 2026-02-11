const std = @import("std");

const Allocator = std.mem.Allocator;

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

const LayoutSize = union(enum) {
    full,
    pixels: f64,
    tw: f64,
};

const InsetValue = union(enum) {
    pixels: f64,
    pct: f64,
};

const Inset4 = struct {
    left: ?InsetValue = null,
    top: ?InsetValue = null,
    right: ?InsetValue = null,
    bottom: ?InsetValue = null,
};

const Layout = struct {
    abs: bool = false,
    anchor: ?[]const u8 = null,
    inset: Inset4 = .{},
    w: ?LayoutSize = null,
    h: ?LayoutSize = null,
};

const Flex = struct {
    present: bool = false,
    dir: ?[]const u8 = null,
    items: ?[]const u8 = null,
    justify: ?[]const u8 = null,
    gap: ?f64 = null,
};

const Margin = struct {
    all: ?f64 = null,
    x: ?f64 = null,
    y: ?f64 = null,
    t: ?f64 = null,
    r: ?f64 = null,
    b: ?f64 = null,
    l: ?f64 = null,
};

const Pad = struct {
    x: ?f64 = null,
    y: ?f64 = null,
};

const Border = struct {
    w: ?f64 = null,
    color: ?[]const u8 = null,
};

const Font = struct {
    family: ?[]const u8 = null,
    weight: ?[]const u8 = null,
    slant: ?[]const u8 = null,
    render: ?[]const u8 = null,
};

const Outline = struct {
    w: ?f64 = null,
    color: ?[]const u8 = null,
};

const Text = struct {
    color: ?[]const u8 = null,
    size: ?[]const u8 = null,
    text_align: ?[]const u8 = null,
    wrap: ?[]const u8 = null,
    font: Font = .{},
    outline: Outline = .{},
};

const ZIndex = union(enum) {
    layer: []const u8,
    value: i64,
};

const ParsedStyle = struct {
    layout: Layout = .{},
    has_layout: bool = false,
    flex: Flex = .{},
    has_flex: bool = false,
    margin: Margin = .{},
    has_margin: bool = false,
    pad: Pad = .{},
    has_pad: bool = false,
    bg: ?[]const u8 = null,
    border: Border = .{},
    has_border: bool = false,
    rounded: ?[]const u8 = null,
    opacity: ?i64 = null,
    z: ?ZIndex = null,
    text: Text = .{},
    has_text: bool = false,
    hidden: bool = false,
    clip: bool = false,
    class_extra: std.ArrayList([]const u8) = .empty,
    saw_border_token: bool = false,

    fn deinit(self: *ParsedStyle, allocator: Allocator) void {
        self.class_extra.deinit(allocator);
    }
};

fn isColorToken(s: []const u8) bool {
    if (s.len == 0) return false;
    if (std.mem.eql(u8, s, "black") or std.mem.eql(u8, s, "white")) return true;
    if (std.mem.indexOfScalar(u8, s, '-') != null) return true;

    const roles = [_][]const u8{
        "content",
        "window",
        "control",
        "highlight",
        "err",
        "app1",
        "app2",
        "app3",
    };
    for (roles) |role| {
        if (std.mem.eql(u8, s, role)) return true;
    }
    return false;
}

fn isTextSize(s: []const u8) bool {
    return std.mem.eql(u8, s, "xs") or
        std.mem.eql(u8, s, "sm") or
        std.mem.eql(u8, s, "base") or
        std.mem.eql(u8, s, "lg") or
        std.mem.eql(u8, s, "xl") or
        std.mem.eql(u8, s, "2xl") or
        std.mem.eql(u8, s, "3xl");
}

fn isRoundedValue(s: []const u8) bool {
    return std.mem.eql(u8, s, "none") or
        std.mem.eql(u8, s, "sm") or
        std.mem.eql(u8, s, "md") or
        std.mem.eql(u8, s, "lg") or
        std.mem.eql(u8, s, "xl") or
        std.mem.eql(u8, s, "2xl") or
        std.mem.eql(u8, s, "3xl") or
        std.mem.eql(u8, s, "full");
}

fn isAnchorValue(s: []const u8) bool {
    return std.mem.eql(u8, s, "top-left") or
        std.mem.eql(u8, s, "top") or
        std.mem.eql(u8, s, "top-right") or
        std.mem.eql(u8, s, "left") or
        std.mem.eql(u8, s, "center") or
        std.mem.eql(u8, s, "right") or
        std.mem.eql(u8, s, "bottom-left") or
        std.mem.eql(u8, s, "bottom") or
        std.mem.eql(u8, s, "bottom-right");
}

fn isZLayerValue(s: []const u8) bool {
    return std.mem.eql(u8, s, "base") or
        std.mem.eql(u8, s, "dropdown") or
        std.mem.eql(u8, s, "overlay") or
        std.mem.eql(u8, s, "modal") or
        std.mem.eql(u8, s, "popover") or
        std.mem.eql(u8, s, "tooltip");
}

fn addExtraToken(style: *ParsedStyle, allocator: Allocator, tok: []const u8) void {
    if (tok.len == 0) return;
    if (std.mem.startsWith(u8, tok, "ui-path-")) return;
    if (std.mem.startsWith(u8, tok, "__key=")) return;
    style.class_extra.append(allocator, tok) catch {};
}

fn parseBracketInner(inner: []const u8) ?struct { value: f64, is_pct: bool } {
    if (inner.len == 0) return null;
    if (std.mem.endsWith(u8, inner, "%")) {
        const num_slice = inner[0 .. inner.len - 1];
        if (num_slice.len == 0) return null;
        const value = std.fmt.parseFloat(f64, num_slice) catch return null;
        if (!std.math.isFinite(value)) return null;
        return .{ .value = value / 100.0, .is_pct = true };
    }

    var num_slice = inner;
    if (std.mem.endsWith(u8, num_slice, "px")) {
        if (num_slice.len <= 2) return null;
        num_slice = num_slice[0 .. num_slice.len - 2];
    }
    const value = std.fmt.parseFloat(f64, num_slice) catch return null;
    if (!std.math.isFinite(value)) return null;
    return .{ .value = value, .is_pct = false };
}

fn parseScaleNumber(inner: []const u8) ?f64 {
    if (inner.len == 0) return null;
    if (std.mem.eql(u8, inner, "px")) return 1;
    const value = std.fmt.parseFloat(f64, inner) catch return null;
    if (!std.math.isFinite(value) or value < 0) return null;
    return value;
}

fn parseClass(allocator: Allocator, class_name: []const u8) ParsedStyle {
    var out: ParsedStyle = .{};
    out.class_extra = .empty;

    var it = std.mem.tokenizeAny(u8, class_name, " \t\r\n");
    while (it.next()) |tok| {
        if (tok.len == 0) continue;

        if (std.mem.startsWith(u8, tok, "mt-")) {
            const suffix = tok["mt-".len..];
            if (parseScaleNumber(suffix)) |value| {
                out.margin.t = value;
                out.has_margin = true;
            } else {
                addExtraToken(&out, allocator, tok);
            }
            continue;
        }
        if (std.mem.startsWith(u8, tok, "mr-")) {
            const suffix = tok["mr-".len..];
            if (parseScaleNumber(suffix)) |value| {
                out.margin.r = value;
                out.has_margin = true;
            } else {
                addExtraToken(&out, allocator, tok);
            }
            continue;
        }
        if (std.mem.startsWith(u8, tok, "mb-")) {
            const suffix = tok["mb-".len..];
            if (parseScaleNumber(suffix)) |value| {
                out.margin.b = value;
                out.has_margin = true;
            } else {
                addExtraToken(&out, allocator, tok);
            }
            continue;
        }
        if (std.mem.startsWith(u8, tok, "ml-")) {
            const suffix = tok["ml-".len..];
            if (parseScaleNumber(suffix)) |value| {
                out.margin.l = value;
                out.has_margin = true;
            } else {
                addExtraToken(&out, allocator, tok);
            }
            continue;
        }
        if (std.mem.startsWith(u8, tok, "mx-")) {
            const suffix = tok["mx-".len..];
            if (parseScaleNumber(suffix)) |value| {
                out.margin.x = value;
                out.margin.l = null;
                out.margin.r = null;
                out.has_margin = true;
            } else {
                addExtraToken(&out, allocator, tok);
            }
            continue;
        }
        if (std.mem.startsWith(u8, tok, "my-")) {
            const suffix = tok["my-".len..];
            if (parseScaleNumber(suffix)) |value| {
                out.margin.y = value;
                out.margin.t = null;
                out.margin.b = null;
                out.has_margin = true;
            } else {
                addExtraToken(&out, allocator, tok);
            }
            continue;
        }
        if (std.mem.startsWith(u8, tok, "m-")) {
            const suffix = tok["m-".len..];
            if (parseScaleNumber(suffix)) |value| {
                out.margin.all = value;
                out.margin.x = null;
                out.margin.y = null;
                out.margin.t = null;
                out.margin.r = null;
                out.margin.b = null;
                out.margin.l = null;
                out.has_margin = true;
            } else {
                addExtraToken(&out, allocator, tok);
            }
            continue;
        }

        if (std.mem.eql(u8, tok, "absolute")) {
            out.layout.abs = true;
            out.has_layout = true;
            continue;
        }

        if (std.mem.startsWith(u8, tok, "anchor-")) {
            const name = tok["anchor-".len..];
            if (isAnchorValue(name)) {
                out.layout.anchor = name;
                out.has_layout = true;
            } else {
                addExtraToken(&out, allocator, tok);
            }
            continue;
        }

        if (std.mem.startsWith(u8, tok, "left-[") and std.mem.endsWith(u8, tok, "]")) {
            const inner = tok["left-[".len .. tok.len - 1];
            if (parseBracketInner(inner)) |v| {
                out.layout.inset.left = if (v.is_pct) .{ .pct = v.value } else .{ .pixels = v.value };
                out.has_layout = true;
            } else {
                addExtraToken(&out, allocator, tok);
            }
            continue;
        }
        if (std.mem.startsWith(u8, tok, "top-[") and std.mem.endsWith(u8, tok, "]")) {
            const inner = tok["top-[".len .. tok.len - 1];
            if (parseBracketInner(inner)) |v| {
                out.layout.inset.top = if (v.is_pct) .{ .pct = v.value } else .{ .pixels = v.value };
                out.has_layout = true;
            } else {
                addExtraToken(&out, allocator, tok);
            }
            continue;
        }
        if (std.mem.startsWith(u8, tok, "right-[") and std.mem.endsWith(u8, tok, "]")) {
            const inner = tok["right-[".len .. tok.len - 1];
            if (parseBracketInner(inner)) |v| {
                out.layout.inset.right = if (v.is_pct) .{ .pct = v.value } else .{ .pixels = v.value };
                out.has_layout = true;
            } else {
                addExtraToken(&out, allocator, tok);
            }
            continue;
        }
        if (std.mem.startsWith(u8, tok, "bottom-[") and std.mem.endsWith(u8, tok, "]")) {
            const inner = tok["bottom-[".len .. tok.len - 1];
            if (parseBracketInner(inner)) |v| {
                out.layout.inset.bottom = if (v.is_pct) .{ .pct = v.value } else .{ .pixels = v.value };
                out.has_layout = true;
            } else {
                addExtraToken(&out, allocator, tok);
            }
            continue;
        }

        if (std.mem.eql(u8, tok, "w-full")) {
            out.layout.w = .full;
            out.has_layout = true;
            continue;
        }
        if (std.mem.eql(u8, tok, "w-screen")) {
            out.layout.w = .full;
            out.has_layout = true;
            continue;
        }
        if (std.mem.eql(u8, tok, "w-px")) {
            out.layout.w = .{ .pixels = 1 };
            out.has_layout = true;
            continue;
        }
        if (std.mem.eql(u8, tok, "h-full")) {
            out.layout.h = .full;
            out.has_layout = true;
            continue;
        }
        if (std.mem.eql(u8, tok, "h-screen")) {
            out.layout.h = .full;
            out.has_layout = true;
            continue;
        }
        if (std.mem.eql(u8, tok, "h-px")) {
            out.layout.h = .{ .pixels = 1 };
            out.has_layout = true;
            continue;
        }
        if (std.mem.startsWith(u8, tok, "w-[") and std.mem.endsWith(u8, tok, "]")) {
            const inner = tok["w-[".len .. tok.len - 1];
            if (parseBracketInner(inner)) |v| {
                if (v.is_pct) {
                    addExtraToken(&out, allocator, tok);
                } else {
                    out.layout.w = .{ .pixels = v.value };
                    out.has_layout = true;
                }
            } else {
                addExtraToken(&out, allocator, tok);
            }
            continue;
        }
        if (std.mem.startsWith(u8, tok, "h-[") and std.mem.endsWith(u8, tok, "]")) {
            const inner = tok["h-[".len .. tok.len - 1];
            if (parseBracketInner(inner)) |v| {
                if (v.is_pct) {
                    addExtraToken(&out, allocator, tok);
                } else {
                    out.layout.h = .{ .pixels = v.value };
                    out.has_layout = true;
                }
            } else {
                addExtraToken(&out, allocator, tok);
            }
            continue;
        }
        if (std.mem.startsWith(u8, tok, "w-")) {
            const suffix = tok["w-".len..];
            if (parseScaleNumber(suffix)) |value| {
                out.layout.w = .{ .tw = value };
                out.has_layout = true;
            } else {
                addExtraToken(&out, allocator, tok);
            }
            continue;
        }
        if (std.mem.startsWith(u8, tok, "h-")) {
            const suffix = tok["h-".len..];
            if (parseScaleNumber(suffix)) |value| {
                out.layout.h = .{ .tw = value };
                out.has_layout = true;
            } else {
                addExtraToken(&out, allocator, tok);
            }
            continue;
        }

        if (std.mem.eql(u8, tok, "flex")) {
            out.flex.present = true;
            out.has_flex = true;
            continue;
        }
        if (std.mem.eql(u8, tok, "flex-row")) {
            out.flex.present = true;
            out.flex.dir = "row";
            out.has_flex = true;
            continue;
        }
        if (std.mem.eql(u8, tok, "flex-col")) {
            out.flex.present = true;
            out.flex.dir = "col";
            out.has_flex = true;
            continue;
        }
        if (std.mem.eql(u8, tok, "items-start")) {
            out.flex.present = true;
            out.flex.items = "start";
            out.has_flex = true;
            continue;
        }
        if (std.mem.eql(u8, tok, "items-center")) {
            out.flex.present = true;
            out.flex.items = "center";
            out.has_flex = true;
            continue;
        }
        if (std.mem.eql(u8, tok, "items-end")) {
            out.flex.present = true;
            out.flex.items = "end";
            out.has_flex = true;
            continue;
        }
        if (std.mem.eql(u8, tok, "justify-start")) {
            out.flex.present = true;
            out.flex.justify = "start";
            out.has_flex = true;
            continue;
        }
        if (std.mem.eql(u8, tok, "justify-center")) {
            out.flex.present = true;
            out.flex.justify = "center";
            out.has_flex = true;
            continue;
        }
        if (std.mem.eql(u8, tok, "justify-end")) {
            out.flex.present = true;
            out.flex.justify = "end";
            out.has_flex = true;
            continue;
        }
        if (std.mem.eql(u8, tok, "justify-between")) {
            out.flex.present = true;
            out.flex.justify = "between";
            out.has_flex = true;
            continue;
        }
        if (std.mem.eql(u8, tok, "justify-around")) {
            out.flex.present = true;
            out.flex.justify = "around";
            out.has_flex = true;
            continue;
        }
        if (std.mem.startsWith(u8, tok, "gap-")) {
            const suffix = tok["gap-".len..];
            if (std.mem.startsWith(u8, suffix, "x-") or std.mem.startsWith(u8, suffix, "y-")) {
                addExtraToken(&out, allocator, tok);
                continue;
            }
            if (parseScaleNumber(suffix)) |value| {
                out.flex.present = true;
                out.flex.gap = value;
                out.has_flex = true;
            } else {
                addExtraToken(&out, allocator, tok);
            }
            continue;
        }

        if (std.mem.startsWith(u8, tok, "p-")) {
            const suffix = tok["p-".len..];
            if (parseScaleNumber(suffix)) |value| {
                out.pad.x = value;
                out.pad.y = value;
                out.has_pad = true;
            } else {
                addExtraToken(&out, allocator, tok);
            }
            continue;
        }
        if (std.mem.startsWith(u8, tok, "px-")) {
            const suffix = tok["px-".len..];
            if (parseScaleNumber(suffix)) |value| {
                out.pad.x = value;
                out.has_pad = true;
            } else {
                addExtraToken(&out, allocator, tok);
            }
            continue;
        }
        if (std.mem.startsWith(u8, tok, "py-")) {
            const suffix = tok["py-".len..];
            if (parseScaleNumber(suffix)) |value| {
                out.pad.y = value;
                out.has_pad = true;
            } else {
                addExtraToken(&out, allocator, tok);
            }
            continue;
        }

        if (std.mem.startsWith(u8, tok, "bg-")) {
            const suffix = tok["bg-".len..];
            if (isColorToken(suffix)) {
                out.bg = suffix;
            } else {
                addExtraToken(&out, allocator, tok);
            }
            continue;
        }

        if (std.mem.eql(u8, tok, "border")) {
            out.saw_border_token = true;
            continue;
        }
        if (std.mem.startsWith(u8, tok, "border-")) {
            const suffix = tok["border-".len..];
            if (suffix.len >= 2 and suffix[1] == '-' and (suffix[0] == 'x' or suffix[0] == 'y' or suffix[0] == 't' or suffix[0] == 'r' or suffix[0] == 'b' or suffix[0] == 'l')) {
                addExtraToken(&out, allocator, tok);
                continue;
            }
            if (std.mem.eql(u8, suffix, "px")) {
                out.border.w = 1;
                out.has_border = true;
                continue;
            }
            if (std.fmt.parseFloat(f64, suffix)) |value| {
                out.border.w = value;
                out.has_border = true;
                continue;
            } else |_| {}
            if (isColorToken(suffix)) {
                out.border.color = suffix;
                out.has_border = true;
                continue;
            }
            addExtraToken(&out, allocator, tok);
            continue;
        }

        if (std.mem.eql(u8, tok, "rounded")) {
            out.rounded = "base";
            continue;
        }
        if (std.mem.startsWith(u8, tok, "rounded-")) {
            const suffix = tok["rounded-".len..];
            if (isRoundedValue(suffix)) {
                out.rounded = suffix;
            } else {
                addExtraToken(&out, allocator, tok);
            }
            continue;
        }

        if (std.mem.startsWith(u8, tok, "opacity-")) {
            const suffix = tok["opacity-".len..];
            const value = std.fmt.parseInt(i64, suffix, 10) catch {
                addExtraToken(&out, allocator, tok);
                continue;
            };
            if (value >= 0 and value <= 100) {
                out.opacity = value;
            } else {
                addExtraToken(&out, allocator, tok);
            }
            continue;
        }

        if (std.mem.eql(u8, tok, "hidden")) {
            out.hidden = true;
            continue;
        }
        if (std.mem.eql(u8, tok, "overflow-hidden")) {
            out.clip = true;
            continue;
        }

        if (std.mem.eql(u8, tok, "text-left")) {
            out.text.text_align = "left";
            out.has_text = true;
            continue;
        }
        if (std.mem.eql(u8, tok, "text-center")) {
            out.text.text_align = "center";
            out.has_text = true;
            continue;
        }
        if (std.mem.eql(u8, tok, "text-right")) {
            out.text.text_align = "right";
            out.has_text = true;
            continue;
        }
        if (std.mem.eql(u8, tok, "text-nowrap")) {
            out.text.wrap = "nowrap";
            out.has_text = true;
            continue;
        }
        if (std.mem.eql(u8, tok, "break-words")) {
            out.text.wrap = "break-words";
            out.has_text = true;
            continue;
        }

        if (std.mem.eql(u8, tok, "italic")) {
            out.text.font.slant = "italic";
            out.has_text = true;
            continue;
        }
        if (std.mem.eql(u8, tok, "not-italic")) {
            out.text.font.slant = "normal";
            out.has_text = true;
            continue;
        }

        if (std.mem.startsWith(u8, tok, "font-render-")) {
            const suffix = tok["font-render-".len..];
            if (std.mem.eql(u8, suffix, "auto") or std.mem.eql(u8, suffix, "msdf") or std.mem.eql(u8, suffix, "raster")) {
                out.text.font.render = suffix;
                out.has_text = true;
            } else {
                addExtraToken(&out, allocator, tok);
            }
            continue;
        }

        if (std.mem.startsWith(u8, tok, "font-")) {
            const suffix = tok["font-".len..];
            if (std.mem.eql(u8, suffix, "ui") or std.mem.eql(u8, suffix, "mono") or std.mem.eql(u8, suffix, "game") or std.mem.eql(u8, suffix, "dyslexic")) {
                out.text.font.family = suffix;
                out.has_text = true;
                continue;
            }
            if (std.mem.eql(u8, suffix, "light") or std.mem.eql(u8, suffix, "normal") or std.mem.eql(u8, suffix, "medium") or std.mem.eql(u8, suffix, "semibold") or std.mem.eql(u8, suffix, "bold")) {
                out.text.font.weight = suffix;
                out.has_text = true;
                continue;
            }
            addExtraToken(&out, allocator, tok);
            continue;
        }

        if (std.mem.startsWith(u8, tok, "text-outline-")) {
            const rest = tok["text-outline-".len..];
            if (rest.len >= 2 and rest[0] == '[' and rest[rest.len - 1] == ']') {
                const inner = rest[1 .. rest.len - 1];
                if (parseBracketInner(inner)) |v| {
                    if (!v.is_pct) {
                        out.text.outline.w = v.value;
                        out.has_text = true;
                    } else {
                        addExtraToken(&out, allocator, tok);
                    }
                } else {
                    addExtraToken(&out, allocator, tok);
                }
            } else if (std.fmt.parseFloat(f64, rest)) |value| {
                out.text.outline.w = value;
                out.has_text = true;
            } else |_| {
                if (isColorToken(rest)) {
                    out.text.outline.color = rest;
                    out.has_text = true;
                } else {
                    addExtraToken(&out, allocator, tok);
                }
            }
            continue;
        }

        if (std.mem.startsWith(u8, tok, "text-")) {
            const suffix = tok["text-".len..];
            if (isTextSize(suffix)) {
                out.text.size = suffix;
                out.has_text = true;
                continue;
            }
            if (isColorToken(suffix)) {
                out.text.color = suffix;
                out.has_text = true;
                continue;
            }
            addExtraToken(&out, allocator, tok);
            continue;
        }

        if (std.mem.eql(u8, tok, "z-auto")) {
            addExtraToken(&out, allocator, tok);
            continue;
        }
        if (std.mem.startsWith(u8, tok, "-z-")) {
            const suffix = tok["-z-".len..];
            const value = std.fmt.parseInt(i64, suffix, 10) catch {
                addExtraToken(&out, allocator, tok);
                continue;
            };
            out.z = .{ .value = -value };
            continue;
        }
        if (std.mem.startsWith(u8, tok, "z-")) {
            const suffix = tok["z-".len..];
            if (isZLayerValue(suffix)) {
                out.z = .{ .layer = suffix };
                continue;
            }
            const value = std.fmt.parseInt(i64, suffix, 10) catch {
                addExtraToken(&out, allocator, tok);
                continue;
            };
            out.z = .{ .value = value };
            continue;
        }

        addExtraToken(&out, allocator, tok);
    }

    if (out.saw_border_token) {
        if (out.border.w == null and out.border.color == null) {
            addExtraToken(&out, allocator, "border");
        }
    }

    if (out.border.w != null or out.border.color != null) {
        out.has_border = true;
    }

    return out;
}

fn hasTailwindJsonKeys(obj: std.json.ObjectMap) bool {
    const keys = [_][]const u8{
        "layout",
        "flex",
        "margin",
        "pad",
        "bg",
        "border",
        "rounded",
        "opacity",
        "z",
        "text",
        "hidden",
        "clip",
        "classExtra",
    };
    for (keys) |k| {
        if (obj.get(k) != null) return true;
    }
    return false;
}

fn migrateValue(allocator: Allocator, value: std.json.Value) Allocator.Error!std.json.Value {
    return switch (value) {
        .null,
        .bool,
        .integer,
        .float,
        .number_string,
        .string,
        => value,
        .array => |arr| blk: {
            var out_arr = std.json.Array.init(allocator);
            for (arr.items) |item| {
                try out_arr.append(try migrateValue(allocator, item));
            }
            break :blk .{ .array = out_arr };
        },
        .object => |obj| blk: {
            if (obj.get("tag")) |tag_val| {
                if (tag_val == .string) {
                    break :blk try migrateNodeObject(allocator, obj);
                }
            }
            break :blk try migrateGenericObject(allocator, obj);
        },
    };
}

fn migrateGenericObject(allocator: Allocator, obj: std.json.ObjectMap) Allocator.Error!std.json.Value {
    var keys: std.ArrayList([]const u8) = .empty;
    defer keys.deinit(allocator);

    var it = obj.iterator();
    while (it.next()) |entry| {
        try keys.append(allocator, entry.key_ptr.*);
    }

    if (keys.items.len > 1) {
        std.sort.pdq([]const u8, keys.items, {}, lessThanString);
    }

    var out_obj = std.json.ObjectMap.init(allocator);
    for (keys.items) |k| {
        const v = obj.get(k).?;
        try out_obj.put(k, try migrateValue(allocator, v));
    }
    return .{ .object = out_obj };
}

fn lessThanString(_: void, a: []const u8, b: []const u8) bool {
    return std.mem.lessThan(u8, a, b);
}

fn migrateNodeObject(allocator: Allocator, obj: std.json.ObjectMap) Allocator.Error!std.json.Value {
    var out_obj = std.json.ObjectMap.init(allocator);

    const tag_val = obj.get("tag").?;
    try out_obj.put("tag", tag_val);

    if (obj.get("key")) |key_val| {
        if (key_val == .string) {
            try out_obj.put("key", key_val);
        }
    }

    const already_structured = hasTailwindJsonKeys(obj);

    var parsed: ?ParsedStyle = null;
    if (!already_structured) {
        if (obj.get("class")) |class_val| {
            if (class_val == .string and class_val.string.len > 0) {
                parsed = parseClass(allocator, class_val.string);
            }
        }
    }

    defer if (parsed) |*p| p.deinit(allocator);

    if (already_structured) {
        const style_keys = [_][]const u8{
            "layout",
            "flex",
            "margin",
            "pad",
            "bg",
            "border",
            "rounded",
            "opacity",
            "z",
            "text",
            "hidden",
            "clip",
            "classExtra",
        };
        for (style_keys) |k| {
            if (obj.get(k)) |v| {
                try out_obj.put(k, try migrateValue(allocator, v));
            }
        }
    } else if (parsed) |p| {
        if (p.has_layout) {
            var layout_obj = std.json.ObjectMap.init(allocator);
            if (p.layout.abs) try layout_obj.put("abs", .{ .bool = true });
            if (p.layout.anchor) |a| try layout_obj.put("anchor", .{ .string = a });

            if (p.layout.inset.left != null or p.layout.inset.top != null or p.layout.inset.right != null or p.layout.inset.bottom != null) {
                var inset_obj = std.json.ObjectMap.init(allocator);
                if (p.layout.inset.left) |v| try inset_obj.put("left", try insetValueToJson(allocator, v));
                if (p.layout.inset.top) |v| try inset_obj.put("top", try insetValueToJson(allocator, v));
                if (p.layout.inset.right) |v| try inset_obj.put("right", try insetValueToJson(allocator, v));
                if (p.layout.inset.bottom) |v| try inset_obj.put("bottom", try insetValueToJson(allocator, v));
                try layout_obj.put("inset", .{ .object = inset_obj });
            }

            if (p.layout.w != null or p.layout.h != null) {
                var size_obj = std.json.ObjectMap.init(allocator);
                if (p.layout.w) |v| try size_obj.put("w", try sizeValueToJson(allocator, v));
                if (p.layout.h) |v| try size_obj.put("h", try sizeValueToJson(allocator, v));
                try layout_obj.put("size", .{ .object = size_obj });
            }

            try out_obj.put("layout", .{ .object = layout_obj });
        }

        if (p.has_flex and (p.flex.present or p.flex.dir != null or p.flex.items != null or p.flex.justify != null or p.flex.gap != null)) {
            var flex_obj = std.json.ObjectMap.init(allocator);
            if (p.flex.dir) |v| try flex_obj.put("dir", .{ .string = v });
            if (p.flex.items) |v| try flex_obj.put("items", .{ .string = v });
            if (p.flex.justify) |v| try flex_obj.put("justify", .{ .string = v });
            if (p.flex.gap) |v| try flex_obj.put("gap", .{ .float = v });
            try out_obj.put("flex", .{ .object = flex_obj });
        }

        if (p.has_margin) {
            var margin_obj = std.json.ObjectMap.init(allocator);
            if (p.margin.all) |v| try margin_obj.put("all", .{ .float = v });
            if (p.margin.x) |v| try margin_obj.put("x", .{ .float = v });
            if (p.margin.y) |v| try margin_obj.put("y", .{ .float = v });
            if (p.margin.t) |v| try margin_obj.put("t", .{ .float = v });
            if (p.margin.r) |v| try margin_obj.put("r", .{ .float = v });
            if (p.margin.b) |v| try margin_obj.put("b", .{ .float = v });
            if (p.margin.l) |v| try margin_obj.put("l", .{ .float = v });
            if (margin_obj.count() > 0) {
                try out_obj.put("margin", .{ .object = margin_obj });
            }
        }

        if (p.has_pad) {
            var pad_obj = std.json.ObjectMap.init(allocator);
            if (p.pad.x) |v| try pad_obj.put("x", .{ .float = v });
            if (p.pad.y) |v| try pad_obj.put("y", .{ .float = v });
            try out_obj.put("pad", .{ .object = pad_obj });
        }

        if (p.bg) |bg| {
            try out_obj.put("bg", .{ .string = bg });
        }

        if (p.has_border) {
            var border_obj = std.json.ObjectMap.init(allocator);
            if (p.border.color) |c| try border_obj.put("color", .{ .string = c });
            if (p.border.w) |w| try border_obj.put("w", .{ .float = w });
            if (border_obj.count() > 0) {
                try out_obj.put("border", .{ .object = border_obj });
            }
        }

        if (p.rounded) |r| {
            try out_obj.put("rounded", .{ .string = r });
        }

        if (p.opacity) |v| {
            try out_obj.put("opacity", .{ .integer = v });
        }

        if (p.z) |zv| {
            switch (zv) {
                .layer => |layer| try out_obj.put("z", .{ .string = layer }),
                .value => |n| try out_obj.put("z", .{ .integer = n }),
            }
        }

        if (p.has_text) {
            var text_obj = std.json.ObjectMap.init(allocator);
            if (p.text.color) |v| try text_obj.put("color", .{ .string = v });
            if (p.text.size) |v| try text_obj.put("size", .{ .string = v });
            if (p.text.text_align) |v| try text_obj.put("align", .{ .string = v });
            if (p.text.wrap) |v| try text_obj.put("wrap", .{ .string = v });

            if (p.text.font.family != null or p.text.font.weight != null or p.text.font.slant != null or p.text.font.render != null) {
                var font_obj = std.json.ObjectMap.init(allocator);
                if (p.text.font.family) |v| try font_obj.put("family", .{ .string = v });
                if (p.text.font.weight) |v| try font_obj.put("weight", .{ .string = v });
                if (p.text.font.slant) |v| try font_obj.put("slant", .{ .string = v });
                if (p.text.font.render) |v| try font_obj.put("render", .{ .string = v });
                if (font_obj.count() > 0) {
                    try text_obj.put("font", .{ .object = font_obj });
                }
            }

            if (p.text.outline.w != null or p.text.outline.color != null) {
                var outline_obj = std.json.ObjectMap.init(allocator);
                if (p.text.outline.w) |v| try outline_obj.put("w", .{ .float = v });
                if (p.text.outline.color) |v| try outline_obj.put("color", .{ .string = v });
                if (outline_obj.count() > 0) {
                    try text_obj.put("outline", .{ .object = outline_obj });
                }
            }

            if (text_obj.count() > 0) {
                try out_obj.put("text", .{ .object = text_obj });
            }
        }

        if (p.hidden) {
            try out_obj.put("hidden", .{ .bool = true });
        }
        if (p.clip) {
            try out_obj.put("clip", .{ .bool = true });
        }

        if (p.class_extra.items.len > 0) {
            var extra_arr = std.json.Array.init(allocator);
            for (p.class_extra.items) |tok| {
                try extra_arr.append(.{ .string = tok });
            }
            try out_obj.put("classExtra", .{ .array = extra_arr });
        }
    }

    var other_keys: std.ArrayList([]const u8) = .empty;
    defer other_keys.deinit(allocator);

    var it = obj.iterator();
    while (it.next()) |entry| {
        const k = entry.key_ptr.*;
        if (std.mem.eql(u8, k, "tag")) continue;
        if (std.mem.eql(u8, k, "key")) continue;
        if (std.mem.eql(u8, k, "class")) continue;
        if (std.mem.eql(u8, k, "children")) continue;

        if (std.mem.eql(u8, k, "layout") or
            std.mem.eql(u8, k, "flex") or
            std.mem.eql(u8, k, "margin") or
            std.mem.eql(u8, k, "pad") or
            std.mem.eql(u8, k, "bg") or
            std.mem.eql(u8, k, "border") or
            std.mem.eql(u8, k, "rounded") or
            std.mem.eql(u8, k, "opacity") or
            std.mem.eql(u8, k, "z") or
            std.mem.eql(u8, k, "text") or
            std.mem.eql(u8, k, "hidden") or
            std.mem.eql(u8, k, "clip") or
            std.mem.eql(u8, k, "classExtra"))
        {
            continue;
        }

        try other_keys.append(allocator, k);
    }

    if (other_keys.items.len > 1) {
        std.sort.pdq([]const u8, other_keys.items, {}, lessThanString);
    }

    for (other_keys.items) |k| {
        try out_obj.put(k, try migrateValue(allocator, obj.get(k).?));
    }

    if (obj.get("children")) |children_val| {
        try out_obj.put("children", try migrateValue(allocator, children_val));
    }

    return .{ .object = out_obj };
}

fn insetValueToJson(allocator: Allocator, v: InsetValue) Allocator.Error!std.json.Value {
    return switch (v) {
        .pixels => |n| .{ .float = n },
        .pct => |p| blk: {
            var obj = std.json.ObjectMap.init(allocator);
            try obj.put("pct", .{ .float = p });
            break :blk .{ .object = obj };
        },
    };
}

fn sizeValueToJson(allocator: Allocator, v: LayoutSize) Allocator.Error!std.json.Value {
    return switch (v) {
        .full => .{ .string = "full" },
        .pixels => |n| .{ .float = n },
        .tw => |n| blk: {
            var obj = std.json.ObjectMap.init(allocator);
            try obj.put("tw", .{ .float = n });
            break :blk .{ .object = obj };
        },
    };
}

const Mode = enum { migrate, normalize };

fn parseMode(s: []const u8) ?Mode {
    if (std.mem.eql(u8, s, "migrate-luau-ui-json")) return .migrate;
    if (std.mem.eql(u8, s, "normalize")) return .normalize;
    return null;
}

fn usage(exe: []const u8) void {
    std.debug.print(
        \\usage:
        \\  {s} migrate-luau-ui-json <input_json_path> [--in-place | --out <output_path>]
        \\  {s} normalize <input_json_path> [--in-place | --out <output_path>]
        \\
    , .{ exe, exe });
}

const Output = union(enum) {
    stdout,
    file: []const u8,
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

    if (args.len < 3) {
        usage(args[0]);
        return error.InvalidArgs;
    }

    const mode = parseMode(args[1]) orelse {
        usage(args[0]);
        return error.InvalidArgs;
    };
    _ = mode;

    const input_path = args[2];

    var out_mode: Output = .stdout;
    var i: usize = 3;
    while (i < args.len) : (i += 1) {
        const a = args[i];
        if (std.mem.eql(u8, a, "--in-place")) {
            out_mode = .{ .file = input_path };
            continue;
        }
        if (std.mem.eql(u8, a, "--out")) {
            if (i + 1 >= args.len) {
                usage(args[0]);
                return error.InvalidArgs;
            }
            out_mode = .{ .file = args[i + 1] };
            i += 1;
            continue;
        }
        usage(args[0]);
        return error.InvalidArgs;
    }

    const input_bytes = try readFileAlloc(gpa_allocator, input_path, 1024 * 1024 * 16);
    defer gpa_allocator.free(input_bytes);

    const normalized = try normalizeJson5(gpa_allocator, input_bytes);
    defer gpa_allocator.free(normalized);

    const parsed = try std.json.parseFromSlice(std.json.Value, gpa_allocator, normalized, .{ .allocate = .alloc_always });
    defer parsed.deinit();

    const migrated = try migrateValue(allocator, parsed.value);

    switch (out_mode) {
        .stdout => {
            const stdout = std.fs.File.stdout();
            const out_bytes = try std.json.Stringify.valueAlloc(gpa_allocator, migrated, .{ .whitespace = .indent_2 });
            defer gpa_allocator.free(out_bytes);
            try stdout.writeAll(out_bytes);
            try stdout.writeAll("\n");
        },
        .file => |path| {
            const out_bytes = try std.json.Stringify.valueAlloc(gpa_allocator, migrated, .{ .whitespace = .indent_2 });
            defer gpa_allocator.free(out_bytes);
            try writeFile(path, out_bytes);
            const file = if (std.fs.path.isAbsolute(path))
                try std.fs.openFileAbsolute(path, .{ .mode = .read_write })
            else
                try std.fs.cwd().openFile(path, .{ .mode = .read_write });
            defer file.close();
            try file.seekFromEnd(0);
            try file.writeAll("\n");
        },
    }
}

fn readFileAlloc(allocator: Allocator, path: []const u8, max_bytes: usize) ![]u8 {
    const file = if (std.fs.path.isAbsolute(path))
        try std.fs.openFileAbsolute(path, .{ .mode = .read_only })
    else
        try std.fs.cwd().openFile(path, .{ .mode = .read_only });
    defer file.close();
    return file.readToEndAlloc(allocator, max_bytes);
}

fn writeFile(path: []const u8, bytes: []const u8) !void {
    if (std.fs.path.dirname(path)) |dir| {
        std.fs.cwd().makePath(dir) catch |err| switch (err) {
            error.PathAlreadyExists => {},
            else => return err,
        };
    }

    const file = if (std.fs.path.isAbsolute(path))
        try std.fs.createFileAbsolute(path, .{ .truncate = true })
    else
        try std.fs.cwd().createFile(path, .{ .truncate = true });
    defer file.close();
    try file.writeAll(bytes);
}
