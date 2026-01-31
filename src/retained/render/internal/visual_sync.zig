const std = @import("std");
const dvui = @import("dvui");

const types = @import("../../core/types.zig");
const events = @import("../../events/mod.zig");
const style_apply = @import("../../style/apply.zig");
const tailwind = @import("../../style/tailwind.zig");
const direct = @import("../direct.zig");
const transitions = @import("../transitions.zig");
const state = @import("state.zig");

const applyVisualPropsToOptions = style_apply.applyVisualPropsToOptions;
const applyClassSpecToVisual = style_apply.applyClassSpecToVisual;
const dvuiColorToPacked = direct.dvuiColorToPacked;
const transformedRect = direct.transformedRect;
const rectContains = state.rectContains;
const intersectRect = state.intersectRect;
const ClipState = state.ClipState;
const isPortalNode = state.isPortalNode;

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

pub fn applyCursorHint(node: *const types.SolidNode, class_spec: *const tailwind.Spec) void {
    if (!state.allowPointerInput()) return;
    if (!node.hovered) return;
    const cursor = class_spec.cursor orelse return;
    dvui.cursorSet(cursor);
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

pub fn syncVisualsFromClasses(
    event_ring: ?*events.EventRing,
    store: *types.NodeStore,
    node: *types.SolidNode,
    clip: ClipState,
    mouse: dvui.Point.Physical,
    pointer_allowed: bool,
) void {
    const class_spec_base = node.prepareClassSpec();
    const has_hover = tailwind.hasHover(&class_spec_base);
    const hover_affects_layout = tailwind.hasHoverLayout(&class_spec_base);
    const has_mouseenter = node.hasListener("mouseenter");
    const has_mouseleave = node.hasListener("mouseleave");
    const prev_bg = node.visual.background;
    const prev_hovered = node.hovered;

    transitions.beginFrameForNode(node, &class_spec_base.transition);

    var rect_opt: ?types.Rect = null;
    if (node.layout.rect) |rect_base| {
        rect_opt = transformedRect(node, rect_base) orelse rect_base;
    }

    const wants_hover = has_hover or has_mouseenter or has_mouseleave or class_spec_base.cursor != null;
    var hovered = false;
    if (pointer_allowed and wants_hover and !class_spec_base.hidden and node.kind == .element) {
        if (rect_opt) |rect| {
            if (rectContains(rect, mouse)) {
                if (!clip.active or rectContains(clip.rect, mouse)) {
                    hovered = true;
                }
            }
        }
    }

    node.hovered = hovered;

    if (class_spec_base.hidden) {
        if (state.input_enabled_state) {
            if (event_ring) |ring| {
                if (prev_hovered and has_mouseleave) {
                    _ = ring.push(.mouseleave, node.id, null);
                }
            }
        }
        if (prev_hovered and has_hover) {
            node.invalidatePaint();
        }
        return;
    }

    if (state.input_enabled_state) {
        if (event_ring) |ring| {
            if (prev_hovered != hovered) {
                if (hovered and has_mouseenter) {
                    _ = ring.push(.mouseenter, node.id, null);
                } else if (!hovered and has_mouseleave) {
                    _ = ring.push(.mouseleave, node.id, null);
                }
            }
        }
    }

    if (prev_hovered != hovered and hover_affects_layout) {
        node.invalidateLayout();
        store.markNodeChanged(node.id);
        state.hover_layout_invalidated = true;
    }

    node.visual = node.visual_props;
    var class_spec = class_spec_base;
    tailwind.applyHover(&class_spec, hovered);

    applyClassSpecToVisual(node, &class_spec);
    if (node.scroll.enabled) {
        node.visual.clip_children = true;
    }
    if (node.visual.background == null) {
        if (class_spec.background) |bg| {
            node.visual.background = dvuiColorToPacked(bg);
        } else {
            node.visual.background = .{ .value = 0x00000000 };
        }
    }
    transitions.updateNode(node, &class_spec);
    const bg_changed = blk: {
        if (node.visual.background) |bg| {
            if (prev_bg) |prev| break :blk bg.value != prev.value;
            break :blk true;
        } else {
            break :blk prev_bg != null;
        }
    };
    if (bg_changed or (prev_hovered != hovered and has_hover)) {
        node.invalidatePaint();
    }

    var next_clip = clip;
    if (node.visual.clip_children) {
        const rect_for_clip = blk: {
            if (node.layout.rect) |rect_base| {
                break :blk transformedRect(node, rect_base) orelse rect_base;
            }
            break :blk rect_opt;
        };
        if (rect_for_clip) |rect| {
            next_clip.active = true;
            next_clip.rect = if (clip.active) intersectRect(clip.rect, rect) else rect;
        }
    }

    for (node.children.items) |child_id| {
        if (store.node(child_id)) |child| {
            if (state.render_layer == .base and isPortalNode(child)) continue;
            syncVisualsFromClasses(event_ring, store, child, next_clip, mouse, pointer_allowed);
        }
    }
}
