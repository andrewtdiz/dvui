const std = @import("std");
const dvui = @import("../../dvui.zig");

const Rect = dvui.Rect;
const RectScale = dvui.RectScale;
const Point = dvui.Point;

pub const SelectionDragPart = enum {
    move,
    resize_top_left,
    resize_top,
    resize_top_right,
    resize_right,
    resize_bottom_right,
    resize_bottom,
    resize_bottom_left,
    resize_left,
    rotate,

    pub fn cursor(self: SelectionDragPart) dvui.enums.Cursor {
        return switch (self) {
            .move => .arrow_all,
            .resize_top_left, .resize_bottom_right => .arrow_nw_se,
            .resize_top_right, .resize_bottom_left => .arrow_ne_sw,
            .resize_top, .resize_bottom => .arrow_n_s,
            .resize_left, .resize_right => .arrow_w_e,
            .rotate => .arrow_all,
        };
    }
};

pub const selection_handle_visual: f32 = 10;
pub const selection_edge_handle_thickness: f32 = 16;
pub const selection_outer_handle_visual_offset: f32 = 18;
pub const selection_outer_alpha: u8 = 100;

pub const corner_parts = [_]SelectionDragPart{
    .resize_top_left,
    .resize_top_right,
    .resize_bottom_right,
    .resize_bottom_left,
};

pub const edge_parts = [_]SelectionDragPart{
    .resize_top,
    .resize_right,
    .resize_bottom,
    .resize_left,
};

pub const DragTransform = struct {
    rect: Rect,
    rs: RectScale,
    rotation: f32,
};

pub fn resizeRect(part: SelectionDragPart, anchor_nat: Point, origin: Rect, min_size: dvui.Size) Rect {
    var rect = origin;
    const min_w = min_size.w;
    const min_h = min_size.h;
    const origin_right = origin.x + origin.w;
    const origin_bottom = origin.y + origin.h;

    switch (part) {
        .resize_top_left => {
            var left = anchor_nat.x;
            var top = anchor_nat.y;
            if (origin_right - left < min_w) left = origin_right - min_w;
            if (origin_bottom - top < min_h) top = origin_bottom - min_h;
            rect.x = left;
            rect.y = top;
            rect.w = origin_right - left;
            rect.h = origin_bottom - top;
        },
        .resize_top => {
            var top = anchor_nat.y;
            if (origin_bottom - top < min_h) top = origin_bottom - min_h;
            rect.x = origin.x;
            rect.y = top;
            rect.w = origin.w;
            rect.h = origin_bottom - top;
        },
        .resize_top_right => {
            var right = anchor_nat.x;
            var top = anchor_nat.y;
            if (right - origin.x < min_w) right = origin.x + min_w;
            if (origin_bottom - top < min_h) top = origin_bottom - min_h;
            rect.x = origin.x;
            rect.y = top;
            rect.w = right - origin.x;
            rect.h = origin_bottom - top;
        },
        .resize_right => {
            var right = anchor_nat.x;
            if (right - origin.x < min_w) right = origin.x + min_w;
            rect.x = origin.x;
            rect.y = origin.y;
            rect.w = right - origin.x;
            rect.h = origin.h;
        },
        .resize_bottom_right => {
            var right = anchor_nat.x;
            var bottom = anchor_nat.y;
            if (right - origin.x < min_w) right = origin.x + min_w;
            if (bottom - origin.y < min_h) bottom = origin.y + min_h;
            rect.x = origin.x;
            rect.y = origin.y;
            rect.w = right - origin.x;
            rect.h = bottom - origin.y;
        },
        .resize_bottom => {
            var bottom = anchor_nat.y;
            if (bottom - origin.y < min_h) bottom = origin.y + min_h;
            rect.x = origin.x;
            rect.y = origin.y;
            rect.w = origin.w;
            rect.h = bottom - origin.y;
        },
        .resize_bottom_left => {
            var left = anchor_nat.x;
            var bottom = anchor_nat.y;
            if (origin_right - left < min_w) left = origin_right - min_w;
            if (bottom - origin.y < min_h) bottom = origin.y + min_h;
            rect.x = left;
            rect.y = origin.y;
            rect.w = origin_right - left;
            rect.h = bottom - origin.y;
        },
        .resize_left => {
            var left = anchor_nat.x;
            if (origin_right - left < min_w) left = origin_right - min_w;
            rect.x = left;
            rect.y = origin.y;
            rect.w = origin_right - left;
            rect.h = origin.h;
        },
        else => {},
    }

    return rect;
}

