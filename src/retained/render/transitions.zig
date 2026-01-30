const std = @import("std");
const dvui = @import("dvui");

const types = @import("../core/types.zig");
const tailwind = @import("../style/tailwind.zig");

const key_layout_tx = "_tw_layout_tx";
const key_layout_ty = "_tw_layout_ty";
const key_layout_sx = "_tw_layout_sx";
const key_layout_sy = "_tw_layout_sy";

const key_margin_l = "_tw_margin_l";
const key_margin_r = "_tw_margin_r";
const key_margin_t = "_tw_margin_t";
const key_margin_b = "_tw_margin_b";

const key_padding_l = "_tw_padding_l";
const key_padding_r = "_tw_padding_r";
const key_padding_t = "_tw_padding_t";
const key_padding_b = "_tw_padding_b";

const key_trans_x = "_tw_trans_x";
const key_trans_y = "_tw_trans_y";
const key_scale_x = "_tw_scale_x";
const key_scale_y = "_tw_scale_y";
const key_rot = "_tw_rot";

const key_opacity = "_tw_opacity";
const key_image_opacity = "_tw_img_opacity";

const key_bg_t = "_tw_bg_t";
const key_text_t = "_tw_text_t";
const key_tint_t = "_tw_tint_t";

fn nodeIdExtra(id: u32) usize {
    var hasher = std.hash.Wyhash.init(0);
    hasher.update(std.mem.asBytes(&id));
    return @intCast(hasher.final());
}

fn nodeAnimId(node_id: u32) dvui.Id {
    return dvui.Id.extendId(null, @src(), nodeIdExtra(node_id));
}

fn sideValue(value: ?f32) f32 {
    return value orelse 0;
}

fn layoutScale(node: *const types.SolidNode) f32 {
    if (node.layout.layout_scale != 0) return node.layout.layout_scale;
    return dvui.windowNaturalScale();
}

fn scaledMargin(spec: *const tailwind.Spec, scale: f32) types.SideOffsets {
    return .{
        .left = sideValue(spec.margin.left) * scale,
        .right = sideValue(spec.margin.right) * scale,
        .top = sideValue(spec.margin.top) * scale,
        .bottom = sideValue(spec.margin.bottom) * scale,
    };
}

fn scaledPadding(spec: *const tailwind.Spec, scale: f32) types.SideOffsets {
    return .{
        .left = sideValue(spec.padding.left) * scale,
        .right = sideValue(spec.padding.right) * scale,
        .top = sideValue(spec.padding.top) * scale,
        .bottom = sideValue(spec.padding.bottom) * scale,
    };
}

fn clearOverrides(node: *types.SolidNode) void {
    node.transition_state.flip_translation = .{ 0, 0 };
    node.transition_state.flip_scale = .{ 1, 1 };
    node.transition_state.anim_translation = null;
    node.transition_state.anim_scale = null;
    node.transition_state.anim_rotation = null;
    node.transition_state.anim_opacity = null;
    node.transition_state.anim_image_opacity = null;
    node.transition_state.anim_bg = null;
    node.transition_state.anim_text = null;
    node.transition_state.anim_tint = null;
    node.transition_state.bg_from = null;
    node.transition_state.bg_to = null;
    node.transition_state.text_from = null;
    node.transition_state.text_to = null;
    node.transition_state.tint_from = null;
    node.transition_state.tint_to = null;
}

pub fn beginFrameForNode(node: *types.SolidNode, cfg: *const tailwind.TransitionConfig) void {
    node.transition_state.enabled = cfg.enabled;
    node.transition_state.active_props = if (cfg.enabled) cfg.props else .{};
    if (!cfg.enabled) {
        clearOverrides(node);
        return;
    }
    updateActiveFromAnimations(node);
}

