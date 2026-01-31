const std = @import("std");
const dvui = @import("dvui");
const types = @import("types.zig");
const color = @import("parse_color_typography.zig");

const design_tokens = dvui.Theme.Tokens;

const spacing_scale: f32 = design_tokens.spacing_unit;
const border_default_width: f32 = design_tokens.border_width_default;
const rounded_rules = design_tokens.radius_tokens;
const dimension_scale: f32 = design_tokens.dimension_unit;

const width_full = "full";
const width_px = "px";
const height_full = "full";
const height_px = "px";

pub fn handleWidth(spec: *types.Spec, suffix: []const u8) void {
    if (std.mem.eql(u8, suffix, width_full)) {
        spec.width = .full;
        return;
    }
    if (std.mem.eql(u8, suffix, "screen")) {
        spec.width = .full;
        return;
    }
    if (std.mem.eql(u8, suffix, width_px)) {
        spec.width = .{ .pixels = 1.0 };
        return;
    }
    if (parseBracketValue(suffix)) |value| {
        spec.width = .{ .pixels = value };
        return;
    }
    const value = std.fmt.parseFloat(f32, suffix) catch return;
    if (!std.math.isFinite(value) or value < 0) return;
    spec.width = .{ .pixels = value * dimension_scale };
}

pub fn handleHeight(spec: *types.Spec, suffix: []const u8) void {
    if (std.mem.eql(u8, suffix, height_full)) {
        spec.height = .full;
        return;
    }
    if (std.mem.eql(u8, suffix, "screen")) {
        spec.height = .full;
        return;
    }
    if (std.mem.eql(u8, suffix, height_px)) {
        spec.height = .{ .pixels = 1.0 };
        return;
    }
    if (parseBracketValue(suffix)) |value| {
        spec.height = .{ .pixels = value };
        return;
    }
    const value = std.fmt.parseFloat(f32, suffix) catch return;
    if (!std.math.isFinite(value) or value < 0) return;
    spec.height = .{ .pixels = value * dimension_scale };
}

pub fn handleGap(spec: *types.Spec, token: []const u8) bool {
    const base = "gap-";
    if (!std.mem.startsWith(u8, token, base)) return false;
    var suffix = token[base.len..];
    if (suffix.len == 0) return false;

    if (suffix[0] == 'x' and suffix.len >= 2 and suffix[1] == '-') {
        suffix = suffix[2..];
        const value = parseSpacingValue(suffix) orelse return false;
        spec.gap_col = value;
        return true;
    }

    if (suffix[0] == 'y' and suffix.len >= 2 and suffix[1] == '-') {
        suffix = suffix[2..];
        const value = parseSpacingValue(suffix) orelse return false;
        spec.gap_row = value;
        return true;
    }

    const value = parseSpacingValue(suffix) orelse return false;
    spec.gap_col = value;
    spec.gap_row = value;
    return true;
}

pub fn handleScale(spec: *types.Spec, token: []const u8) bool {
    const base = "scale-";
    if (!std.mem.startsWith(u8, token, base)) return false;
    var suffix = token[base.len..];
    if (suffix.len == 0) return false;

    if (suffix[0] == '[' and suffix[suffix.len - 1] == ']') {
        suffix = suffix[1 .. suffix.len - 1];
        if (suffix.len == 0) return false;
        const value = std.fmt.parseFloat(f32, suffix) catch return false;
        if (!std.math.isFinite(value) or value <= 0) return false;
        spec.scale = value;
        return true;
    }

    const value = std.fmt.parseFloat(f32, suffix) catch return false;
    if (!std.math.isFinite(value) or value <= 0) return false;
    const scaled = if (value >= 10.0) value / 100.0 else value;
    spec.scale = scaled;
    return true;
}

pub fn handleSpacing(spec: *types.Spec, token: []const u8) bool {
    if (token.len < 3) return false;
    const kind = token[0];
    const is_margin = kind == 'm';
    const is_padding = kind == 'p';
    if (!is_margin and !is_padding) return false;

    var idx: usize = 1;
    var target: types.SideTarget = .all;
    if (idx < token.len and token[idx] != '-') {
        target = switch (token[idx]) {
            'x' => .horizontal,
            'y' => .vertical,
            't' => .top,
            'r' => .right,
            'b' => .bottom,
            'l' => .left,
            else => return false,
        };
        idx += 1;
    }
    if (idx >= token.len or token[idx] != '-') return false;
    idx += 1;
    if (idx >= token.len) return false;
    const value = parseSpacingValue(token[idx..]) orelse return false;
    if (is_margin) {
        spec.margin.set(target, value);
    } else {
        spec.padding.set(target, value);
    }
    return true;
}

