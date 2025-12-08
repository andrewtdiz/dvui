const dvui = @import("dvui");
const tailwind = @import("tailwind.zig");

pub fn applyToOptions(_: *const tailwind.Spec, _: *dvui.Options) void {
    // no-op stub
}

pub fn isFlex(_: *const tailwind.Spec) bool {
    return false;
}

pub fn buildFlexOptions(_: *const tailwind.Spec) dvui.FlexBoxWidget.InitOptions {
    return .{};
}

pub fn flexDirection(_: *const tailwind.Spec) dvui.enums.Direction {
    return .horizontal;
}