pub fn updateNode(node: *types.SolidNode, class_spec: *const tailwind.Spec) void {
    const cfg = &class_spec.transition;
    beginFrameForNode(node, cfg);

    if (!cfg.enabled) {
        updatePrevTargets(node, class_spec);
        return;
    }

    if (!node.transition_state.prev_initialized) {
        updatePrevTargets(node, class_spec);
    }

    if (cfg.duration_us <= 0 or (!cfg.props.layout and !cfg.props.transform and !cfg.props.colors and !cfg.props.opacity)) {
        clearOverrides(node);
        updatePrevTargets(node, class_spec);
        return;
    }

    if (cfg.props.layout) {
        scheduleOrUpdateLayoutFlip(node, cfg);
        scheduleOrUpdateSpacingTweens(node, cfg, class_spec);
    }

    if (cfg.props.transform) {
        scheduleOrUpdateTransformTweens(node, cfg);
    }

    if (cfg.props.opacity or cfg.props.colors) {
        scheduleOrUpdateVisualTweens(node, cfg, node.visual);
    }

    updateActiveFromAnimations(node);
    if (hasAnyActiveAnimation(node, cfg)) {
        node.invalidatePaint();
    }
    if (hasAnyActiveSpacingAnimation(node, cfg)) {
        node.invalidateLayout();
    }

    updatePrevTargets(node, class_spec);
}

fn updatePrevTargets(node: *types.SolidNode, class_spec: *const tailwind.Spec) void {
    if (node.layout.rect) |rect| {
        node.transition_state.prev_layout_rect = rect;
    } else {
        node.transition_state.prev_layout_rect = null;
    }
    const scale = layoutScale(node);
    node.transition_state.prev_margin = scaledMargin(class_spec, scale);
    node.transition_state.prev_padding = scaledPadding(class_spec, scale);
    node.transition_state.prev_translation = node.transform.translation;
    node.transition_state.prev_scale = node.transform.scale;
    node.transition_state.prev_rotation = node.transform.rotation;
    node.transition_state.prev_opacity = node.visual.opacity;
    node.transition_state.prev_image_opacity = node.image_opacity;
    node.transition_state.prev_bg = node.visual.background;
    node.transition_state.prev_text = node.visual.text_color;
    node.transition_state.prev_tint = node.image_tint;
    node.transition_state.prev_initialized = true;
}

fn updateActiveFromAnimations(node: *types.SolidNode) void {
    const id = nodeAnimId(node.id);

    node.transition_state.flip_translation = .{ 0, 0 };
    node.transition_state.flip_scale = .{ 1, 1 };
    if (node.transition_state.active_props.layout) {
        if (dvui.animationGet(id, key_layout_tx)) |a| node.transition_state.flip_translation[0] = a.value();
        if (dvui.animationGet(id, key_layout_ty)) |a| node.transition_state.flip_translation[1] = a.value();
        if (dvui.animationGet(id, key_layout_sx)) |a| node.transition_state.flip_scale[0] = a.value();
        if (dvui.animationGet(id, key_layout_sy)) |a| node.transition_state.flip_scale[1] = a.value();
    }

    node.transition_state.anim_translation = null;
    node.transition_state.anim_scale = null;
    node.transition_state.anim_rotation = null;
    if (node.transition_state.active_props.transform) {
        if (dvui.animationGet(id, key_trans_x) != null or dvui.animationGet(id, key_trans_y) != null) {
            const x = if (dvui.animationGet(id, key_trans_x)) |a| a.value() else node.transition_state.prev_translation[0];
            const y = if (dvui.animationGet(id, key_trans_y)) |a| a.value() else node.transition_state.prev_translation[1];
            node.transition_state.anim_translation = .{ x, y };
        }
        if (dvui.animationGet(id, key_scale_x) != null or dvui.animationGet(id, key_scale_y) != null) {
            const x = if (dvui.animationGet(id, key_scale_x)) |a| a.value() else node.transition_state.prev_scale[0];
            const y = if (dvui.animationGet(id, key_scale_y)) |a| a.value() else node.transition_state.prev_scale[1];
            node.transition_state.anim_scale = .{ x, y };
        }
        if (dvui.animationGet(id, key_rot)) |a| {
            node.transition_state.anim_rotation = a.value();
        }
    }

    node.transition_state.anim_opacity = null;
    if (node.transition_state.active_props.opacity) {
        if (dvui.animationGet(id, key_opacity)) |a| {
            node.transition_state.anim_opacity = a.value();
        }
    }

    node.transition_state.anim_image_opacity = null;
    if (node.transition_state.active_props.opacity) {
        if (dvui.animationGet(id, key_image_opacity)) |a| {
            node.transition_state.anim_image_opacity = a.value();
        }
    }

    node.transition_state.anim_bg = null;
    node.transition_state.anim_text = null;
    node.transition_state.anim_tint = null;
    if (node.transition_state.active_props.colors) {
        if (dvui.animationGet(id, key_bg_t)) |a| {
            if (node.transition_state.bg_from) |from| {
                if (node.transition_state.bg_to) |to| {
                    node.transition_state.anim_bg = lerpPackedColor(from, to, a.value());
                }
            }
        }

        if (dvui.animationGet(id, key_text_t)) |a| {
            if (node.transition_state.text_from) |from| {
                if (node.transition_state.text_to) |to| {
                    node.transition_state.anim_text = lerpPackedColor(from, to, a.value());
                }
            }
        }

        if (dvui.animationGet(id, key_tint_t)) |a| {
            if (node.transition_state.tint_from) |from| {
                if (node.transition_state.tint_to) |to| {
                    node.transition_state.anim_tint = lerpPackedColor(from, to, a.value());
                }
            }
        }
    }
}