pub fn handleBorder(spec: *types.Spec, token: []const u8) bool {
    const prefix = "border";
    if (!std.mem.startsWith(u8, token, prefix)) return false;
    if (token.len == prefix.len) {
        spec.border.set(.all, border_default_width);
        return true;
    }
    if (token.len <= prefix.len or token[prefix.len] != '-') return false;
    var suffix = token[(prefix.len + 1)..];
    if (suffix.len == 0) return false;

    if (suffix.len == 1) {
        const dir_target: ?types.SideTarget = switch (suffix[0]) {
            'x' => .horizontal,
            'y' => .vertical,
            't' => .top,
            'r' => .right,
            'b' => .bottom,
            'l' => .left,
            else => null,
        };
        if (dir_target) |target| {
            spec.border.set(target, border_default_width);
            return true;
        }
    }

    if (parseDirectionPrefix(suffix)) |dir_info| {
        var rest = suffix[dir_info.consume_len..];
        if (rest.len == 0) {
            spec.border.set(dir_info.target, border_default_width);
            return true;
        }
        if (rest[0] != '-') return false;
        rest = rest[1..];
        if (rest.len == 0) return false;
        if (parseBorderWidth(rest)) |value| {
            spec.border.set(dir_info.target, value);
            return true;
        }
        if (color.lookupColorToken(.border, rest)) |color_value| {
            spec.border_color = color_value;
            return true;
        }
        return false;
    }

    if (parseBorderWidth(suffix)) |width_value| {
        spec.border.set(.all, width_value);
        return true;
    }

    if (color.lookupColorToken(.border, suffix)) |color_value| {
        spec.border_color = color_value;
        return true;
    }

    return false;
}

pub fn handleRounded(spec: *types.Spec, token: []const u8) bool {
    inline for (rounded_rules) |rule| {
        if (std.mem.eql(u8, token, rule.token)) {
            spec.corner_radius = rule.radius;
            return true;
        }
    }
    return false;
}

pub fn handleInset(spec: *types.Spec, token: []const u8) bool {
    const top_prefix = "top-";
    const right_prefix = "right-";
    const bottom_prefix = "bottom-";
    const left_prefix = "left-";

    if (std.mem.startsWith(u8, token, top_prefix)) {
        const value = parseInsetValue(token[top_prefix.len..]) orelse return false;
        spec.top = value;
        return true;
    }
    if (std.mem.startsWith(u8, token, right_prefix)) {
        const value = parseInsetValue(token[right_prefix.len..]) orelse return false;
        spec.right = value;
        return true;
    }
    if (std.mem.startsWith(u8, token, bottom_prefix)) {
        const value = parseInsetValue(token[bottom_prefix.len..]) orelse return false;
        spec.bottom = value;
        return true;
    }
    if (std.mem.startsWith(u8, token, left_prefix)) {
        const value = parseInsetValue(token[left_prefix.len..]) orelse return false;
        spec.left = value;
        return true;
    }

    return false;
}

pub fn handleHoverSpacing(spec: *types.Spec, token: []const u8) bool {
    if (token.len < 3) return false;
    const kind = token[0];
    const is_margin = kind == 'm';
    const is_padding = kind == 'p';
    if (!is_margin and !is_padding) return false;

    var idx: usize = 1;
    var target: types.SideTarget = .all;
    if (idx < token.len and token[idx] != '-') {
        target = switch (token[idx]) {
            'x' => .horizontal,
            'y' => .vertical,
            't' => .top,
            'r' => .right,
            'b' => .bottom,
            'l' => .left,
            else => return false,
        };
        idx += 1;
    }
    if (idx >= token.len or token[idx] != '-') return false;
    idx += 1;
    if (idx >= token.len) return false;
    const value = parseSpacingValue(token[idx..]) orelse return false;
    if (is_margin) {
        spec.hover_margin.set(target, value);
    } else {
        spec.hover_padding.set(target, value);
    }
    return true;
}