pub fn resizeRectCentered(part: SelectionDragPart, anchor_nat: Point, origin: Rect, min_size: dvui.Size) Rect {
    const center = origin.center();
    var half_w = origin.w * 0.5;
    var half_h = origin.h * 0.5;

    if (partAffectsHorizontal(part)) {
        const delta = @abs(anchor_nat.x - center.x);
        half_w = @max(min_size.w * 0.5, delta);
    }

    if (partAffectsVertical(part)) {
        const delta = @abs(anchor_nat.y - center.y);
        half_h = @max(min_size.h * 0.5, delta);
    }

    return Rect{
        .x = center.x - half_w,
        .y = center.y - half_h,
        .w = half_w * 2,
        .h = half_h * 2,
    };
}

pub fn applyProportionalScaling(
    rect: Rect,
    origin: Rect,
    aspect_ratio: f32,
    part: SelectionDragPart,
    min_size: dvui.Size,
    anchor_nat: Point,
    centered: bool,
) Rect {
    if (!partAffectsHorizontal(part) or !partAffectsVertical(part)) return rect;
    if (aspect_ratio == 0) return rect;

    const pivot = if (centered)
        origin.center()
    else
        selectionAnchorNatural(origin, selectionOppositePart(part));

    const offset_x = anchor_nat.x - pivot.x;
    const offset_y = anchor_nat.y - pivot.y;
    const abs_offset_x = @abs(offset_x);
    const abs_offset_y = @abs(offset_y);

    const normalized_vertical = abs_offset_y * aspect_ratio;
    const horizontal_dominant = normalized_vertical <= abs_offset_x;

    var width: f32 = rect.w;
    var height: f32 = rect.h;

    if (horizontal_dominant) {
        width = if (centered) abs_offset_x * 2 else abs_offset_x;
        width = @max(width, min_size.w);
        height = width / aspect_ratio;
    } else {
        height = if (centered) abs_offset_y * 2 else abs_offset_y;
        height = @max(height, min_size.h);
        width = height * aspect_ratio;
    }

    width = @max(width, min_size.w);
    height = @max(height, min_size.h);

    return rectFromPivot(pivot, width, height, part, centered);
}

pub fn snapRectToIncrement(rect: Rect, part: SelectionDragPart, min_size: dvui.Size, increment: f32) Rect {
    if (increment <= 0) return rect;
    var result = rect;
    if (partAffectsHorizontal(part)) {
        result.w = snapDimension(rect.w, increment);
    }
    if (partAffectsVertical(part)) {
        result.h = snapDimension(rect.h, increment);
    }
    result.w = @max(result.w, min_size.w);
    result.h = @max(result.h, min_size.h);
    return result;
}

pub fn snapDimension(value: f32, increment: f32) f32 {
    if (increment <= 0) return value;
    const snapped = @round(value / increment) * increment;
    return snapped;
}

pub fn enforceMinSize(rect: Rect, min_size: dvui.Size) Rect {
    var result = rect;
    if (result.w < min_size.w) result.w = min_size.w;
    if (result.h < min_size.h) result.h = min_size.h;
    return result;
}

pub fn partAffectsHorizontal(part: SelectionDragPart) bool {
    return switch (part) {
        .resize_top_left,
        .resize_top_right,
        .resize_bottom_right,
        .resize_bottom_left,
        .resize_left,
        .resize_right => true,
        else => false,
    };
}

pub fn partAffectsVertical(part: SelectionDragPart) bool {
    return switch (part) {
        .resize_top_left,
        .resize_top_right,
        .resize_bottom_right,
        .resize_bottom_left,
        .resize_top,
        .resize_bottom => true,
        else => false,
    };
}

pub fn rectAspectRatio(rect: Rect) f32 {
    if (rect.h == 0) return 1.0;
    return rect.w / rect.h;
}