fn hasAnyActiveAnimation(node: *types.SolidNode, cfg: *const tailwind.TransitionConfig) bool {
    const id = nodeAnimId(node.id);
    if (cfg.props.layout) {
        if (dvui.animationGet(id, key_layout_tx) != null) return true;
        if (dvui.animationGet(id, key_layout_ty) != null) return true;
        if (dvui.animationGet(id, key_layout_sx) != null) return true;
        if (dvui.animationGet(id, key_layout_sy) != null) return true;
        if (dvui.animationGet(id, key_margin_l) != null) return true;
        if (dvui.animationGet(id, key_margin_r) != null) return true;
        if (dvui.animationGet(id, key_margin_t) != null) return true;
        if (dvui.animationGet(id, key_margin_b) != null) return true;
        if (dvui.animationGet(id, key_padding_l) != null) return true;
        if (dvui.animationGet(id, key_padding_r) != null) return true;
        if (dvui.animationGet(id, key_padding_t) != null) return true;
        if (dvui.animationGet(id, key_padding_b) != null) return true;
    }
    if (cfg.props.transform) {
        if (dvui.animationGet(id, key_trans_x) != null) return true;
        if (dvui.animationGet(id, key_trans_y) != null) return true;
        if (dvui.animationGet(id, key_scale_x) != null) return true;
        if (dvui.animationGet(id, key_scale_y) != null) return true;
        if (dvui.animationGet(id, key_rot) != null) return true;
    }
    if (cfg.props.opacity) {
        if (dvui.animationGet(id, key_opacity) != null) return true;
        if (dvui.animationGet(id, key_image_opacity) != null) return true;
    }
    if (cfg.props.colors) {
        if (dvui.animationGet(id, key_bg_t) != null) return true;
        if (dvui.animationGet(id, key_text_t) != null) return true;
        if (dvui.animationGet(id, key_tint_t) != null) return true;
    }
    return false;
}

fn hasAnyActiveSpacingAnimation(node: *types.SolidNode, cfg: *const tailwind.TransitionConfig) bool {
    if (!cfg.props.layout) return false;
    const id = nodeAnimId(node.id);
    if (dvui.animationGet(id, key_margin_l) != null) return true;
    if (dvui.animationGet(id, key_margin_r) != null) return true;
    if (dvui.animationGet(id, key_margin_t) != null) return true;
    if (dvui.animationGet(id, key_margin_b) != null) return true;
    if (dvui.animationGet(id, key_padding_l) != null) return true;
    if (dvui.animationGet(id, key_padding_r) != null) return true;
    if (dvui.animationGet(id, key_padding_t) != null) return true;
    if (dvui.animationGet(id, key_padding_b) != null) return true;
    return false;
}

fn scheduleAnimation(id: dvui.Id, key: []const u8, start: f32, end: f32, cfg: *const tailwind.TransitionConfig) void {
    dvui.animation(id, key, .{
        .start_val = start,
        .end_val = end,
        .end_time = cfg.duration_us,
        .easing = cfg.easingFn(),
    });
}