pub fn handleHoverBorder(spec: *types.Spec, token: []const u8) bool {
    const prefix = "border";
    if (!std.mem.startsWith(u8, token, prefix)) return false;
    if (token.len == prefix.len) {
        spec.hover_border.set(.all, border_default_width);
        return true;
    }
    if (token.len <= prefix.len or token[prefix.len] != '-') return false;
    var suffix = token[(prefix.len + 1)..];
    if (suffix.len == 0) return false;

    if (suffix.len == 1) {
        const dir_target: ?types.SideTarget = switch (suffix[0]) {
            'x' => .horizontal,
            'y' => .vertical,
            't' => .top,
            'r' => .right,
            'b' => .bottom,
            'l' => .left,
            else => null,
        };
        if (dir_target) |target| {
            spec.hover_border.set(target, border_default_width);
            return true;
        }
    }

    if (parseDirectionPrefix(suffix)) |dir_info| {
        var rest = suffix[dir_info.consume_len..];
        if (rest.len == 0) {
            spec.hover_border.set(dir_info.target, border_default_width);
            return true;
        }
        if (rest[0] != '-') return false;
        rest = rest[1..];
        if (rest.len == 0) return false;
        if (parseBorderWidth(rest)) |value| {
            spec.hover_border.set(dir_info.target, value);
            return true;
        }
        if (color.lookupColorToken(.border, rest)) |color_value| {
            spec.hover_border_color = color_value;
            return true;
        }
        return false;
    }

    if (parseBorderWidth(suffix)) |width_value| {
        spec.hover_border.set(.all, width_value);
        return true;
    }

    if (color.lookupColorToken(.border, suffix)) |color_value| {
        spec.hover_border_color = color_value;
        return true;
    }

    return false;
}

fn parseDirectionPrefix(suffix: []const u8) ?struct { target: types.SideTarget, consume_len: usize } {
    if (suffix.len < 2 or suffix[1] != '-') return null;
    return switch (suffix[0]) {
        'x' => .{ .target = .horizontal, .consume_len = 1 },
        'y' => .{ .target = .vertical, .consume_len = 1 },
        't' => .{ .target = .top, .consume_len = 1 },
        'r' => .{ .target = .right, .consume_len = 1 },
        'b' => .{ .target = .bottom, .consume_len = 1 },
        'l' => .{ .target = .left, .consume_len = 1 },
        else => null,
    };
}

fn parseSpacingValue(token: []const u8) ?f32 {
    if (token.len == 0) return null;
    if (std.mem.eql(u8, token, "px")) return 1.0;
    const value = std.fmt.parseFloat(f32, token) catch return null;
    if (!std.math.isFinite(value) or value < 0) return null;
    return value * spacing_scale;
}

fn parseBorderWidth(token: []const u8) ?f32 {
    if (token.len == 0) return null;
    if (std.mem.eql(u8, token, "px")) return 1.0;
    const value = std.fmt.parseFloat(f32, token) catch return null;
    if (!std.math.isFinite(value) or value < 0) return null;
    return value;
}

fn parseInsetValue(token: []const u8) ?f32 {
    if (token.len == 0) return null;
    if (token[0] == '[' and token[token.len - 1] == ']') {
        const inner = token[1 .. token.len - 1];
        if (inner.len == 0) return null;

        var num_slice = inner;
        if (std.mem.endsWith(u8, inner, "px")) {
            num_slice = inner[0 .. inner.len - 2];
        }
        const value = std.fmt.parseFloat(f32, num_slice) catch return null;
        if (!std.math.isFinite(value)) return null;
        return value;
    }
    return parseSpacingValue(token);
}

fn parseBracketValue(token: []const u8) ?f32 {
    if (token.len < 2 or token[0] != '[' or token[token.len - 1] != ']') return null;
    const inner = token[1 .. token.len - 1];
    if (inner.len == 0) return null;

    var num_slice = inner;
    if (std.mem.endsWith(u8, inner, "px")) {
        num_slice = inner[0 .. inner.len - 2];
    }
    const value = std.fmt.parseFloat(f32, num_slice) catch return null;
    if (!std.math.isFinite(value) or value < 0) return null;
    return value;
}
