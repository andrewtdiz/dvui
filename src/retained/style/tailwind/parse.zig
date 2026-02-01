const std = @import("std");
const dvui = @import("dvui");
const types = @import("types.zig");
const layout = @import("parse_layout.zig");
const color = @import("parse_color_typography.zig");

const design_tokens = dvui.Theme.Tokens;
const z_layer_tokens = design_tokens.z_layers;

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
    hidden,
    overflow_hidden,
    overflow_scroll,
    overflow_x_scroll,
    overflow_y_scroll,
    text_left,
    text_center,
    text_right,
    text_nowrap,
    break_words,
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
    .{ .token = "hidden", .kind = .hidden },
    .{ .token = "overflow-hidden", .kind = .overflow_hidden },
    .{ .token = "overflow-scroll", .kind = .overflow_scroll },
    .{ .token = "overflow-x-scroll", .kind = .overflow_x_scroll },
    .{ .token = "overflow-y-scroll", .kind = .overflow_y_scroll },
    .{ .token = "text-left", .kind = .text_left },
    .{ .token = "text-center", .kind = .text_center },
    .{ .token = "text-right", .kind = .text_right },
    .{ .token = "text-nowrap", .kind = .text_nowrap },
    .{ .token = "break-words", .kind = .break_words },
};

const AnchorRule = struct {
    token: []const u8,
    anchor: [2]f32,
};

const anchor_rules = [_]AnchorRule{
    .{ .token = "anchor-top-left", .anchor = .{ 0.0, 0.0 } },
    .{ .token = "anchor-top", .anchor = .{ 0.5, 0.0 } },
    .{ .token = "anchor-top-right", .anchor = .{ 1.0, 0.0 } },
    .{ .token = "anchor-left", .anchor = .{ 0.0, 0.5 } },
    .{ .token = "anchor-center", .anchor = .{ 0.5, 0.5 } },
    .{ .token = "anchor-right", .anchor = .{ 1.0, 0.5 } },
    .{ .token = "anchor-bottom-left", .anchor = .{ 0.0, 1.0 } },
    .{ .token = "anchor-bottom", .anchor = .{ 0.5, 1.0 } },
    .{ .token = "anchor-bottom-right", .anchor = .{ 1.0, 1.0 } },
};

const PrefixRule = struct {
    prefix: []const u8,
    handler: fn (*types.Spec, []const u8) void,
};

const prefix_rules: [4]PrefixRule = .{
    .{ .prefix = "bg-", .handler = color.handleBackground },
    .{ .prefix = "text-", .handler = color.handleText },
    .{ .prefix = "w-", .handler = layout.handleWidth },
    .{ .prefix = "h-", .handler = layout.handleHeight },
};

pub fn parse(classes: []const u8) types.Spec {
    var spec: types.Spec = .{};

    var tokens = std.mem.tokenizeAny(u8, classes, " \t\n\r");
    while (tokens.next()) |token| {
        if (token.len == 0) continue;
        if (handleHover(&spec, token)) continue;
        if (handleLiteral(&spec, token)) continue;
        if (handleAnchor(&spec, token)) continue;
        if (layout.handleSpacing(&spec, token)) continue;
        if (layout.handleInset(&spec, token)) continue;
        if (layout.handleGap(&spec, token)) continue;
        if (layout.handleScale(&spec, token)) continue;
        if (layout.handleBorder(&spec, token)) continue;
        if (layout.handleRounded(&spec, token)) continue;
        if (color.handleTypography(&spec, token)) continue;
        if (color.handleFontToken(&spec, token)) continue;
        if (color.handleFontRenderMode(&spec, token)) continue;
        if (color.handleOpacity(&spec, token)) continue;
        if (handleZIndex(&spec, token)) continue;
        if (handleCursor(&spec, token)) continue;
        if (handleTransition(&spec, token)) continue;
        if (handleDuration(&spec, token)) continue;
        if (handleEase(&spec, token)) continue;
        _ = handlePrefixed(&spec, token);
    }

    return spec;
}

