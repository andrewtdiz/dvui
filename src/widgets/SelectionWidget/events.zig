const std = @import("std");
const dvui = @import("../../dvui.zig");
const transform = @import("transform.zig");

const Event = dvui.Event;
const Point = dvui.Point;
const RectScale = dvui.RectScale;
const WidgetData = dvui.WidgetData;

const SelectionDragPart = transform.SelectionDragPart;

pub fn process(self: anytype) void {
    self.syncWidgetRect();
    self.selection_activation_event = null;
    updateSelectionToggle(self);

    const runtime = self.runtime;
    const debug_info = &runtime.debug_info;
    const wd = self.data();
    const rs = wd.borderRectScale();
    const handle_half = transform.selection_handle_visual * rs.s * 0.5;
    const rotate_half = (transform.selection_handle_visual * 0.5 + transform.selection_outer_handle_visual_offset) * rs.s;
    const interaction_padding = if (self.init_opts.can_rotate) rotate_half else handle_half;
    const interaction_rect = transform.rotatedInteractionRect(rs.r, self.state.rotation, interaction_padding);
    const modifiers = self.init_opts.transform_modifiers;
    updateActiveResizePivot(self, modifiers.centered);
    debug_info.interaction_rect = interaction_rect;
    debug_info.last_rect = self.state.rect;
    debug_info.selected = self.state.selected;
    debug_info.hover_state = self.state.hovered;
    debug_info.drag_part = runtime.drag_part;

    for (dvui.events()) |*e| {
        const event_matches = dvui.eventMatch(e, .{ .id = wd.id, .r = interaction_rect });

        switch (e.evt) {
            .mouse => |me| {
                const has_capture = dvui.captured(wd.id);
                if (!has_capture and !event_matches) continue;
                runtime.pointer_current_phys = me.p;

                const updates_hover = switch (me.action) {
                    .motion, .position, .press, .release => true,
                    else => false,
                };

                var hovered_part = runtime.hover_part;
                if (updates_hover) {
                    hovered_part = hitTest(self, rs, me.p);
                    setHoverPart(self, hovered_part);
                }

                if (has_capture) {
                    if (runtime.drag_part) |part| {
                        switch (me.action) {
                            .motion, .position => {
                                const anchor_phys = me.p.plus(runtime.drag_offset);
                                const anchor_nat = self.pointToSelectionSpaceDuringDrag(anchor_phys);
                                applyDrag(self, part, anchor_nat, wd, e);
                                requestCursor(part);
                            },
                            .release => {
                                if (me.button.pointer()) {
                                    e.handle(@src(), wd);
                                    dvui.captureMouse(null, e.num);
                                    throttledDebugPrint("SelectionWidget capture released #{d}\n", .{e.num});
                                    runtime.drag_part = null;
                                    runtime.drag_offset = .{};
                                    runtime.drag_transform = null;
                                    runtime.resize_pivot_part = null;
                                    runtime.resize_pivot_world_handle = .{};
                                    runtime.resize_pivot_world_center = .{};
                                    runtime.resize_pivot_is_center = false;
                                    debug_info.drag_part = null;
                                    debug_info.drag_offset = .{};
                                }
                            },
                            else => {},
                        }
                    }
                    continue;
                }

                if (hovered_part) |_| switch (me.action) {
                    .motion, .position => {
                        e.handle(@src(), wd);
                        continue;
                    },
                    else => {},
                };

                if (!self.state.selected) continue;

                switch (me.action) {
                    .press => {
                        if (!me.button.pointer()) break;
                        if (self.selection_activation_event) |event_num| {
                            if (event_num == e.num) {
                                self.selection_activation_event = null;
                            }
                        }
                        if (hovered_part) |part| {
                            e.handle(@src(), wd);
                            dvui.captureMouse(wd, e.num);
                            throttledDebugPrint("SelectionWidget capture start #{d} part={s} pointer={any}\n", .{
                                e.num,
                                transform.partName(part),
                                me.p,
                            });
                            runtime.drag_transform = .{ .rect = self.state.rect, .rs = rs, .rotation = self.state.rotation };
                            runtime.drag_part = part;
                            runtime.drag_origin_rect = self.state.rect;
                            runtime.drag_pointer_origin_phys = me.p;
                            runtime.pointer_current_phys = me.p;
                            const pointer_nat = transform.pointToSelectionSpaceWithTransform(runtime.drag_transform.?, me.p);
                            switch (part) {
                                .move => {
                                    runtime.drag_origin_anchor = pointer_nat;
                                    runtime.drag_pointer_origin = pointer_nat;
                                    runtime.drag_offset = .{};
                                    runtime.resize_pivot_part = null;
                                    runtime.resize_pivot_is_center = false;
                                },
                                .rotate => {
                                    runtime.drag_origin_anchor = pointer_nat;
                                    runtime.drag_pointer_origin = pointer_nat;
                                    runtime.drag_offset = .{};
                                    runtime.drag_origin_rotation = self.state.rotation;
                                    runtime.rotation_center_phys = rs.r.center();
                                    runtime.drag_origin_angle = transform.angleFromCenterPhysical(runtime.rotation_center_phys, me.p);
                                    runtime.resize_pivot_part = null;
                                    runtime.resize_pivot_is_center = false;
                                },
                                else => {
                                    runtime.drag_origin_anchor = transform.selectionAnchorNatural(runtime.drag_origin_rect, part);
                                    const anchor_base = transform.selectionAnchorPhysical(rs, part);
                                    const rotation_origin = rs.r.center();
                                    const anchor_phys = transform.rotatePointAround(anchor_base, rotation_origin, self.state.rotation);
                                    runtime.drag_offset = Point.Physical.diff(anchor_phys, me.p);
                                    runtime.drag_pointer_origin = pointer_nat;
                                    const pivot_part = transform.selectionOppositePart(part);
                                    runtime.resize_pivot_part = pivot_part;
                                    runtime.resize_pivot_world_handle = transform.rotatedSelectionAnchor(runtime.drag_origin_rect, pivot_part, runtime.drag_transform.?.rotation);
                                    runtime.resize_pivot_world_center = runtime.drag_origin_rect.center();
                                    runtime.resize_pivot_is_center = modifiers.centered;
                                    runtime.resize_pivot_world = if (modifiers.centered)
                                        runtime.resize_pivot_world_center
                                    else
                                        runtime.resize_pivot_world_handle;
                                },
                            }
                            runtime.drag_aspect_ratio = transform.rectAspectRatio(runtime.drag_origin_rect);
                        }
                    },
                    else => {},
                }
            },
            else => {},
        }
    }

    if (runtime.drag_part) |part| {
        requestCursor(part);
    } else if (runtime.hover_part) |part| {
        requestCursor(part);
    }
}

