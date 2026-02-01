const dvui = @import("dvui");

const types = @import("../../core/types.zig");

pub fn applyLayoutScaleToOptions(node: *const types.SolidNode, options: *dvui.Options) void {
    const natural = dvui.windowNaturalScale();
    if (natural == 0) return;
    const layout_scale = node.layout.layout_scale;
    if (layout_scale == 0) return;
    const factor = layout_scale / natural;
    if (factor == 1.0) return;
    if (options.margin) |m| options.margin = m.scale(factor, dvui.Rect);
    if (options.border) |b| options.border = b.scale(factor, dvui.Rect);
    if (options.padding) |p| options.padding = p.scale(factor, dvui.Rect);
    if (options.corner_radius) |c| options.corner_radius = c.scale(factor, dvui.Rect);
    if (options.min_size_content) |ms| options.min_size_content = dvui.Size{ .w = ms.w * factor, .h = ms.h * factor };
    if (options.max_size_content) |mx| options.max_size_content = dvui.Options.MaxSize{ .w = mx.w * factor, .h = mx.h * factor };
    if (options.text_outline_thickness) |v| options.text_outline_thickness = v * factor;
    const font = options.fontGet();
    options.font = font.resize(font.size * factor);
}

pub fn nodeHasAccessibilityProps(node: *const types.SolidNode) bool {
    if (node.access_role != null) return true;
    if (node.access_label.len > 0) return true;
    if (node.access_description.len > 0) return true;
    if (node.access_expanded != null) return true;
    if (node.access_selected != null) return true;
    if (node.access_toggled != null) return true;
    if (node.access_hidden != null) return true;
    if (node.access_disabled != null) return true;
    if (node.access_has_popup != null) return true;
    if (node.access_modal != null) return true;
    return false;
}

pub fn applyAccessibilityOptions(
    node: *const types.SolidNode,
    options: *dvui.Options,
    fallback_role: ?dvui.AccessKit.Role,
) void {
    if (node.access_role) |role| {
        options.role = role;
    } else if (fallback_role != null and nodeHasAccessibilityProps(node)) {
        options.role = fallback_role.?;
    }
    if (node.access_label.len > 0) {
        options.label = .{ .text = node.access_label };
    }
}

pub fn applyAccessibilityState(node: *const types.SolidNode, wd: *dvui.WidgetData) void {
    if (wd.accesskit_node()) |ak_node| {
        if (node.access_description.len > 0) {
            const desc = dvui.currentWindow().arena().dupeZ(u8, node.access_description) catch "";
            defer dvui.currentWindow().arena().free(desc);
            dvui.AccessKit.nodeSetDescription(ak_node, desc);
        }
        if (node.access_expanded) |flag| {
            dvui.AccessKit.nodeSetExpanded(ak_node, flag);
        } else {
            dvui.AccessKit.nodeClearExpanded(ak_node);
        }
        if (node.access_selected) |flag| {
            dvui.AccessKit.nodeSetSelected(ak_node, flag);
        } else {
            dvui.AccessKit.nodeClearSelected(ak_node);
        }
        if (node.access_toggled) |state_value| {
            const toggled = switch (state_value) {
                .ak_false => dvui.AccessKit.Toggled.ak_false,
                .ak_true => dvui.AccessKit.Toggled.ak_true,
                .mixed => dvui.AccessKit.Toggled.mixed,
            };
            dvui.AccessKit.nodeSetToggled(ak_node, toggled);
        } else {
            dvui.AccessKit.nodeClearToggled(ak_node);
        }
        if (node.access_hidden) |flag| {
            dvui.AccessKit.nodeSetHidden(ak_node, flag);
        } else {
            dvui.AccessKit.nodeClearHidden(ak_node);
        }
        if (node.access_disabled) |flag| {
            dvui.AccessKit.nodeSetDisabled(ak_node, flag);
        } else {
            dvui.AccessKit.nodeClearDisabled(ak_node);
        }
        if (node.access_has_popup) |popup| {
            const popup_value = switch (popup) {
                .menu => dvui.AccessKit.HasPopup.menu,
                .listbox => dvui.AccessKit.HasPopup.listbox,
                .tree => dvui.AccessKit.HasPopup.tree,
                .grid => dvui.AccessKit.HasPopup.grid,
                .dialog => dvui.AccessKit.HasPopup.dialog,
            };
            dvui.AccessKit.nodeSetHasPopup(ak_node, popup_value);
        } else {
            dvui.AccessKit.nodeClearHasPopup(ak_node);
        }
        const modal_flag: ?bool = if (node.access_modal) |flag| flag else if (node.modal) true else null;
        if (modal_flag) |flag| {
            dvui.AccessKit.nodeSetModal(ak_node, flag);
        } else {
            dvui.AccessKit.nodeClearModal(ak_node);
        }
    }
}