pub fn selectionAnchorNatural(rect: Rect, part: SelectionDragPart) Point {
    return switch (part) {
        .move, .resize_top_left => rect.topLeft(),
        .resize_top => Point{ .x = rect.x + rect.w * 0.5, .y = rect.y },
        .resize_top_right => rect.topRight(),
        .resize_right => Point{ .x = rect.x + rect.w, .y = rect.y + rect.h * 0.5 },
        .resize_bottom_right => rect.bottomRight(),
        .resize_bottom => Point{ .x = rect.x + rect.w * 0.5, .y = rect.y + rect.h },
        .resize_bottom_left => rect.bottomLeft(),
        .resize_left => Point{ .x = rect.x, .y = rect.y + rect.h * 0.5 },
        .rotate => Point{ .x = rect.x + rect.w * 0.5, .y = rect.y },
    };
}

pub fn isResizePart(part: SelectionDragPart) bool {
    return switch (part) {
        .resize_top_left,
        .resize_top,
        .resize_top_right,
        .resize_right,
        .resize_bottom_right,
        .resize_bottom,
        .resize_bottom_left,
        .resize_left => true,
        else => false,
    };
}

pub fn selectionAnchorPhysical(rs: RectScale, part: SelectionDragPart) Point.Physical {
    const rect = rs.r;
    return switch (part) {
        .move, .resize_top_left => rect.topLeft(),
        .resize_top => Point.Physical{ .x = rect.x + rect.w * 0.5, .y = rect.y },
        .resize_top_right => rect.topRight(),
        .resize_right => Point.Physical{ .x = rect.x + rect.w, .y = rect.y + rect.h * 0.5 },
        .resize_bottom_right => rect.bottomRight(),
        .resize_bottom => Point.Physical{ .x = rect.x + rect.w * 0.5, .y = rect.y + rect.h },
        .resize_bottom_left => rect.bottomLeft(),
        .resize_left => Point.Physical{ .x = rect.x, .y = rect.y + rect.h * 0.5 },
        .rotate => Point.Physical{ .x = rect.x + rect.w * 0.5, .y = rect.y },
    };
}

pub fn selectionAnchorRelative(rect: Rect, part: SelectionDragPart) Point {
    const anchor = selectionAnchorNatural(rect, part);
    return Point{
        .x = anchor.x - rect.x,
        .y = anchor.y - rect.y,
    };
}

pub fn selectionOppositePart(part: SelectionDragPart) SelectionDragPart {
    return switch (part) {
        .resize_top_left => .resize_bottom_right,
        .resize_top => .resize_bottom,
        .resize_top_right => .resize_bottom_left,
        .resize_right => .resize_left,
        .resize_bottom_right => .resize_top_left,
        .resize_bottom => .resize_top,
        .resize_bottom_left => .resize_top_right,
        .resize_left => .resize_right,
        else => part,
    };
}

pub fn rotatedSelectionAnchor(rect: Rect, part: SelectionDragPart, rotation: f32) Point {
    const anchor = selectionAnchorNatural(rect, part);
    return rotatePointAroundNatural(anchor, rect.center(), rotation);
}

pub fn rotateVector(v: Point, radians: f32) Point {
    if (radians == 0) return v;
    const cosv = @cos(radians);
    const sinv = @sin(radians);
    return .{
        .x = v.x * cosv - v.y * sinv,
        .y = v.x * sinv + v.y * cosv,
    };
}

pub fn repositionRectToPivot(rect: Rect, pivot_world: Point, pivot_part: ?SelectionDragPart, pivot_is_center: bool, rotation: f32) Rect {
    if (pivot_is_center) {
        return Rect{
            .x = pivot_world.x - rect.w * 0.5,
            .y = pivot_world.y - rect.h * 0.5,
            .w = rect.w,
            .h = rect.h,
        };
    }

    const part = pivot_part orelse return rect;
    const center_offset = Point{ .x = rect.w * 0.5, .y = rect.h * 0.5 };
    const pivot_rel = selectionAnchorRelative(rect, part);
    const rel_from_center = Point{
        .x = pivot_rel.x - center_offset.x,
        .y = pivot_rel.y - center_offset.y,
    };
    const rotated_rel = rotateVector(rel_from_center, rotation);
    return Rect{
        .x = pivot_world.x - center_offset.x - rotated_rel.x,
        .y = pivot_world.y - center_offset.y - rotated_rel.y,
        .w = rect.w,
        .h = rect.h,
    };
}