fn applyDrag(self: anytype, part: SelectionDragPart, anchor_nat: Point, wd: *WidgetData, e: *Event) void {
    const runtime = self.runtime;
    const debug_info = &runtime.debug_info;
    const origin = runtime.drag_origin_rect;
    const modifiers = self.init_opts.transform_modifiers;
    switch (part) {
        .move => {
            if (!self.init_opts.can_move) return;
            const drag_transform = runtime.drag_transform orelse return;
            const delta_phys = Point.Physical.diff(runtime.pointer_current_phys, runtime.drag_pointer_origin_phys);
            const delta = delta_phys.scale(1 / drag_transform.rs.s, Point);
            self.state.rect = origin;
            self.state.rect.x = origin.x + delta.x;
            self.state.rect.y = origin.y + delta.y;
        },
        .rotate => {
            if (!self.init_opts.can_rotate) return;
            const current_angle = transform.angleFromCenterPhysical(runtime.rotation_center_phys, runtime.pointer_current_phys);
            const delta_angle = transform.normalizeAngle(current_angle - runtime.drag_origin_angle);
            var rotation = runtime.drag_origin_rotation + delta_angle;
            if (modifiers.fixed_increment and modifiers.rotation_increment > 0) {
                rotation = transform.snapAngleVertical(rotation, modifiers.rotation_increment);
            }
            self.state.rotation = rotation;
        },
        else => {
            if (!self.init_opts.can_resize) return;
            const min_size = self.init_opts.min_size;
            const use_centered = modifiers.centered;
            var rect = if (use_centered)
                transform.resizeRectCentered(part, anchor_nat, origin, min_size)
            else
                transform.resizeRect(part, anchor_nat, origin, min_size);

            if (modifiers.proportional) {
                rect = transform.applyProportionalScaling(rect, origin, runtime.drag_aspect_ratio, part, min_size, anchor_nat, use_centered);
            }

            if (modifiers.fixed_increment and modifiers.scale_increment > 0) {
                rect = transform.snapRectToIncrement(rect, part, min_size, modifiers.scale_increment);
            }

            rect = transform.enforceMinSize(rect, min_size);

            if (runtime.resize_pivot_part != null or runtime.resize_pivot_is_center) {
                const rotation = if (runtime.drag_transform) |drag_transform|
                    drag_transform.rotation
                else
                    self.state.rotation;
                rect = transform.repositionRectToPivot(rect, runtime.resize_pivot_world, runtime.resize_pivot_part, runtime.resize_pivot_is_center, rotation);
            }

            self.state.rect = rect;
        },
    }

    self.syncWidgetRect();
    e.handle(@src(), wd);
    dvui.refresh(null, @src(), wd.id);
    debug_info.drag_apply_count += 1;
    debug_info.last_rect = self.state.rect;
    debug_info.drag_offset = runtime.drag_offset;
}