fn scheduleOrUpdateLayoutFlip(node: *types.SolidNode, cfg: *const tailwind.TransitionConfig) void {
    const rect = node.layout.rect orelse return;
    const prev = node.transition_state.prev_layout_rect orelse return;

    if (rect.x == prev.x and rect.y == prev.y and rect.w == prev.w and rect.h == prev.h) return;

    const dx = prev.x - rect.x;
    const dy = prev.y - rect.y;
    const sx = if (rect.w != 0) prev.w / rect.w else 1.0;
    const sy = if (rect.h != 0) prev.h / rect.h else 1.0;

    const id = nodeAnimId(node.id);
    scheduleAnimation(id, key_layout_tx, dx, 0, cfg);
    scheduleAnimation(id, key_layout_ty, dy, 0, cfg);
    scheduleAnimation(id, key_layout_sx, sx, 1, cfg);
    scheduleAnimation(id, key_layout_sy, sy, 1, cfg);
}

fn animValueOr(id: dvui.Id, key: []const u8, fallback: f32) f32 {
    if (dvui.animationGet(id, key)) |a| return a.value();
    return fallback;
}

fn scheduleOrUpdateSpacingTweens(node: *types.SolidNode, cfg: *const tailwind.TransitionConfig, class_spec: *const tailwind.Spec) void {
    const scale = layoutScale(node);
    const target_margin = scaledMargin(class_spec, scale);
    const target_padding = scaledPadding(class_spec, scale);
    const prev_margin = node.transition_state.prev_margin;
    const prev_padding = node.transition_state.prev_padding;
    const id = nodeAnimId(node.id);

    if (target_margin.left != prev_margin.left) {
        scheduleAnimation(id, key_margin_l, animValueOr(id, key_margin_l, prev_margin.left), target_margin.left, cfg);
    }
    if (target_margin.right != prev_margin.right) {
        scheduleAnimation(id, key_margin_r, animValueOr(id, key_margin_r, prev_margin.right), target_margin.right, cfg);
    }
    if (target_margin.top != prev_margin.top) {
        scheduleAnimation(id, key_margin_t, animValueOr(id, key_margin_t, prev_margin.top), target_margin.top, cfg);
    }
    if (target_margin.bottom != prev_margin.bottom) {
        scheduleAnimation(id, key_margin_b, animValueOr(id, key_margin_b, prev_margin.bottom), target_margin.bottom, cfg);
    }

    if (target_padding.left != prev_padding.left) {
        scheduleAnimation(id, key_padding_l, animValueOr(id, key_padding_l, prev_padding.left), target_padding.left, cfg);
    }
    if (target_padding.right != prev_padding.right) {
        scheduleAnimation(id, key_padding_r, animValueOr(id, key_padding_r, prev_padding.right), target_padding.right, cfg);
    }
    if (target_padding.top != prev_padding.top) {
        scheduleAnimation(id, key_padding_t, animValueOr(id, key_padding_t, prev_padding.top), target_padding.top, cfg);
    }
    if (target_padding.bottom != prev_padding.bottom) {
        scheduleAnimation(id, key_padding_b, animValueOr(id, key_padding_b, prev_padding.bottom), target_padding.bottom, cfg);
    }
}

fn currentTransformNoFlip(node: *const types.SolidNode) types.Transform {
    var t = node.transform;
    if (!node.transition_state.enabled) return t;
    if (node.transition_state.anim_translation) |v| t.translation = v;
    if (node.transition_state.anim_scale) |v| t.scale = v;
    if (node.transition_state.anim_rotation) |v| t.rotation = v;
    return t;
}

fn scheduleOrUpdateTransformTweens(node: *types.SolidNode, cfg: *const tailwind.TransitionConfig) void {
    const prev_translation = node.transition_state.prev_translation;
    const prev_scale = node.transition_state.prev_scale;
    const prev_rotation = node.transition_state.prev_rotation;

    const cur_translation = (node.transition_state.anim_translation orelse prev_translation);
    const cur_scale = (node.transition_state.anim_scale orelse prev_scale);
    const cur_rotation = node.transition_state.anim_rotation orelse prev_rotation;
    const id = nodeAnimId(node.id);

    if (node.transform.translation[0] != prev_translation[0]) {
        scheduleAnimation(id, key_trans_x, cur_translation[0], node.transform.translation[0], cfg);
    }
    if (node.transform.translation[1] != prev_translation[1]) {
        scheduleAnimation(id, key_trans_y, cur_translation[1], node.transform.translation[1], cfg);
    }
    if (node.transform.scale[0] != prev_scale[0]) {
        scheduleAnimation(id, key_scale_x, cur_scale[0], node.transform.scale[0], cfg);
    }
    if (node.transform.scale[1] != prev_scale[1]) {
        scheduleAnimation(id, key_scale_y, cur_scale[1], node.transform.scale[1], cfg);
    }
    if (node.transform.rotation != prev_rotation) {
        const wrapped_target = shortestAngleTarget(cur_rotation, node.transform.rotation);
        scheduleAnimation(id, key_rot, cur_rotation, wrapped_target, cfg);
    }
}

