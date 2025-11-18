const std = @import("std");

const constants = @import("tailwind_constants.zig");

pub const PackedColor = u32;

pub const Display = enum {
    unspecified,
    flex,
    hidden,
};

pub const Position = enum {
    unspecified,
    relative,
    absolute,
    fixed,
};

pub const Dimension = union(enum) {
    full,
    screen,
    pixels: f32,
    fraction: f32,
};

pub const FlexDirection = enum { row, column };
pub const ContentPosition = enum { start, center, end, between, around };
pub const AlignItems = enum { start, center, end };
pub const AlignContent = enum { start, center, end };
pub const FontSize = constants.FontSize;
pub const FontWeight = constants.FontWeight;
pub const Cursor = constants.Cursor;

pub const ClassSpec = struct {
    display: Display = .unspecified,
    position: Position = .unspecified,
    width: ?Dimension = null,
    height: ?Dimension = null,
    flex_direction: ?FlexDirection = null,
    justify_content: ?ContentPosition = null,
    align_items: ?AlignItems = null,
    align_content: ?AlignContent = null,
    margin: SideValues = .{},
    padding: SideValues = .{},
    border: SideValues = .{},
    border_color: ?PackedColor = null,
    background_color: ?PackedColor = null,
    text_color: ?PackedColor = null,
    gap_row: ?f32 = null,
    gap_col: ?f32 = null,
    space_x: ?f32 = null,
    space_y: ?f32 = null,
    corner_radius: ?f32 = null,
    font_size: ?FontSize = null,
    font_weight: ?FontWeight = null,
    cursor: ?Cursor = null,
    top: ?f32 = null,
    bottom: ?f32 = null,
    left: ?f32 = null,
    right: ?f32 = null,
};

pub const Spec = ClassSpec;

pub const Config = struct {
    spacing_scale: f32 = 4.0,
    dimension_scale: f32 = 4.0,
    border_default_width: f32 = 1.0,
    palette: Palette = .builtin,

    pub const Palette = union(enum) {
        builtin,
        custom: []const PaletteEntry,
    };
};

pub const PaletteEntry = struct {
    name: []const u8,
    value: PackedColor,
};

var active_config: Config = .{};

const ColorMap = std.StaticStringMap(PackedColor).initComptime(constants.color_entries);
const LiteralKind = constants.LiteralKind;
const LiteralMap = constants.LiteralMap;
const RoundedMap = constants.RoundedMap;
const PrefixHandler = constants.PrefixHandler;
const PrefixRule = constants.PrefixRule;
const prefix_rules = constants.prefix_rules;
const FontMap = constants.FontMap;
const FontWeightMap = constants.FontWeightMap;
const rem_to_px: f32 = constants.rem_to_px;

const SideTarget = enum {
    all,
    horizontal,
    vertical,
    top,
    right,
    bottom,
    left,
};

pub const SideValues = struct {
    left: ?f32 = null,
    right: ?f32 = null,
    top: ?f32 = null,
    bottom: ?f32 = null,

    fn any(self: *const SideValues) bool {
        return self.left != null or self.right != null or self.top != null or self.bottom != null;
    }

    fn set(self: *SideValues, target: SideTarget, value: f32) void {
        switch (target) {
            .all => {
                self.left = value;
                self.right = value;
                self.top = value;
                self.bottom = value;
            },
            .horizontal => {
                self.left = value;
                self.right = value;
            },
            .vertical => {
                self.top = value;
                self.bottom = value;
            },
            .top => self.top = value,
            .right => self.right = value,
            .bottom => self.bottom = value,
            .left => self.left = value,
        }
    }
};

const SpacingAxis = enum { horizontal, vertical };

const AxisSpacingValue = struct {
    axis: SpacingAxis,
    value: f32,
};


pub fn defaultConfig() Config {
    return .{};
}

pub fn setConfig(new_config: Config) void {
    active_config = new_config;
}

pub fn config() *const Config {
    return &active_config;
}

pub fn parseClasses(classes: []const u8) ClassSpec {
    return parseClassesWithConfig(classes, &active_config);
}

pub fn parseClassesWithConfig(classes: []const u8, cfg: *const Config) ClassSpec {
    var spec: ClassSpec = .{};

    var tokens = std.mem.tokenizeAny(u8, classes, " \t\n\r");
    while (tokens.next()) |token| {
        if (token.len == 0) continue;
        if (handleLiteral(&spec, token)) continue;
        if (handleSpacing(&spec, token, cfg)) continue;
        if (handleGap(&spec, token, cfg)) continue;
        if (handleSpace(&spec, token, cfg)) continue;
        if (handleBorder(&spec, token, cfg)) continue;
        if (handleRounded(&spec, token)) continue;
        if (handleTypography(&spec, token)) continue;
        _ = handlePrefixed(&spec, token, cfg);
    }

    return spec;
}