fn handleHover(spec: *types.Spec, token: []const u8) bool {
    const prefix = "hover:";
    if (!std.mem.startsWith(u8, token, prefix)) return false;
    const inner = token[prefix.len..];
    if (inner.len == 0) return true;
    if (color.handleHoverOpacity(spec, inner)) return true;
    if (layout.handleHoverSpacing(spec, inner)) return true;
    if (layout.handleHoverBorder(spec, inner)) return true;
    if (handleHoverPrefixed(spec, inner)) return true;
    return true;
}

fn handleHoverPrefixed(spec: *types.Spec, token: []const u8) bool {
    if (std.mem.startsWith(u8, token, "bg-")) {
        color.handleHoverBackground(spec, token[3..]);
        return true;
    }
    if (std.mem.startsWith(u8, token, "text-")) {
        color.handleHoverText(spec, token[5..]);
        return true;
    }
    return false;
}

fn handleLiteral(spec: *types.Spec, token: []const u8) bool {
    for (literal_rules) |rule| {
        if (std.mem.eql(u8, token, rule.token)) {
            applyLiteral(spec, rule.kind);
            return true;
        }
    }
    return false;
}

fn handleAnchor(spec: *types.Spec, token: []const u8) bool {
    for (anchor_rules) |rule| {
        if (std.mem.eql(u8, token, rule.token)) {
            spec.layout_anchor = rule.anchor;
            return true;
        }
    }
    return false;
}

fn handlePrefixed(spec: *types.Spec, token: []const u8) bool {
    inline for (prefix_rules) |rule| {
        if (token.len > rule.prefix.len and std.mem.startsWith(u8, token, rule.prefix)) {
            rule.handler(spec, token[rule.prefix.len..]);
            return true;
        }
    }
    return false;
}

fn applyLiteral(spec: *types.Spec, kind: LiteralKind) void {
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
        .hidden => spec.hidden = true,
        .overflow_hidden => spec.clip_children = true,
        .overflow_scroll => {
            spec.scroll_x = true;
            spec.scroll_y = true;
        },
        .overflow_x_scroll => spec.scroll_x = true,
        .overflow_y_scroll => spec.scroll_y = true,
        .text_left => spec.text_align = .left,
        .text_center => spec.text_align = .center,
        .text_right => spec.text_align = .right,
        .text_nowrap => spec.text_wrap = false,
        .break_words => spec.break_words = true,
    }
}