fn packedOrTransparent(color: ?types.PackedColor) types.PackedColor {
    return color orelse .{ .value = 0x00000000 };
}

fn packedEqual(a: ?types.PackedColor, b: ?types.PackedColor) bool {
    if (a) |av| {
        if (b) |bv| return av.value == bv.value;
        return false;
    }
    return b == null;
}

fn scheduleOrUpdateVisualTweens(node: *types.SolidNode, cfg: *const tailwind.TransitionConfig, target_visual: types.VisualProps) void {
    const id = nodeAnimId(node.id);

    if (cfg.props.opacity) {
        if (target_visual.opacity != node.transition_state.prev_opacity) {
            const start = node.transition_state.anim_opacity orelse node.transition_state.prev_opacity;
            scheduleAnimation(id, key_opacity, start, target_visual.opacity, cfg);
        }
        if (node.image_opacity != node.transition_state.prev_image_opacity) {
            const start = node.transition_state.anim_image_opacity orelse node.transition_state.prev_image_opacity;
            scheduleAnimation(id, key_image_opacity, start, node.image_opacity, cfg);
        }
    }

    if (cfg.props.colors) {
        const target_bg = packedOrTransparent(target_visual.background);
        const prev_bg = packedOrTransparent(node.transition_state.prev_bg);
        if (target_bg.value != prev_bg.value) {
            const from = node.transition_state.anim_bg orelse prev_bg;
            node.transition_state.bg_from = from;
            node.transition_state.bg_to = target_bg;
            scheduleAnimation(id, key_bg_t, 0, 1, cfg);
        }

        if (!packedEqual(target_visual.text_color, node.transition_state.prev_text) and target_visual.text_color != null and node.transition_state.prev_text != null) {
            const from = node.transition_state.anim_text orelse node.transition_state.prev_text.?;
            node.transition_state.text_from = from;
            node.transition_state.text_to = target_visual.text_color;
            scheduleAnimation(id, key_text_t, 0, 1, cfg);
        }

        if (!packedEqual(node.image_tint, node.transition_state.prev_tint) and node.image_tint != null and node.transition_state.prev_tint != null) {
            const from = node.transition_state.anim_tint orelse node.transition_state.prev_tint.?;
            node.transition_state.tint_from = from;
            node.transition_state.tint_to = node.image_tint;
            scheduleAnimation(id, key_tint_t, 0, 1, cfg);
        }
    }
}

pub fn effectiveTransform(node: *const types.SolidNode) types.Transform {
    var t = node.transform;
    if (!node.transition_state.enabled) return t;

    if (node.transition_state.active_props.transform) {
        if (node.transition_state.anim_translation) |v| t.translation = v;
        if (node.transition_state.anim_scale) |v| t.scale = v;
        if (node.transition_state.anim_rotation) |v| t.rotation = v;
    }

    if (node.transition_state.active_props.layout) {
        t.translation[0] += node.transition_state.flip_translation[0];
        t.translation[1] += node.transition_state.flip_translation[1];
        t.scale[0] *= node.transition_state.flip_scale[0];
        t.scale[1] *= node.transition_state.flip_scale[1];
    }
    return t;
}

pub fn effectiveMargin(node: *const types.SolidNode, base: types.SideOffsets) types.SideOffsets {
    if (!node.transition_state.enabled) return base;
    if (!node.transition_state.active_props.layout) return base;
    const id = nodeAnimId(node.id);
    var out = base;
    if (dvui.animationGet(id, key_margin_l)) |a| out.left = a.value();
    if (dvui.animationGet(id, key_margin_r)) |a| out.right = a.value();
    if (dvui.animationGet(id, key_margin_t)) |a| out.top = a.value();
    if (dvui.animationGet(id, key_margin_b)) |a| out.bottom = a.value();
    return out;
}