pub fn lookupColor(name: []const u8) ?PackedColor {
    return lookupColorWithConfig(&active_config, name);
}

pub fn lookupColorWithConfig(cfg: *const Config, name: []const u8) ?PackedColor {
    return switch (cfg.palette) {
        .builtin => ColorMap.get(name),
        .custom => |entries| {
            for (entries) |entry| {
                if (std.mem.eql(u8, entry.name, name)) return entry.value;
            }
            return null;
        },
    };
}

fn handleLiteral(spec: *ClassSpec, token: []const u8) bool {
    if (LiteralMap.get(token)) |kind| {
        applyLiteral(spec, kind);
        return true;
    }
    return false;
}

fn handlePrefixed(spec: *ClassSpec, token: []const u8, cfg: *const Config) bool {
    for (prefix_rules) |rule| {
        if (token.len > rule.prefix.len and std.mem.startsWith(u8, token, rule.prefix)) {
            applyPrefixHandler(spec, token[rule.prefix.len..], cfg, rule.handler);
            return true;
        }
    }
    return false;
}

fn applyPrefixHandler(spec: *ClassSpec, suffix: []const u8, cfg: *const Config, handler: PrefixHandler) void {
    switch (handler) {
        .background => handleBackground(spec, suffix, cfg),
        .text => handleText(spec, suffix, cfg),
        .width => handleWidth(spec, suffix, cfg),
        .height => handleHeight(spec, suffix, cfg),
        .top => handleTop(spec, suffix, cfg),
        .bottom => handleBottom(spec, suffix, cfg),
        .left => handleLeft(spec, suffix, cfg),
        .right => handleRight(spec, suffix, cfg),
        .cursor => handleCursor(spec, suffix, cfg),
    }
}

fn handleTypography(spec: *ClassSpec, token: []const u8) bool {
    if (FontMap.get(token)) |size| {
        spec.font_size = size;
        return true;
    }
    if (FontWeightMap.get(token)) |weight| {
        spec.font_weight = weight;
        return true;
    }
    return false;
}

fn applyLiteral(spec: *ClassSpec, kind: LiteralKind) void {
    switch (kind) {
        .flex_display => spec.display = .flex,
        .hidden_display => spec.display = .hidden,
        .position_relative => spec.position = .relative,
        .position_absolute => spec.position = .absolute,
        .position_fixed => spec.position = .fixed,
        .flex_row => spec.flex_direction = .row,
        .flex_col => spec.flex_direction = .column,
        .justify_start => spec.justify_content = .start,
        .justify_center => spec.justify_content = .center,
        .justify_end => spec.justify_content = .end,
        .justify_between => spec.justify_content = .between,
        .justify_around => spec.justify_content = .around,
        .align_items_start => spec.align_items = .start,
        .align_items_center => spec.align_items = .center,
        .align_items_end => spec.align_items = .end,
        .align_content_start => spec.align_content = .start,
        .align_content_center => spec.align_content = .center,
        .align_content_end => spec.align_content = .end,
    }
}

fn handleBackground(spec: *ClassSpec, suffix: []const u8, cfg: *const Config) void {
    if (parseColorToken(suffix, cfg)) |color_value| {
        spec.background_color = color_value;
    }
}

fn handleText(spec: *ClassSpec, suffix: []const u8, cfg: *const Config) void {
    if (parseColorToken(suffix, cfg)) |color_value| {
        spec.text_color = color_value;
    }
}

fn handleWidth(spec: *ClassSpec, suffix: []const u8, cfg: *const Config) void {
    if (parseDimensionValue(suffix, cfg.dimension_scale)) |dimension| {
        spec.width = dimension;
    }
}

fn handleHeight(spec: *ClassSpec, suffix: []const u8, cfg: *const Config) void {
    if (parseDimensionValue(suffix, cfg.dimension_scale)) |dimension| {
        spec.height = dimension;
    }
}

fn handleTop(spec: *ClassSpec, suffix: []const u8, cfg: *const Config) void {
    spec.top = parseSpacingValue(suffix, cfg.spacing_scale);
}

fn handleBottom(spec: *ClassSpec, suffix: []const u8, cfg: *const Config) void {
    spec.bottom = parseSpacingValue(suffix, cfg.spacing_scale);
}

fn handleLeft(spec: *ClassSpec, suffix: []const u8, cfg: *const Config) void {
    spec.left = parseSpacingValue(suffix, cfg.spacing_scale);
}

fn handleRight(spec: *ClassSpec, suffix: []const u8, cfg: *const Config) void {
    spec.right = parseSpacingValue(suffix, cfg.spacing_scale);
}