fn hitTest(self: anytype, rs: RectScale, p: Point.Physical) ?SelectionDragPart {
    const test_point = transform.pointToSelectionSpace(self.state.rect, self.state.rotation, rs, p);
    if (self.init_opts.can_resize) {
        inline for (transform.corner_parts) |corner_part| {
            const rect = transform.selectionHandleRect(self.state.rect, corner_part);
            if (rect.contains(test_point)) {
                return corner_part;
            }
        }

        inline for (transform.edge_parts) |edge_part| {
            const rect = transform.selectionHandleRect(self.state.rect, edge_part);
            if (rect.contains(test_point)) {
                return edge_part;
            }
        }
    }

    if (self.init_opts.can_move and self.state.rect.contains(test_point)) return .move;

    if (self.init_opts.can_rotate) {
        inline for (transform.corner_parts) |corner_part| {
            const rect = transform.selectionOuterHandleRect(self.state.rect, corner_part);
            if (rect.contains(test_point)) {
                return .rotate;
            }
        }
    }

    return null;
}

fn recordDebugEvent(self: anytype, e: *Event, me: Event.Mouse, event_matches: bool, has_capture: bool, hovered_part: ?SelectionDragPart) void {
    const runtime = self.runtime;
    runtime.debug_info.last_event_num = e.num;
    runtime.debug_info.last_event_action = @tagName(me.action);
    runtime.debug_info.last_pointer = me.p;
    runtime.debug_info.event_matched = event_matches;
    runtime.debug_info.has_capture = has_capture;
    runtime.debug_info.hovered_part = hovered_part;
    runtime.debug_info.drag_part = runtime.drag_part;
    runtime.debug_info.drag_offset = runtime.drag_offset;
    runtime.debug_info.selected = self.state.selected;
    runtime.debug_info.hover_state = self.state.hovered;
    if (self.init_opts.debug_logging) {
        std.debug.print(
            "SelectionWidget dbg #{d} action={s} match={} capture={} hover={s} drag={s} pos=({d:0.1},{d:0.1}) rect=({d:0.1},{d:0.1},{d:0.1},{d:0.1})\n",
            .{
                e.num,
                runtime.debug_info.last_event_action,
                event_matches,
                has_capture,
                transform.partName(hovered_part),
                transform.partName(runtime.drag_part),
                me.p.x,
                me.p.y,
                self.state.rect.x,
                self.state.rect.y,
                self.state.rect.w,
                self.state.rect.h,
            },
        );
    }
}

