const dvui = @import("dvui");

const types = @import("../../core/types.zig");
const tailwind = @import("../../style/tailwind.zig");
const style_apply = @import("../../style/apply.zig");

const applyClassSpecToVisual = style_apply.applyClassSpecToVisual;

pub fn apply(win: *dvui.Window, node: *types.SolidNode) tailwind.Spec {
    var spec = node.prepareClassSpec();
    tailwind.applyHover(&spec, node.hovered);

    node.visual = node.visual_props;

    applyClassSpecToVisual(win, node, &spec);

    return spec;
}