fn handleCursor(spec: *ClassSpec, suffix: []const u8, _: *const Config) void {
    if (std.mem.eql(u8, suffix, "pointer")) {
        spec.cursor = .pointer;
        return;
    }
    if (std.mem.eql(u8, suffix, "wait")) {
        spec.cursor = .wait;
        return;
    }
    if (std.mem.eql(u8, suffix, "text")) {
        spec.cursor = .text;
        return;
    }
    if (std.mem.eql(u8, suffix, "default")) {
        spec.cursor = .default_cursor;
        return;
    }
    if (std.mem.eql(u8, suffix, "not-allowed")) {
        spec.cursor = .not_allowed;
        return;
    }
    if (std.mem.eql(u8, suffix, "move")) {
        spec.cursor = .move;
        return;
    }
    if (std.mem.eql(u8, suffix, "crosshair")) {
        spec.cursor = .crosshair;
    }
}

fn handleGap(spec: *ClassSpec, token: []const u8, cfg: *const Config) bool {
    const base = "gap-";
    if (!std.mem.startsWith(u8, token, base)) return false;
    const suffix = token[base.len..];
    if (suffix.len == 0) return false;

    if (parseAxisSpacingSuffix(suffix, cfg)) |axis_value| {
        switch (axis_value.axis) {
            .horizontal => spec.gap_col = axis_value.value,
            .vertical => spec.gap_row = axis_value.value,
        }
        return true;
    }

    const value = parseSpacingValue(suffix, cfg.spacing_scale) orelse return false;
    spec.gap_col = value;
    spec.gap_row = value;
    return true;
}

fn handleSpace(spec: *ClassSpec, token: []const u8, cfg: *const Config) bool {
    const base = "space-";
    if (!std.mem.startsWith(u8, token, base)) return false;
    const suffix = token[base.len..];
    if (suffix.len == 0) return false;

    const axis_value = parseAxisSpacingSuffix(suffix, cfg) orelse return false;
    switch (axis_value.axis) {
        .horizontal => {
            spec.space_x = axis_value.value;
            if (spec.gap_col == null) spec.gap_col = axis_value.value;
        },
        .vertical => {
            spec.space_y = axis_value.value;
            if (spec.gap_row == null) spec.gap_row = axis_value.value;
        },
    }
    return true;
}

fn parseAxisSpacingSuffix(suffix: []const u8, cfg: *const Config) ?AxisSpacingValue {
    if (suffix.len < 3) return null;
    const axis = switch (suffix[0]) {
        'x' => SpacingAxis.horizontal,
        'y' => SpacingAxis.vertical,
        else => return null,
    };
    if (suffix[1] != '-') return null;
    const value_slice = suffix[2..];
    if (value_slice.len == 0) return null;
    const value = parseSpacingValue(value_slice, cfg.spacing_scale) orelse return null;
    return .{ .axis = axis, .value = value };
}

fn handleSpacing(spec: *ClassSpec, token: []const u8, cfg: *const Config) bool {
    if (token.len < 3) return false;
    const kind = token[0];
    const is_margin = kind == 'm';
    const is_padding = kind == 'p';
    if (!is_margin and !is_padding) return false;

    var idx: usize = 1;
    var target: SideTarget = .all;
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
    const value = parseSpacingValue(token[idx..], cfg.spacing_scale) orelse return false;
    if (is_margin) {
        spec.margin.set(target, value);
    } else {
        spec.padding.set(target, value);
    }
    return true;
}

fn handleBorder(spec: *ClassSpec, token: []const u8, cfg: *const Config) bool {
    const prefix = "border";
    if (!std.mem.startsWith(u8, token, prefix)) return false;
    if (token.len == prefix.len) {
        spec.border.set(.all, cfg.border_default_width);
        return true;
    }
    if (token.len <= prefix.len or token[prefix.len] != '-') return false;
    var suffix = token[(prefix.len + 1)..];
    if (suffix.len == 0) return false;

    if (parseDirectionPrefix(suffix)) |dir_info| {
        var rest = suffix[dir_info.consume_len..];
        if (rest.len == 0) {
            spec.border.set(dir_info.target, cfg.border_default_width);
            return true;
        }
        if (rest[0] != '-') return false;
        rest = rest[1..];
        if (rest.len == 0) return false;
        if (parseBorderWidth(rest)) |value| {
            spec.border.set(dir_info.target, value);
            return true;
        }
        if (parseColorToken(rest, cfg)) |color_value| {
            spec.border_color = color_value;
            return true;
        }
        return false;
    }

    if (parseBorderWidth(suffix)) |width_value| {
        spec.border.set(.all, width_value);
        return true;
    }

    if (parseColorToken(suffix, cfg)) |color_value| {
        spec.border_color = color_value;
        return true;
    }

    return false;
}

fn handleRounded(spec: *ClassSpec, token: []const u8) bool {
    if (RoundedMap.get(token)) |radius| {
        spec.corner_radius = radius;
        return true;
    }
    return false;
}