pub fn effectivePadding(node: *const types.SolidNode, base: types.SideOffsets) types.SideOffsets {
    if (!node.transition_state.enabled) return base;
    if (!node.transition_state.active_props.layout) return base;
    const id = nodeAnimId(node.id);
    var out = base;
    if (dvui.animationGet(id, key_padding_l)) |a| out.left = a.value();
    if (dvui.animationGet(id, key_padding_r)) |a| out.right = a.value();
    if (dvui.animationGet(id, key_padding_t)) |a| out.top = a.value();
    if (dvui.animationGet(id, key_padding_b)) |a| out.bottom = a.value();
    return out;
}

pub fn hasActiveSpacingAnimation(node: *const types.SolidNode) bool {
    if (!node.transition_state.enabled) return false;
    if (!node.transition_state.active_props.layout) return false;
    const id = nodeAnimId(node.id);
    if (dvui.animationGet(id, key_margin_l) != null) return true;
    if (dvui.animationGet(id, key_margin_r) != null) return true;
    if (dvui.animationGet(id, key_margin_t) != null) return true;
    if (dvui.animationGet(id, key_margin_b) != null) return true;
    if (dvui.animationGet(id, key_padding_l) != null) return true;
    if (dvui.animationGet(id, key_padding_r) != null) return true;
    if (dvui.animationGet(id, key_padding_t) != null) return true;
    if (dvui.animationGet(id, key_padding_b) != null) return true;
    return false;
}

pub fn effectiveVisual(node: *const types.SolidNode) types.VisualProps {
    var v = node.visual;
    if (!node.transition_state.enabled) return v;

    if (node.transition_state.active_props.colors) {
        if (node.transition_state.anim_bg) |bg| v.background = bg;
        if (node.transition_state.anim_text) |tc| v.text_color = tc;
    }
    if (node.transition_state.active_props.opacity) {
        if (node.transition_state.anim_opacity) |opacity| v.opacity = opacity;
    }
    return v;
}

pub fn effectiveImageOpacity(node: *const types.SolidNode) f32 {
    if (!node.transition_state.enabled) return node.image_opacity;
    if (!node.transition_state.active_props.opacity) return node.image_opacity;
    return node.transition_state.anim_image_opacity orelse node.image_opacity;
}

pub fn effectiveImageTint(node: *const types.SolidNode) ?types.PackedColor {
    if (!node.transition_state.enabled) return node.image_tint;
    if (!node.transition_state.active_props.colors) return node.image_tint;
    return node.transition_state.anim_tint orelse node.image_tint;
}

pub fn lerpPackedColor(a: types.PackedColor, b: types.PackedColor, t: f32) types.PackedColor {
    const tt = std.math.clamp(t, 0.0, 1.0);
    const ar: f32 = @floatFromInt((a.value >> 24) & 0xff);
    const ag: f32 = @floatFromInt((a.value >> 16) & 0xff);
    const ab: f32 = @floatFromInt((a.value >> 8) & 0xff);
    const aa: f32 = @floatFromInt(a.value & 0xff);

    const br: f32 = @floatFromInt((b.value >> 24) & 0xff);
    const bg: f32 = @floatFromInt((b.value >> 16) & 0xff);
    const bb: f32 = @floatFromInt((b.value >> 8) & 0xff);
    const ba: f32 = @floatFromInt(b.value & 0xff);

    const r: u8 = @intFromFloat(std.math.clamp(std.math.lerp(ar, br, tt), 0.0, 255.0));
    const g: u8 = @intFromFloat(std.math.clamp(std.math.lerp(ag, bg, tt), 0.0, 255.0));
    const bch: u8 = @intFromFloat(std.math.clamp(std.math.lerp(ab, bb, tt), 0.0, 255.0));
    const aout: u8 = @intFromFloat(std.math.clamp(std.math.lerp(aa, ba, tt), 0.0, 255.0));

    const packed_rgb: u32 = (@as(u32, r) << 24) | (@as(u32, g) << 16) | (@as(u32, bch) << 8) | @as(u32, aout);
    return .{ .value = packed_rgb };
}

pub fn shortestAngleTarget(from: f32, to: f32) f32 {
    const two_pi: f32 = 2.0 * std.math.pi;
    var delta = to - from;
    while (delta > std.math.pi) delta -= two_pi;
    while (delta < -std.math.pi) delta += two_pi;
    return from + delta;
}
