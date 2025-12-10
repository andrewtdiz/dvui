const dvui = @import("dvui");
const tailwind = @import("tailwind.zig");

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