fn parseDirectionPrefix(suffix: []const u8) ?struct { target: SideTarget, consume_len: usize } {
    if (suffix.len == 0) return null;
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

fn parseSpacingValue(token: []const u8, scale: f32) ?f32 {
    if (token.len == 0) return null;
    if (token.len >= 2 and token[0] == '[' and token[token.len - 1] == ']') {
        return parseExplicitMeasurement(token[1 .. token.len - 1]);
    }
    if (std.mem.eql(u8, token, "px")) return 1.0;
    const value = parsePositiveDecimal(token) orelse return null;
    return value * scale;
}

fn parseDimensionValue(token: []const u8, scale: f32) ?Dimension {
    if (token.len == 0) return null;
    if (std.mem.eql(u8, token, "full")) return .full;
    if (std.mem.eql(u8, token, "screen")) return .screen;
    if (std.mem.eql(u8, token, "px")) return .{ .pixels = 1.0 };
    if (token.len >= 2 and token[0] == '[' and token[token.len - 1] == ']') {
        const parsed = parseExplicitMeasurement(token[1 .. token.len - 1]) orelse return null;
        return .{ .pixels = parsed };
    }
    if (parseFraction(token)) |ratio| {
        return .{ .fraction = ratio };
    }
    const value = parsePositiveDecimal(token) orelse return null;
    return .{ .pixels = value * scale };
}

fn parseFraction(token: []const u8) ?f32 {
    const slash_index = std.mem.indexOfScalar(u8, token, '/') orelse return null;
    if (slash_index == 0 or slash_index + 1 >= token.len) return null;
    const numerator_slice = token[0..slash_index];
    const denominator_slice = token[(slash_index + 1)..];
    const numerator = parsePositiveDecimal(numerator_slice) orelse return null;
    const denominator = parsePositiveDecimal(denominator_slice) orelse return null;
    if (denominator == 0) return null;
    const result = numerator / denominator;
    if (!std.math.isFinite(result)) return null;
    return result;
}

fn parseExplicitMeasurement(raw: []const u8) ?f32 {
    if (raw.len == 0) return null;
    if (std.mem.endsWith(u8, raw, "px")) {
        if (raw.len == 2) return null;
        const slice = raw[0 .. raw.len - 2];
        const parsed = parsePositiveDecimal(slice) orelse return null;
        return parsed;
    }
    if (std.mem.endsWith(u8, raw, "rem")) {
        if (raw.len == 3) return null;
        const slice = raw[0 .. raw.len - 3];
        const parsed = parsePositiveDecimal(slice) orelse return null;
        return parsed * rem_to_px;
    }
    return parsePositiveDecimal(raw);
}

fn parseBorderWidth(token: []const u8) ?f32 {
    if (token.len == 0) return null;
    if (std.mem.eql(u8, token, "px")) return 1.0;
    return parsePositiveDecimal(token);
}

fn parsePositiveDecimal(token: []const u8) ?f32 {
    if (token.len == 0) return null;
    var seen_digit = false;
    var seen_dot = false;
    var integer_value: f32 = 0.0;
    var fraction_value: f32 = 0.0;
    var fraction_scale: f32 = 0.1;

    for (token) |ch| {
        switch (ch) {
            '0'...'9' => {
                seen_digit = true;
                const digit = @as(f32, @floatFromInt(ch - '0'));
                if (seen_dot) {
                    fraction_value += digit * fraction_scale;
                    fraction_scale *= 0.1;
                } else {
                    integer_value = integer_value * 10.0 + digit;
                }
            },
            '.' => {
                if (seen_dot) return null;
                seen_dot = true;
            },
            else => return null,
        }
    }

    if (!seen_digit) return null;
    const result = integer_value + fraction_value;
    if (!std.math.isFinite(result)) return null;
    return result;
}

fn parseColorToken(token: []const u8, cfg: *const Config) ?PackedColor {
    if (token.len == 0) return null;
    var color_slice = token;
    var opacity: ?f32 = null;

    if (std.mem.indexOfScalar(u8, token, '/')) |idx| {
        if (idx == 0 or idx + 1 >= token.len) return null;
        color_slice = token[0..idx];
        const opacity_slice = token[(idx + 1)..];
        const parsed = std.fmt.parseFloat(f32, opacity_slice) catch return null;
        if (!std.math.isFinite(parsed)) return null;
        opacity = if (parsed > 1.0) parsed / 100.0 else parsed;
    }

    const base = lookupColorWithConfig(cfg, color_slice) orelse return null;
    if (opacity) |ratio_value| {
        const clamped = @min(1.0, @max(0.0, ratio_value));
        const scaled: u32 = @intFromFloat(@round(clamped * 255.0));
        return (base & 0xffffff00) | scaled;
    }
    return base;
}