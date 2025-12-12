const std = @import("std");

const dvui = @import("dvui");
const FontStyle = dvui.Options.FontStyle;

const color_data = @import("colors.zig");

pub const TextAlign = enum {
    left,
    center,
    right,
};

pub const Spec = struct {
    background: ?dvui.Color = null,
    text: ?dvui.Color = null,
    width: ?Width = null,
    height: ?Height = null,
    is_flex: bool = false,
    position: ?Position = null,
    top: ?f32 = null,
    right: ?f32 = null,
    bottom: ?f32 = null,
    left: ?f32 = null,
    direction: ?dvui.enums.Direction = null,
    justify: ?dvui.FlexBoxWidget.ContentPosition = null,
    align_items: ?dvui.FlexBoxWidget.AlignItems = null,
    align_content: ?dvui.FlexBoxWidget.AlignContent = null,
    margin: SideValues = .{},
    padding: SideValues = .{},
    border: SideValues = .{},
    border_color: ?dvui.Color = null,
    font_style: ?FontStyle = null,
    gap_row: ?f32 = null,
    gap_col: ?f32 = null,
    corner_radius: ?f32 = null,
    // Z-ordering (z-index). Default 0 preserves document order.
    z_index: i16 = 0,
    // Clip descendants to this node's bounds (overflow-hidden).
    clip_children: bool = false,
    // New easy wins
    hidden: bool = false,
    opacity: ?f32 = null,
    text_align: ?TextAlign = null,
};

// Compatibility alias for callers expecting ClassSpec.
pub const ClassSpec = Spec;

pub const Width = union(enum) {
    full,
    pixels: f32,
};

pub const Height = union(enum) {
    full,
    pixels: f32,
};

pub const Position = enum {
    absolute,
};

const SideTarget = enum {
    all,
    horizontal,
    vertical,
    top,
    right,
    bottom,
    left,
};