fn rectFromPivot(pivot: Point, width: f32, height: f32, part: SelectionDragPart, centered: bool) Rect {
    if (centered) {
        return Rect{
            .x = pivot.x - width * 0.5,
            .y = pivot.y - height * 0.5,
            .w = width,
            .h = height,
        };
    }

    return switch (part) {
        .resize_top_left => Rect{
            .x = pivot.x - width,
            .y = pivot.y - height,
            .w = width,
            .h = height,
        },
        .resize_top_right => Rect{
            .x = pivot.x,
            .y = pivot.y - height,
            .w = width,
            .h = height,
        },
        .resize_bottom_right => Rect{
            .x = pivot.x,
            .y = pivot.y,
            .w = width,
            .h = height,
        },
        .resize_bottom_left => Rect{
            .x = pivot.x - width,
            .y = pivot.y,
            .w = width,
            .h = height,
        },
        else => Rect{
            .x = pivot.x - width,
            .y = pivot.y - height,
            .w = width,
            .h = height,
        },
    };
}

pub fn selectionHandleRect(rect: Rect, part: SelectionDragPart) Rect {
    const corner_size = selection_handle_visual;
    const corner_half = corner_size * 0.5;
    const edge_size = selection_edge_handle_thickness;
    const edge_half = edge_size * 0.5;
    const horizontal_len = @max(@as(f32, 0), rect.w - corner_size);
    const vertical_len = @max(@as(f32, 0), rect.h - corner_size);
    return switch (part) {
        .resize_top_left => Rect{
            .x = rect.x - corner_half,
            .y = rect.y - corner_half,
            .w = corner_size,
            .h = corner_size,
        },
        .resize_top => Rect{
            .x = rect.x + corner_half,
            .y = rect.y - edge_half,
            .w = horizontal_len,
            .h = edge_size,
        },
        .resize_top_right => Rect{
            .x = rect.x + rect.w - corner_half,
            .y = rect.y - corner_half,
            .w = corner_size,
            .h = corner_size,
        },
        .resize_right => Rect{
            .x = rect.x + rect.w - edge_half,
            .y = rect.y + corner_half,
            .w = edge_size,
            .h = vertical_len,
        },
        .resize_bottom_right => Rect{
            .x = rect.x + rect.w - corner_half,
            .y = rect.y + rect.h - corner_half,
            .w = corner_size,
            .h = corner_size,
        },
        .resize_bottom => Rect{
            .x = rect.x + corner_half,
            .y = rect.y + rect.h - edge_half,
            .w = horizontal_len,
            .h = edge_size,
        },
        .resize_bottom_left => Rect{
            .x = rect.x - corner_half,
            .y = rect.y + rect.h - corner_half,
            .w = corner_size,
            .h = corner_size,
        },
        .resize_left => Rect{
            .x = rect.x - edge_half,
            .y = rect.y + corner_half,
            .w = edge_size,
            .h = vertical_len,
        },
        else => Rect{},
    };
}

pub fn selectionOuterHandleRect(rect: Rect, part: SelectionDragPart) Rect {
    const corner_size = selection_handle_visual;
    const outer_size = corner_size + (selection_outer_handle_visual_offset * 2);
    const outer_half = outer_size * 0.5;
    return switch (part) {
        .resize_top_left => Rect{
            .x = rect.x - outer_half,
            .y = rect.y - outer_half,
            .w = outer_size,
            .h = outer_size,
        },
        .resize_top_right => Rect{
            .x = rect.x + rect.w - outer_half,
            .y = rect.y - outer_half,
            .w = outer_size,
            .h = outer_size,
        },
        .resize_bottom_right => Rect{
            .x = rect.x + rect.w - outer_half,
            .y = rect.y + rect.h - outer_half,
            .w = outer_size,
            .h = outer_size,
        },
        .resize_bottom_left => Rect{
            .x = rect.x - outer_half,
            .y = rect.y + rect.h - outer_half,
            .w = outer_size,
            .h = outer_size,
        },
        else => Rect{},
    };
}

