const std = @import("std");

const dvui = @import("dvui");

const types = @import("../core/types.zig");
const tailwind = @import("tailwind.zig");

pub fn dvuiColorToPacked(color: dvui.Color) types.PackedColor {
    const value: u32 = (@as(u32, color.r) << 24) | (@as(u32, color.g) << 16) | (@as(u32, color.b) << 8) | @as(u32, color.a);
    return .{ .value = value };
}

pub fn packedColorToDvui(color: types.PackedColor, opacity: f32) dvui.Color {
    const clamped_opacity = std.math.clamp(opacity, 0.0, 1.0);
    const r: u8 = @intCast((color.value >> 24) & 0xff);
    const g: u8 = @intCast((color.value >> 16) & 0xff);
    const b: u8 = @intCast((color.value >> 8) & 0xff);
    const a_base: u8 = @intCast(color.value & 0xff);
    const final_a: f32 = @as(f32, @floatFromInt(a_base)) / 255.0 * clamped_opacity * 255.0;
    const a: u8 = @intFromFloat(std.math.clamp(final_a, 0.0, 255.0));
    return .{ .r = r, .g = g, .b = b, .a = a };
}

pub fn applyClassSpecToVisual(node: *types.SolidNode, spec: *const tailwind.Spec) void {
    if (spec.background) |bg| {
        node.visual.background = dvuiColorToPacked(bg);
    }
    if (spec.text) |tc| {
        node.visual.text_color = dvuiColorToPacked(tc);
    }
    if (spec.corner_radius) |radius| {
        node.visual.corner_radius = radius;
    }
    // Apply opacity from Tailwind class (opacity-50, etc.)
    if (spec.opacity) |opacity| {
        node.visual.opacity = opacity;
    }
}

pub fn applyVisualToOptions(node: *const types.SolidNode, options: *dvui.Options) void {
    const opacity = node.visual.opacity;
    if (node.visual.background) |bg| {
        const color = packedColorToDvui(bg, opacity);
        options.background = true;
        options.color_fill = color;
        options.color_fill_hover = color;
        options.color_fill_press = color;
    }
    if (node.visual.text_color) |tc| {
        const color = packedColorToDvui(tc, opacity);
        options.color_text = color;
        options.color_text_hover = color;
        options.color_text_press = color;
    }
    if (node.visual.corner_radius != 0) {
        options.corner_radius = dvui.Rect.all(node.visual.corner_radius);
    }
}

pub fn applyToOptions(spec: *const tailwind.Spec, options: *dvui.Options) void {
    // Delegate to the full tailwind adapter so Solid nodes can pick up
    // backgrounds, text colors, spacing, sizing, etc.
    tailwind.applyToOptions(spec, options);
}

pub fn isFlex(spec: *const tailwind.Spec) bool {
    return spec.is_flex;
}

pub fn buildFlexOptions(spec: *const tailwind.Spec) dvui.FlexBoxWidget.InitOptions {
    return tailwind.buildFlexOptions(spec);
}

pub fn flexDirection(spec: *const tailwind.Spec) dvui.enums.Direction {
    return spec.direction orelse .horizontal;
}