fn setHoverPart(self: anytype, new_part: ?SelectionDragPart) void {
    const runtime = self.runtime;
    const changed = runtime.hover_part != new_part;
    runtime.hover_part = new_part;
    self.state.hovered = (new_part != null);
    runtime.debug_info.hovered_part = runtime.hover_part;
    runtime.debug_info.hover_state = self.state.hovered;
    if (changed) {
        if (new_part) |part| {
            requestCursor(part);
        }
    }
}

fn requestCursor(part: SelectionDragPart) void {
    dvui.cursorSet(part.cursor());
}

fn updateSelectionToggle(self: anytype) void {
    const runtime = self.runtime;
    const rs = self.data().borderRectScale();
    for (dvui.events()) |*e| {
        switch (e.evt) {
            .mouse => |me| {
                if (me.action == .press and me.button.pointer()) {
                    if (selectionHit(self, rs, me.p)) {
                        if (!self.state.selected) {
                            self.state.selected = true;
                            self.selection_activation_event = e.num;
                            throttledDebugPrint("SelectionWidget selected via event #{d}\n", .{e.num});
                        }
                    } else if (self.state.selected) {
                        self.state.selected = false;
                        runtime.drag_part = null;
                        runtime.drag_offset = .{};
                        runtime.drag_transform = null;
                        runtime.resize_pivot_part = null;
                        runtime.resize_pivot_world_handle = .{};
                        runtime.resize_pivot_world_center = .{};
                        runtime.resize_pivot_is_center = false;
                        throttledDebugPrint("SelectionWidget deselected via event #{d}\n", .{e.num});
                    }
                }
            },
            else => {},
        }
    }
}

fn selectionHit(self: anytype, rs: RectScale, p: Point.Physical) bool {
    const test_point = transform.pointToSelectionSpace(self.state.rect, self.state.rotation, rs, p);
    if (self.init_opts.can_rotate) {
        inline for (transform.corner_parts) |corner_part| {
            const rect = transform.selectionOuterHandleRect(self.state.rect, corner_part);
            if (rect.contains(test_point)) return true;
        }
    }
    inline for (transform.corner_parts) |corner_part| {
        const rect = transform.selectionHandleRect(self.state.rect, corner_part);
        if (rect.contains(test_point)) return true;
    }
    inline for (transform.edge_parts) |edge_part| {
        const rect = transform.selectionHandleRect(self.state.rect, edge_part);
        if (rect.contains(test_point)) return true;
    }
    return self.state.rect.contains(test_point);
}

fn updateActiveResizePivot(self: anytype, centered: bool) void {
    const runtime = self.runtime;
    const drag_part = runtime.drag_part orelse return;
    if (!transform.isResizePart(drag_part)) return;
    if (centered) {
        if (!runtime.resize_pivot_is_center) {
            runtime.resize_pivot_is_center = true;
            runtime.resize_pivot_world = runtime.resize_pivot_world_center;
        }
    } else {
        if (runtime.resize_pivot_is_center) {
            runtime.resize_pivot_is_center = false;
            runtime.resize_pivot_world = runtime.resize_pivot_world_handle;
        }
    }
}

var last_debug_print_ns: i128 = 0;

fn throttledDebugPrint(comptime fmt: []const u8, args: anytype) void {
    const now = std.time.nanoTimestamp();
    if (last_debug_print_ns != 0 and now - last_debug_print_ns < std.time.ns_per_s) return;
    last_debug_print_ns = now;
    std.debug.print(fmt, args);
}

test {
    @import("std").testing.refAllDecls(@This());
}