const SideValues = struct {
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

const LiteralKind = enum {
    flex_display,
    flex_row,
    flex_col,
    absolute,
    justify_start,
    justify_center,
    justify_end,
    justify_between,
    justify_around,
    align_items_start,
    align_items_center,
    align_items_end,
    align_content_start,
    align_content_center,
    align_content_end,
    // Visibility
    hidden,
    overflow_hidden,
    // Text alignment
    text_left,
    text_center,
    text_right,
};

const LiteralRule = struct {
    token: []const u8,
    kind: LiteralKind,
};

const literal_rules = [_]LiteralRule{
    .{ .token = "flex", .kind = .flex_display },
    .{ .token = "flex-row", .kind = .flex_row },
    .{ .token = "flex-col", .kind = .flex_col },
    .{ .token = "absolute", .kind = .absolute },
    .{ .token = "justify-start", .kind = .justify_start },
    .{ .token = "justify-center", .kind = .justify_center },
    .{ .token = "justify-end", .kind = .justify_end },
    .{ .token = "justify-between", .kind = .justify_between },
    .{ .token = "justify-around", .kind = .justify_around },
    .{ .token = "items-start", .kind = .align_items_start },
    .{ .token = "items-center", .kind = .align_items_center },
    .{ .token = "items-end", .kind = .align_items_end },
    .{ .token = "content-start", .kind = .align_content_start },
    .{ .token = "content-center", .kind = .align_content_center },
    .{ .token = "content-end", .kind = .align_content_end },
    // Visibility
    .{ .token = "hidden", .kind = .hidden },
    .{ .token = "overflow-hidden", .kind = .overflow_hidden },
    // Text alignment
    .{ .token = "text-left", .kind = .text_left },
    .{ .token = "text-center", .kind = .text_center },
    .{ .token = "text-right", .kind = .text_right },
};

const RoundedRule = struct {
    token: []const u8,
    radius: f32,
};

const rounded_rules = [_]RoundedRule{
    .{ .token = "rounded-none", .radius = 0.0 },
    .{ .token = "rounded-sm", .radius = 2.0 },
    .{ .token = "rounded", .radius = 4.0 },
    .{ .token = "rounded-md", .radius = 6.0 },
    .{ .token = "rounded-lg", .radius = 8.0 },
    .{ .token = "rounded-xl", .radius = 12.0 },
    .{ .token = "rounded-2xl", .radius = 16.0 },
    .{ .token = "rounded-3xl", .radius = 24.0 },
    .{ .token = "rounded-full", .radius = 9999.0 },
};

const PrefixRule = struct {
    prefix: []const u8,
    handler: fn (*Spec, []const u8) void,
};

const prefix_rules: [4]PrefixRule = .{
    .{ .prefix = "bg-", .handler = handleBackground },
    .{ .prefix = "text-", .handler = handleText },
    .{ .prefix = "w-", .handler = handleWidth },
    .{ .prefix = "h-", .handler = handleHeight },
};

const ColorMap = std.StaticStringMap(u32).initComptime(color_data.entries);

const spacing_scale: f32 = 4.0;
const border_default_width: f32 = 1.0;

const FontRule = struct {
    token: []const u8,
    style: FontStyle,
};

const font_rules = [_]FontRule{
    .{ .token = "text-xs", .style = .caption },
    .{ .token = "text-sm", .style = .caption_heading },
    .{ .token = "text-base", .style = .body },
    .{ .token = "text-lg", .style = .title_3 },
    .{ .token = "text-xl", .style = .title_2 },
    .{ .token = "text-2xl", .style = .title_1 },
    .{ .token = "text-3xl", .style = .title },
};

pub fn parse(classes: []const u8) Spec {
    var spec: Spec = .{};

    var tokens = std.mem.tokenizeAny(u8, classes, " \t\n\r");
    while (tokens.next()) |token| {
        if (token.len == 0) continue;
        if (handleLiteral(&spec, token)) continue;
        if (handleSpacing(&spec, token)) continue;
        if (handleInset(&spec, token)) continue;
        if (handleGap(&spec, token)) continue;
        if (handleBorder(&spec, token)) continue;
        if (handleRounded(&spec, token)) continue;
        if (handleTypography(&spec, token)) continue;
        if (handleOpacity(&spec, token)) continue;
        if (handleZIndex(&spec, token)) continue;
        _ = handlePrefixed(&spec, token);
    }

    return spec;
}

pub fn applyToOptions(spec: *const Spec, options: *dvui.Options) void {
    if (spec.background) |color_value| {
        options.color_fill = color_value;
        options.background = true;
    }
    if (spec.text) |color_value| {
        options.color_text = color_value;
    }
    if (spec.width) |w| {
        switch (w) {
            .full => applyFullWidth(options),
            .pixels => |px| applyFixedWidth(options, px),
        }
    }
    if (spec.height) |h| {
        switch (h) {
            .full => applyFullHeight(options),
            .pixels => |px| applyFixedHeight(options, px),
        }
    }
    options.margin = applySideValues(&spec.margin, options.margin);
    options.padding = applySideValues(&spec.padding, options.padding);
    options.border = applySideValues(&spec.border, options.border);
    if (spec.border_color) |color_value| {
        options.color_border = color_value;
    }
    if (spec.font_style) |style| {
        options.font_style = style;
    }
    if (spec.corner_radius) |radius| {
        options.corner_radius = dvui.Rect.all(radius);
    }
    // Text alignment via gravity_x
    if (spec.text_align) |text_alignment| {
        options.gravity_x = switch (text_alignment) {
            .left => 0.0,
            .center => 0.5,
            .right => 1.0,
        };
    }
}

pub fn buildFlexOptions(spec: *const Spec) dvui.FlexBoxWidget.InitOptions {
    var init: dvui.FlexBoxWidget.InitOptions = .{
        .direction = .horizontal,
        .justify_content = .start,
        .align_items = .start,
        .align_content = .start,
    };

    if (spec.direction) |dir| init.direction = dir;
    if (spec.justify) |value| init.justify_content = value;
    if (spec.align_items) |value| init.align_items = value;
    if (spec.align_content) |value| init.align_content = value;

    return init;
}

fn handleLiteral(spec: *Spec, token: []const u8) bool {
    for (literal_rules) |rule| {
        if (std.mem.eql(u8, token, rule.token)) {
            applyLiteral(spec, rule.kind);
            return true;
        }
    }
    return false;
}

fn handlePrefixed(spec: *Spec, token: []const u8) bool {
    inline for (prefix_rules) |rule| {
        if (token.len > rule.prefix.len and std.mem.startsWith(u8, token, rule.prefix)) {
            rule.handler(spec, token[rule.prefix.len..]);
            return true;
        }
    }
    return false;
}

fn handleTypography(spec: *Spec, token: []const u8) bool {
    for (font_rules) |rule| {
        if (std.mem.eql(u8, token, rule.token)) {
            spec.font_style = rule.style;
            return true;
        }
    }
    return false;
}

fn applyLiteral(spec: *Spec, kind: LiteralKind) void {
    switch (kind) {
        .flex_display => spec.is_flex = true,
        .flex_row => spec.direction = .horizontal,
        .flex_col => spec.direction = .vertical,
        .absolute => spec.position = .absolute,
        .justify_start => spec.justify = .start,
        .justify_center => spec.justify = .center,
        .justify_end => spec.justify = .end,
        .justify_between => spec.justify = .between,
        .justify_around => spec.justify = .around,
        .align_items_start => spec.align_items = .start,
        .align_items_center => spec.align_items = .center,
        .align_items_end => spec.align_items = .end,
        .align_content_start => spec.align_content = .start,
        .align_content_center => spec.align_content = .center,
        .align_content_end => spec.align_content = .end,
        // Visibility
        .hidden => spec.hidden = true,
        .overflow_hidden => spec.clip_children = true,
        // Text alignment
        .text_left => spec.text_align = .left,
        .text_center => spec.text_align = .center,
        .text_right => spec.text_align = .right,
    }
}

fn handleOpacity(spec: *Spec, token: []const u8) bool {
    const prefix = "opacity-";
    if (!std.mem.startsWith(u8, token, prefix)) return false;
    const suffix = token[prefix.len..];
    if (suffix.len == 0) return false;

    // Handle common Tailwind opacity values: 0, 5, 10, 20, 25, 30, 40, 50, 60, 70, 75, 80, 90, 95, 100
    const int_value = std.fmt.parseInt(u8, suffix, 10) catch return false;
    if (int_value > 100) return false;

    spec.opacity = @as(f32, @floatFromInt(int_value)) / 100.0;
    return true;
}

fn handleZIndex(spec: *Spec, token: []const u8) bool {
    const neg_prefix = "-z-";
    const prefix = "z-";

    var negative = false;
    var suffix: []const u8 = undefined;

    if (std.mem.startsWith(u8, token, neg_prefix)) {
        negative = true;
        suffix = token[neg_prefix.len..];
    } else if (std.mem.startsWith(u8, token, prefix)) {
        suffix = token[prefix.len..];
    } else {
        return false;
    }

    if (suffix.len == 0) return false;
    if (std.mem.eql(u8, suffix, "auto")) {
        spec.z_index = 0;
        return true;
    }

    if (suffix[0] == '[' and suffix[suffix.len - 1] == ']') {
        const inner = suffix[1 .. suffix.len - 1];
        if (inner.len == 0) return false;
        var value = std.fmt.parseInt(i16, inner, 10) catch return false;
        if (negative and value > 0) {
            value = -value;
        }
        spec.z_index = value;
        return true;
    }

    var value = std.fmt.parseInt(i16, suffix, 10) catch return false;
    if (negative) {
        value = -value;
    }
    spec.z_index = value;
    return true;
}

fn handleInset(spec: *Spec, token: []const u8) bool {
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

fn handleBackground(spec: *Spec, suffix: []const u8) void {
    if (lookupColor(suffix)) |color_value| {
        spec.background = color_value;
    }
}

fn handleText(spec: *Spec, suffix: []const u8) void {
    if (lookupColor(suffix)) |color_value| {
        spec.text = color_value;
    }
}

const width_full = "full";
const width_px = "px";
const height_full = "full";
const height_px = "px";
const dimension_scale: f32 = 4.0;

fn handleWidth(spec: *Spec, suffix: []const u8) void {
    if (std.mem.eql(u8, suffix, width_full)) {
        spec.width = .full;
        return;
    }
    if (std.mem.eql(u8, suffix, "screen")) {
        spec.width = .full; // screen = full viewport width
        return;
    }
    if (std.mem.eql(u8, suffix, width_px)) {
        spec.width = .{ .pixels = 1.0 };
        return;
    }
    const value = std.fmt.parseFloat(f32, suffix) catch return;
    if (!std.math.isFinite(value) or value < 0) return;
    spec.width = .{ .pixels = value * dimension_scale };
}

fn handleHeight(spec: *Spec, suffix: []const u8) void {
    if (std.mem.eql(u8, suffix, height_full)) {
        spec.height = .full;
        return;
    }
    if (std.mem.eql(u8, suffix, "screen")) {
        spec.height = .full; // screen = full viewport height
        return;
    }
    if (std.mem.eql(u8, suffix, height_px)) {
        spec.height = .{ .pixels = 1.0 };
        return;
    }
    const value = std.fmt.parseFloat(f32, suffix) catch return;
    if (!std.math.isFinite(value) or value < 0) return;
    spec.height = .{ .pixels = value * dimension_scale };
}

fn handleGap(spec: *Spec, token: []const u8) bool {
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

fn handleSpacing(spec: *Spec, token: []const u8) bool {
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
    const value = parseSpacingValue(token[idx..]) orelse return false;
    if (is_margin) {
        spec.margin.set(target, value);
    } else {
        spec.padding.set(target, value);
    }
    return true;
}

fn handleBorder(spec: *Spec, token: []const u8) bool {
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
        const dir_target: ?SideTarget = switch (suffix[0]) {
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
        if (lookupColor(rest)) |color_value| {
            spec.border_color = color_value;
            return true;
        }
        return false;
    }

    if (parseBorderWidth(suffix)) |width_value| {
        spec.border.set(.all, width_value);
        return true;
    }

    if (lookupColor(suffix)) |color_value| {
        spec.border_color = color_value;
        return true;
    }

    return false;
}

fn handleRounded(spec: *Spec, token: []const u8) bool {
    inline for (rounded_rules) |rule| {
        if (std.mem.eql(u8, token, rule.token)) {
            spec.corner_radius = rule.radius;
            return true;
        }
    }
    return false;
}

fn parseDirectionPrefix(suffix: []const u8) ?struct { target: SideTarget, consume_len: usize } {
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

fn applySideValues(values: *const SideValues, current: ?dvui.Rect) ?dvui.Rect {
    if (!values.any()) return current;
    var rect = current orelse dvui.Rect{};
    if (values.left) |v| rect.x = v;
    if (values.top) |v| rect.y = v;
    if (values.right) |v| rect.w = v;
    if (values.bottom) |v| rect.h = v;
    return rect;
}

fn lookupColor(name: []const u8) ?dvui.Color {
    if (ColorMap.get(name)) |_packed| {
        return colorFromPacked(_packed);
    }
    return null;
}

fn applyFullWidth(options: *dvui.Options) void {
    if (options.expand) |current| {
        options.expand = switch (current) {
            .none, .horizontal => .horizontal,
            .vertical => .both,
            .both => .both,
            .ratio => .ratio,
        };
    } else {
        options.expand = .horizontal;
    }
}

fn applyFixedWidth(options: *dvui.Options, width: f32) void {
    var min_size = options.min_size_content orelse dvui.Size{};
    min_size.w = width;
    options.min_size_content = min_size;

    var max_size = options.max_size_content orelse dvui.Options.MaxSize{
        .w = dvui.max_float_safe,
        .h = dvui.max_float_safe,
    };
    max_size.w = width;
    options.max_size_content = max_size;
}

fn applyFullHeight(options: *dvui.Options) void {
    if (options.expand) |current| {
        options.expand = switch (current) {
            .none, .vertical => .vertical,
            .horizontal => .both,
            .both => .both,
            .ratio => .ratio,
        };
    } else {
        options.expand = .vertical;
    }
}

fn applyFixedHeight(options: *dvui.Options, height: f32) void {
    var min_size = options.min_size_content orelse dvui.Size{};
    min_size.h = height;
    options.min_size_content = min_size;

    var max_size = options.max_size_content orelse dvui.Options.MaxSize{
        .w = dvui.max_float_safe,
        .h = dvui.max_float_safe,
    };
    max_size.h = height;
    options.max_size_content = max_size;
}

fn colorFromPacked(value: u32) dvui.Color {
    const r: u8 = @intCast((value >> 24) & 0xff);
    const g: u8 = @intCast((value >> 16) & 0xff);
    const b: u8 = @intCast((value >> 8) & 0xff);
    const a: u8 = @intCast(value & 0xff);
    return dvui.Color{ .r = r, .g = g, .b = b, .a = a };
}