pub fn rotatePointAround(point: Point.Physical, origin: Point.Physical, radians: f32) Point.Physical {
    if (radians == 0) return point;
    const cosv = @cos(radians);
    const sinv = @sin(radians);
    const dx = point.x - origin.x;
    const dy = point.y - origin.y;
    return .{
        .x = origin.x + dx * cosv - dy * sinv,
        .y = origin.y + dx * sinv + dy * cosv,
    };
}

pub fn rotatePointAroundNatural(point: Point, origin: Point, radians: f32) Point {
    if (radians == 0) return point;
    const cosv = @cos(radians);
    const sinv = @sin(radians);
    const dx = point.x - origin.x;
    const dy = point.y - origin.y;
    return .{
        .x = origin.x + dx * cosv - dy * sinv,
        .y = origin.y + dx * sinv + dy * cosv,
    };
}

pub fn rotatedInteractionRect(rect: Rect.Physical, rotation: f32, padding: f32) Rect.Physical {
    const rotation_origin = rect.center();
    var min_x: f32 = std.math.floatMax(f32);
    var min_y: f32 = std.math.floatMax(f32);
    var max_x: f32 = -std.math.floatMax(f32);
    var max_y: f32 = -std.math.floatMax(f32);
    const corners = [_]Point.Physical{
        rect.topLeft(),
        rect.topRight(),
        rect.bottomRight(),
        rect.bottomLeft(),
    };
    for (corners) |corner| {
        const rotated = rotatePointAround(corner, rotation_origin, rotation);
        min_x = @min(min_x, rotated.x);
        min_y = @min(min_y, rotated.y);
        max_x = @max(max_x, rotated.x);
        max_y = @max(max_y, rotated.y);
    }
    return Rect.Physical{
        .x = min_x - padding,
        .y = min_y - padding,
        .w = (max_x - min_x) + padding * 2,
        .h = (max_y - min_y) + padding * 2,
    };
}

pub fn rectNaturalToPhysical(widget_rect: Rect, rect_nat: Rect, rs: RectScale) Rect.Physical {
    const widget_origin = widget_rect.topLeft();
    const local_rect = rect_nat.offsetNegPoint(widget_origin);
    return rs.rectToPhysical(local_rect);
}

pub fn pointToSelectionSpace(rect: Rect, rotation: f32, rs: RectScale, p: Point.Physical) Point {
    const rotation_origin_phys = rs.r.center();
    const unrotated_phys = rotatePointAround(p, rotation_origin_phys, -rotation);
    const local_nat = rs.pointFromPhysical(unrotated_phys);
    return local_nat.plus(rect.topLeft());
}

pub fn pointToSelectionSpaceWithTransform(transform: DragTransform, p: Point.Physical) Point {
    const rotation_origin_phys = transform.rs.r.center();
    const unrotated_phys = rotatePointAround(p, rotation_origin_phys, -transform.rotation);
    const local_nat = transform.rs.pointFromPhysical(unrotated_phys);
    return local_nat.plus(transform.rect.topLeft());
}

pub fn angleFromCenterPhysical(center: Point.Physical, p: Point.Physical) f32 {
    return std.math.atan2(p.y - center.y, p.x - center.x);
}

pub fn normalizeAngle(angle: f32) f32 {
    const pi = std.math.pi;
    const tau = std.math.tau;
    var value = angle;
    while (value > pi) : (value -= tau) {}
    while (value < -pi) : (value += tau) {}
    return value;
}

pub fn snapAngleVertical(angle: f32, increment: f32) f32 {
    if (increment <= 0) return angle;
    const vertical_offset = std.math.pi / 2.0;
    const relative = angle - vertical_offset;
    const snapped_relative = @round(relative / increment) * increment;
    return normalizeAngle(snapped_relative + vertical_offset);
}

pub fn partName(part: ?SelectionDragPart) []const u8 {
    return if (part) |p| @tagName(p) else "none";
}

test {
    @import("std").testing.refAllDecls(@This());
}
