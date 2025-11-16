const dvui = @import("dvui");
const tailwind = @import("tailwind.zig");

const Options = dvui.Options;
const FlexBoxWidget = dvui.FlexBoxWidget;

const Axis = enum { horizontal, vertical };

pub fn applyToOptions(spec: *const tailwind.ClassSpec, options: *Options) void {
    applyBackground(spec, options);
    applyText(spec, options);
    applyBorderColors(spec, options);
    applySpacing(spec, options);
    applyCornerRadius(spec, options);
    applyDimensions(spec, options);
    applyTypography(spec, options);
}

pub fn buildFlexOptions(spec: *const tailwind.ClassSpec) FlexBoxWidget.InitOptions {
    return .{
        .direction = flexDirection(spec),
        .justify_content = mapContentPosition(spec.justify_content),
        .align_items = mapAlignItems(spec.align_items),
        .align_content = mapAlignContent(spec.align_content),
    };
}

pub fn isFlex(spec: *const tailwind.ClassSpec) bool {
    return spec.display == .flex;
}

pub fn flexDirection(spec: *const tailwind.ClassSpec) dvui.enums.Direction {
    return switch (spec.flex_direction orelse .row) {
        .row => .horizontal,
        .column => .vertical,
    };
}

fn applyBackground(spec: *const tailwind.ClassSpec, options: *Options) void {
    if (spec.background_color) |color_value| {
        options.color_fill = packedToColor(color_value);
        options.background = true;
    }
}

fn applyText(spec: *const tailwind.ClassSpec, options: *Options) void {
    if (spec.text_color) |color_value| {
        options.color_text = packedToColor(color_value);
    }
}

fn applyBorderColors(spec: *const tailwind.ClassSpec, options: *Options) void {
    if (spec.border_color) |color_value| {
        options.color_border = packedToColor(color_value);
    }
}

fn applySpacing(spec: *const tailwind.ClassSpec, options: *Options) void {
    options.margin = applySideValues(&spec.margin, options.margin);
    options.padding = applySideValues(&spec.padding, options.padding);
    options.border = applySideValues(&spec.border, options.border);
}

fn applyCornerRadius(spec: *const tailwind.ClassSpec, options: *Options) void {
    if (spec.corner_radius) |radius| {
        options.corner_radius = dvui.Rect.all(radius);
    }
}

fn applyDimensions(spec: *const tailwind.ClassSpec, options: *Options) void {
    var expand_horizontal = false;
    var expand_vertical = false;

    if (spec.width) |dimension| {
        expand_horizontal = applyDimension(dimension, .horizontal, options) or expand_horizontal;
    }
    if (spec.height) |dimension| {
        expand_vertical = applyDimension(dimension, .vertical, options) or expand_vertical;
    }

    setExpand(options, expand_horizontal, expand_vertical);
}

fn applyTypography(spec: *const tailwind.ClassSpec, options: *Options) void {
    if (spec.font_size) |size| {
        if (options.font_style == null) {
            if (mapFontSize(size)) |style| {
                options.font_style = style;
            }
        }
    }
}

fn applyDimension(dimension: tailwind.Dimension, axis: Axis, options: *Options) bool {
    return switch (dimension) {
        .full => true,
        .screen => true,
        .fraction => true,
        .pixels => |value| blk: {
            setMinSize(options, axis, value);
            setMaxSize(options, axis, value);
            break :blk false;
        },
    };
}

fn setMinSize(options: *Options, axis: Axis, value: f32) void {
    var size: dvui.Size = options.min_size_content orelse dvui.Size{};
    switch (axis) {
        .horizontal => size.w = value,
        .vertical => size.h = value,
    }
    options.min_size_content = size;
}

fn setMaxSize(options: *Options, axis: Axis, value: f32) void {
    var size: Options.MaxSize = options.max_size_content orelse Options.MaxSize{
        .w = dvui.max_float_safe,
        .h = dvui.max_float_safe,
    };
    switch (axis) {
        .horizontal => size.w = value,
        .vertical => size.h = value,
    }
    options.max_size_content = size;
}

fn setExpand(options: *Options, want_horizontal: bool, want_vertical: bool) void {
    if (!want_horizontal and !want_vertical) return;

    const current = options.expand orelse .none;
    if (current == .ratio) return;

    var horizontal = want_horizontal;
    var vertical = want_vertical;

    switch (current) {
        .horizontal => horizontal = true,
        .vertical => vertical = true,
        .both => {
            horizontal = true;
            vertical = true;
        },
        .none => {},
        .ratio => return,
    }

    const desired = desiredExpand(horizontal, vertical);
    if (desired == .none) return;
    if (current != desired or options.expand == null) {
        options.expand = desired;
    }
}

fn desiredExpand(horizontal: bool, vertical: bool) Options.Expand {
    if (horizontal and vertical) return .both;
    if (horizontal) return .horizontal;
    if (vertical) return .vertical;
    return .none;
}

fn applySideValues(values: *const tailwind.SideValues, existing: ?dvui.Rect) ?dvui.Rect {
    if (!hasSideValues(values)) return existing;

    var rect = existing orelse dvui.Rect{};
    if (values.left) |value| rect.x = value;
    if (values.top) |value| rect.y = value;
    if (values.right) |value| rect.w = value;
    if (values.bottom) |value| rect.h = value;
    return rect;
}

fn hasSideValues(values: *const tailwind.SideValues) bool {
    return values.left != null or values.right != null or values.top != null or values.bottom != null;
}

fn mapFontSize(size: tailwind.FontSize) ?Options.FontStyle {
    return switch (size) {
        .xs => .caption,
        .sm => .caption_heading,
        .base => .body,
        .md => .body,
        .lg => .heading,
        .xl => .title_4,
        .xl2 => .title_3,
        .xl3 => .title_2,
        .xl4 => .title_1,
        .xl5 => .title,
    };
}

fn mapContentPosition(value: ?tailwind.ContentPosition) FlexBoxWidget.ContentPosition {
    if (value) |position| {
        return switch (position) {
            .start => .start,
            .center => .center,
            .end => .end,
            .between => .between,
            .around => .around,
        };
    }
    return .start;
}

fn mapAlignItems(value: ?tailwind.AlignItems) FlexBoxWidget.AlignItems {
    if (value) |align_items| {
        return switch (align_items) {
            .start => .start,
            .center => .center,
            .end => .end,
        };
    }
    return .start;
}

fn mapAlignContent(value: ?tailwind.AlignContent) FlexBoxWidget.AlignContent {
    if (value) |align_content| {
        return switch (align_content) {
            .start => .start,
            .center => .center,
            .end => .end,
        };
    }
    return .start;
}

fn packedToColor(value: tailwind.PackedColor) dvui.Color {
    return .{
        .r = @intCast((value >> 24) & 0xff),
        .g = @intCast((value >> 16) & 0xff),
        .b = @intCast((value >> 8) & 0xff),
        .a = @intCast(value & 0xff),
    };
}