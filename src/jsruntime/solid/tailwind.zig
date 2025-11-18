const dvui = @import("dvui");

const tailwind = @import("../../tailwindcss/tailwind.zig");
const dvui_bridge = @import("../../tailwindcss/dvui_bridge.zig");

pub const Spec = tailwind.ClassSpec;

pub fn parse(classes: []const u8) Spec {
    return tailwind.parseClasses(classes);
}

pub fn lookupColor(name: []const u8) ?dvui.Color {
    const packed = tailwind.lookupColor(name) orelse return null;
    return packedToColor(packed);
}

pub fn applyToOptions(spec: *const Spec, options: *dvui.Options) void {
    dvui_bridge.applyToOptions(spec, options);
}

pub fn buildFlexOptions(spec: *const Spec) dvui.FlexBoxWidget.InitOptions {
    return dvui_bridge.buildFlexOptions(spec);
}

pub fn isFlex(spec: *const Spec) bool {
    return dvui_bridge.isFlex(spec);
}

pub fn flexDirection(spec: *const Spec) dvui.enums.Direction {
    return dvui_bridge.flexDirection(spec);
}

pub fn gapRow(spec: *const Spec) ?f32 {
    return spec.gap_row;
}

pub fn gapCol(spec: *const Spec) ?f32 {
    return spec.gap_col;
}

fn packedToColor(value: tailwind.PackedColor) dvui.Color {
    return .{
        .r = @intCast((value >> 24) & 0xff),
        .g = @intCast((value >> 16) & 0xff),
        .b = @intCast((value >> 8) & 0xff),
        .a = @intCast(value & 0xff),
    };
}