fn handleZIndex(spec: *types.Spec, token: []const u8) bool {
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
        spec.z_index = design_tokens.z_index_default;
        return true;
    }

    if (lookupZLayer(suffix)) |layer_value| {
        const value = if (negative) -layer_value else layer_value;
        spec.z_index = value;
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

fn lookupZLayer(name: []const u8) ?i16 {
    for (z_layer_tokens) |layer| {
        if (std.mem.eql(u8, name, layer.token)) {
            return layer.value;
        }
    }
    return null;
}

fn handleCursor(spec: *types.Spec, token: []const u8) bool {
    const prefix = "cursor-";
    if (!std.mem.startsWith(u8, token, prefix)) return false;
    const name = token[prefix.len..];
    const cursor = if (std.mem.eql(u8, name, "auto") or std.mem.eql(u8, name, "default"))
        dvui.enums.Cursor.arrow
    else if (std.mem.eql(u8, name, "pointer"))
        dvui.enums.Cursor.hand
    else if (std.mem.eql(u8, name, "text"))
        dvui.enums.Cursor.ibeam
    else if (std.mem.eql(u8, name, "move"))
        dvui.enums.Cursor.arrow_all
    else if (std.mem.eql(u8, name, "wait"))
        dvui.enums.Cursor.wait
    else if (std.mem.eql(u8, name, "progress"))
        dvui.enums.Cursor.wait_arrow
    else if (std.mem.eql(u8, name, "crosshair"))
        dvui.enums.Cursor.crosshair
    else if (std.mem.eql(u8, name, "not-allowed"))
        dvui.enums.Cursor.bad
    else if (std.mem.eql(u8, name, "none"))
        dvui.enums.Cursor.hidden
    else if (std.mem.eql(u8, name, "grab") or std.mem.eql(u8, name, "grabbing"))
        dvui.enums.Cursor.hand
    else if (std.mem.eql(u8, name, "col-resize") or std.mem.eql(u8, name, "e-resize") or std.mem.eql(u8, name, "w-resize"))
        dvui.enums.Cursor.arrow_w_e
    else if (std.mem.eql(u8, name, "row-resize") or std.mem.eql(u8, name, "n-resize") or std.mem.eql(u8, name, "s-resize"))
        dvui.enums.Cursor.arrow_n_s
    else if (std.mem.eql(u8, name, "ne-resize") or std.mem.eql(u8, name, "sw-resize"))
        dvui.enums.Cursor.arrow_ne_sw
    else if (std.mem.eql(u8, name, "nw-resize") or std.mem.eql(u8, name, "se-resize"))
        dvui.enums.Cursor.arrow_nw_se
    else
        return false;
    spec.cursor = cursor;
    return true;
}

fn handleTransition(spec: *types.Spec, token: []const u8) bool {
    if (std.mem.eql(u8, token, "transition")) {
        spec.transition.enabled = true;
        spec.transition.props = .{ .layout = true, .transform = true, .colors = true, .opacity = true };
        return true;
    }
    if (std.mem.eql(u8, token, "transition-none")) {
        spec.transition = .{};
        return true;
    }
    if (std.mem.eql(u8, token, "transition-layout")) {
        spec.transition.enabled = true;
        spec.transition.props = .{ .layout = true };
        return true;
    }
    if (std.mem.eql(u8, token, "transition-transform")) {
        spec.transition.enabled = true;
        spec.transition.props = .{ .transform = true };
        return true;
    }
    if (std.mem.eql(u8, token, "transition-colors")) {
        spec.transition.enabled = true;
        spec.transition.props = .{ .colors = true };
        return true;
    }
    if (std.mem.eql(u8, token, "transition-opacity")) {
        spec.transition.enabled = true;
        spec.transition.props = .{ .opacity = true };
        return true;
    }
    return false;
}

fn handleDuration(spec: *types.Spec, token: []const u8) bool {
    const prefix = "duration-";
    if (!std.mem.startsWith(u8, token, prefix)) return false;
    const suffix = token[prefix.len..];
    if (suffix.len == 0) return false;

    const ms = std.fmt.parseInt(i32, suffix, 10) catch return false;
    const clamped_ms = std.math.clamp(ms, 0, 10_000);
    spec.transition.duration_us = clamped_ms * 1000;
    return true;
}

fn handleEase(spec: *types.Spec, token: []const u8) bool {
    if (std.mem.eql(u8, token, "ease-linear")) {
        spec.transition.easing_style = .linear;
        return true;
    }

    if (std.mem.eql(u8, token, "ease-in")) {
        spec.transition.easing_dir = .@"in";
        return true;
    }
    if (std.mem.eql(u8, token, "ease-out")) {
        spec.transition.easing_dir = .out;
        return true;
    }
    if (std.mem.eql(u8, token, "ease-in-out")) {
        spec.transition.easing_dir = .in_out;
        return true;
    }

    if (std.mem.eql(u8, token, "ease-sine")) {
        spec.transition.easing_style = .sine;
        return true;
    }
    if (std.mem.eql(u8, token, "ease-quad")) {
        spec.transition.easing_style = .quad;
        return true;
    }
    if (std.mem.eql(u8, token, "ease-cubic")) {
        spec.transition.easing_style = .cubic;
        return true;
    }
    if (std.mem.eql(u8, token, "ease-quart")) {
        spec.transition.easing_style = .quart;
        return true;
    }
    if (std.mem.eql(u8, token, "ease-quint")) {
        spec.transition.easing_style = .quint;
        return true;
    }
    if (std.mem.eql(u8, token, "ease-expo")) {
        spec.transition.easing_style = .expo;
        return true;
    }
    if (std.mem.eql(u8, token, "ease-circ")) {
        spec.transition.easing_style = .circ;
        return true;
    }
    if (std.mem.eql(u8, token, "ease-back")) {
        spec.transition.easing_style = .back;
        return true;
    }
    if (std.mem.eql(u8, token, "ease-elastic")) {
        spec.transition.easing_style = .elastic;
        return true;
    }
    if (std.mem.eql(u8, token, "ease-bounce")) {
        spec.transition.easing_style = .bounce;
        return true;
    }

    return false;
}
