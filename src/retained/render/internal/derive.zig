const types = @import("../../core/types.zig");
const tailwind = @import("../../style/tailwind.zig");
const style_apply = @import("../../style/apply.zig");

const applyClassSpecToVisual = style_apply.applyClassSpecToVisual;

pub fn apply(node: *types.SolidNode) tailwind.Spec {
    var spec = node.prepareClassSpec();
    tailwind.applyHover(&spec, node.hovered);

    node.visual = node.visual_props;

    const class_scroll_enabled = spec.scroll_x or spec.scroll_y;
    node.scroll.class_enabled = class_scroll_enabled;
    node.scroll.class_x = spec.scroll_x;
    node.scroll.class_y = spec.scroll_y;

    applyClassSpecToVisual(node, &spec);
    if (node.scroll.isEnabled()) {
        node.visual.clip_children = true;
    }

    return spec;
}

