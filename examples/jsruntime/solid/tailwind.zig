const std = @import("std");

const dvui = @import("dvui");

const color_data = @import("tailwind_colors.zig");

pub const Spec = struct {
    background: ?dvui.Color = null,
    text: ?dvui.Color = null,
    width: ?Width = null,
    is_flex: bool = false,
    direction: ?dvui.enums.Direction = null,
    justify: ?dvui.FlexBoxWidget.ContentPosition = null,
    align_items: ?dvui.FlexBoxWidget.AlignItems = null,
    align_content: ?dvui.FlexBoxWidget.AlignContent = null,
};

pub const Width = union(enum) {
    full,
    pixels: f32,
};

const LiteralKind = enum {
    flex_display,
    flex_row,
    flex_col,
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
};

const LiteralRule = struct {
    token: []const u8,
    kind: LiteralKind,
};

const literal_rules = [_]LiteralRule{
    .{ .token = "flex", .kind = .flex_display },
    .{ .token = "flex-row", .kind = .flex_row },
    .{ .token = "flex-col", .kind = .flex_col },
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
};

const PrefixRule = struct {
    prefix: []const u8,
    handler: fn (*Spec, []const u8) void,
};

const prefix_rules: [3]PrefixRule = .{
    .{ .prefix = "bg-", .handler = handleBackground },
    .{ .prefix = "text-", .handler = handleText },
    .{ .prefix = "w-", .handler = handleWidth },
};

const ColorMap = std.StaticStringMap(u32).initComptime(color_data.entries);

pub fn parse(classes: []const u8) Spec {
    var spec: Spec = .{};

    var tokens = std.mem.tokenizeAny(u8, classes, " \t\n\r");
    while (tokens.next()) |token| {
        if (token.len == 0) continue;
        if (handleLiteral(&spec, token)) continue;
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

fn applyLiteral(spec: *Spec, kind: LiteralKind) void {
    switch (kind) {
        .flex_display => spec.is_flex = true,
        .flex_row => spec.direction = .horizontal,
        .flex_col => spec.direction = .vertical,
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
    }
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
const width_scale: f32 = 4.0;

fn handleWidth(spec: *Spec, suffix: []const u8) void {
    if (std.mem.eql(u8, suffix, width_full)) {
        spec.width = .full;
        return;
    }
    if (std.mem.eql(u8, suffix, width_px)) {
        spec.width = .{ .pixels = 1.0 };
        return;
    }
    const value = std.fmt.parseFloat(f32, suffix) catch return;
    if (!std.math.isFinite(value) or value < 0) return;
    spec.width = .{ .pixels = value * width_scale };
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

fn colorFromPacked(value: u32) dvui.Color {
    const r: u8 = @intCast((value >> 24) & 0xff);
    const g: u8 = @intCast((value >> 16) & 0xff);
    const b: u8 = @intCast((value >> 8) & 0xff);
    const a: u8 = @intCast(value & 0xff);
    return dvui.Color{ .r = r, .g = g, .b = b, .a = a };
}
