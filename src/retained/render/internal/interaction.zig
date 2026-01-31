const dvui = @import("dvui");

const types = @import("../../core/types.zig");
const direct = @import("../direct.zig");
const state = @import("state.zig");

const rectContains = state.rectContains;
const intersectRect = state.intersectRect;
const isPortalNode = state.isPortalNode;
const nodeIdExtra = state.nodeIdExtra;
const physicalToDvuiRect = state.physicalToDvuiRect;
const transformedRect = direct.transformedRect;
const PointerPick = state.PointerPick;

fn pointerEventAllowed(node_id: u32, widget_id: dvui.Id, e: *dvui.Event) bool {
    switch (e.evt) {
        .mouse => {
            if (e.target_widgetId) |target| {
                return target == widget_id;
            }
            return state.pointerTargetId() == node_id;
        },
        else => return true,
    }
}

pub fn scanPickInteractive(
    store: *types.NodeStore,
    node: *types.SolidNode,
    point: dvui.Point.Physical,
    clip_rect: ?types.Rect,
    result: *PointerPick,
    order: *u32,
    skip_portals: bool,
) void {
    if (skip_portals and isPortalNode(node)) return;
    if (clip_rect) |clip| {
        if (!rectContains(clip, point)) return;
    }

    var next_clip = clip_rect;
    var node_rect: ?types.Rect = null;
    if (node.kind == .element) {
        const spec = node.prepareClassSpec();
        if (!spec.hidden and node.visual.opacity > 0) {
            if (node.layout.rect) |base_rect| {
                node_rect = transformedRect(node, base_rect) orelse base_rect;
            }
            if (node_rect) |rect| {
                if (rectContains(rect, point)) {
                    if (node.isInteractive()) {
                        order.* += 1;
                        const z_index = node.visual.z_index;
                        if (z_index > result.z_index or (z_index == result.z_index and order.* >= result.order)) {
                            result.* = .{
                                .id = node.id,
                                .z_index = z_index,
                                .order = order.*,
                            };
                        }
                    }
                }
                if ((spec.clip_children orelse false) or node.visual.clip_children) {
                    if (next_clip) |clip| {
                        next_clip = intersectRect(clip, rect);
                        if (next_clip == null) return;
                    } else {
                        next_clip = rect;
                    }
                }
            }
        }
    }

    for (node.children.items) |child_id| {
        if (store.node(child_id)) |child| {
            scanPickInteractive(store, child, point, next_clip, result, order, skip_portals);
        }
    }
}

pub fn pickInteractiveId(store: *types.NodeStore, root: *types.SolidNode, point: dvui.Point.Physical, skip_portals: bool) u32 {
    var result: PointerPick = .{};
    var order: u32 = 0;
    scanPickInteractive(store, root, point, null, &result, &order, skip_portals);
    return result.id;
}

pub fn clickedExTopmost(wd: *const dvui.WidgetData, node_id: u32, opts: dvui.ClickOptions) ?dvui.Event.EventTypes {
    var click_event: ?dvui.Event.EventTypes = null;

    const click_rect = opts.rect orelse wd.borderRectScale().r;
    for (dvui.events()) |*e| {
        if (!pointerEventAllowed(node_id, wd.id, e)) continue;
        if (!dvui.eventMatch(e, .{ .id = wd.id, .r = click_rect })) continue;

        switch (e.evt) {
            .mouse => |me| {
                if (me.action == .focus) {
                    e.handle(@src(), wd);
                    dvui.focusWidget(wd.id, null, e.num);
                } else if (me.action == .press and (if (opts.buttons == .pointer) me.button.pointer() else true)) {
                    e.handle(@src(), wd);
                    dvui.captureMouse(wd, e.num);
                    dvui.dragPreStart(me.p, .{});
                } else if (me.action == .release and (if (opts.buttons == .pointer) me.button.pointer() else true)) {
                    if (dvui.captured(wd.id)) {
                        e.handle(@src(), wd);
                        dvui.captureMouse(null, e.num);
                        dvui.dragEnd();
                        if (click_rect.contains(me.p)) {
                            dvui.refresh(null, @src(), wd.id);
                            click_event = .{ .mouse = me };
                        }
                    }
                } else if (me.action == .motion and me.button.touch()) {
                    if (dvui.captured(wd.id)) {
                        if (dvui.dragging(me.p, null)) |_| {
                            dvui.captureMouse(null, e.num);
                            dvui.dragEnd();
                        }
                    }
                } else if (me.action == .position) {
                    if (opts.hover_cursor) |cursor| {
                        dvui.cursorSet(cursor);
                    }
                    if (opts.hovered) |hovered| {
                        hovered.* = true;
                    }
                }
            },
            .key => |ke| {
                if (ke.action == .down and ke.matchBind("activate")) {
                    e.handle(@src(), wd);
                    click_event = .{ .key = ke };
                    dvui.refresh(null, @src(), wd.id);
                }
            },
            else => {},
        }
    }
    return click_event;
}

pub fn clickedTopmost(wd: *const dvui.WidgetData, node_id: u32, opts: dvui.ClickOptions) bool {
    return clickedExTopmost(wd, node_id, opts) != null;
}

pub fn handleScrollInput(
    node: *types.SolidNode,
    hit_rect: types.Rect,
    scroll_info: *dvui.ScrollInfo,
    scroll_id: dvui.Id,
) bool {
    _ = node;
    if (!state.input_enabled_state) return false;
    const rect_phys = direct.rectToPhysical(hit_rect);
    const allow_vertical = scroll_info.scrollMax(.vertical) > 0;
    const allow_horizontal = scroll_info.scrollMax(.horizontal) > 0;
    var changed = false;

    for (dvui.events()) |*e| {
        if (!dvui.eventMatch(e, .{ .id = scroll_id, .r = rect_phys })) continue;

        switch (e.evt) {
            .mouse => |me| {
                switch (me.action) {
                    .wheel_y => |ticks| {
                        if (!allow_vertical) break;
                        scroll_info.scrollByOffset(.vertical, -ticks);
                        changed = true;
                        e.handled = true;
                        dvui.refresh(null, @src(), scroll_id);
                    },
                    .wheel_x => |ticks| {
                        if (!allow_horizontal) break;
                        scroll_info.scrollByOffset(.horizontal, ticks);
                        changed = true;
                        e.handled = true;
                        dvui.refresh(null, @src(), scroll_id);
                    },
                    .press => {
                        if (me.button.touch() and (allow_vertical or allow_horizontal)) {
                            const capture = dvui.CaptureMouse{
                                .id = scroll_id,
                                .rect = rect_phys,
                                .subwindow_id = dvui.subwindowCurrentId(),
                            };
                            dvui.captureMouseCustom(capture, e.num);
                            dvui.dragPreStart(me.p, .{});
                            e.handled = true;
                        }
                    },
                    .release => {
                        if (me.button.touch() and dvui.captured(scroll_id)) {
                            dvui.captureMouseCustom(null, e.num);
                            dvui.dragEnd();
                            e.handled = true;
                        }
                    },
                    .motion => {
                        if (dvui.captured(scroll_id)) {
                            if (dvui.dragging(me.p, null)) |dp| {
                                if (allow_horizontal) {
                                    scroll_info.scrollByOffset(.horizontal, -dp.x);
                                }
                                if (allow_vertical) {
                                    scroll_info.scrollByOffset(.vertical, -dp.y);
                                }
                                changed = true;
                                e.handled = true;
                                dvui.refresh(null, @src(), scroll_id);
                            }
                        }
                    },
                    else => {},
                }
            },
            else => {},
        }
    }

    return changed;
}

fn drawScrollBarStatic(rect: types.Rect, scroll_info: dvui.ScrollInfo, dir: dvui.enums.Direction) void {
    const rect_phys = direct.rectToPhysical(rect);
    if (rect_phys.w <= 0 or rect_phys.h <= 0) return;

    const theme = dvui.themeGet();
    rect_phys.fill(.all(100), .{ .color = theme.border.opacity(0.2), .fade = 1.0 });

    var grab = rect_phys;
    switch (dir) {
        .vertical => {
            const fraction = scroll_info.visibleFraction(.vertical);
            const grab_h = @min(grab.h, @max(20.0, grab.h * fraction));
            grab.h = grab_h;
            grab.y += (rect_phys.h - grab_h) * scroll_info.offsetFraction(.vertical);
        },
        .horizontal => {
            const fraction = scroll_info.visibleFraction(.horizontal);
            const grab_w = @min(grab.w, @max(20.0, grab.w * fraction));
            grab.w = grab_w;
            grab.x += (rect_phys.w - grab_w) * scroll_info.offsetFraction(.horizontal);
        },
    }

    grab.fill(.all(100), .{ .color = theme.text.opacity(0.5), .fade = 1.0 });
}

pub fn renderScrollBars(
    node: *types.SolidNode,
    viewport: types.Rect,
    scroll_info: *dvui.ScrollInfo,
    scroll_id: dvui.Id,
) bool {
    const thickness = node.scroll.scrollbar_thickness;
    if (thickness <= 0) return false;

    const show_v = scroll_info.scrollMax(.vertical) > 0;
    const show_h = scroll_info.scrollMax(.horizontal) > 0;
    if (!show_v and !show_h) return false;

    const prev_x = scroll_info.viewport.x;
    const prev_y = scroll_info.viewport.y;

    if (show_v) {
        var bar_rect = viewport;
        bar_rect.x = viewport.x + viewport.w - thickness;
        bar_rect.w = thickness;
        if (show_h) {
            bar_rect.h = @max(0.0, bar_rect.h - thickness);
        }
        if (state.input_enabled_state) {
            const options = dvui.Options{
                .name = "solid-scrollbar",
                .rect = physicalToDvuiRect(bar_rect),
                .background = true,
                .id_extra = nodeIdExtra(node.id ^ 0x9e3779b9),
            };
            var bar = dvui.ScrollBarWidget.init(
                @src(),
                .{ .scroll_info = scroll_info, .direction = .vertical, .focus_id = scroll_id },
                options,
            );
            bar.install();
            const grab = bar.grab();
            grab.draw();
            bar.deinit();
        } else {
            drawScrollBarStatic(bar_rect, scroll_info.*, .vertical);
        }
    }

    if (show_h) {
        var bar_rect = viewport;
        bar_rect.y = viewport.y + viewport.h - thickness;
        bar_rect.h = thickness;
        if (show_v) {
            bar_rect.w = @max(0.0, bar_rect.w - thickness);
        }
        if (state.input_enabled_state) {
            const options = dvui.Options{
                .name = "solid-scrollbar",
                .rect = physicalToDvuiRect(bar_rect),
                .background = true,
                .id_extra = nodeIdExtra(node.id ^ 0x3c6ef372),
            };
            var bar = dvui.ScrollBarWidget.init(
                @src(),
                .{ .scroll_info = scroll_info, .direction = .horizontal, .focus_id = scroll_id },
                options,
            );
            bar.install();
            const grab = bar.grab();
            grab.draw();
            bar.deinit();
        } else {
            drawScrollBarStatic(bar_rect, scroll_info.*, .horizontal);
        }
    }

    return scroll_info.viewport.x != prev_x or scroll_info.viewport.y != prev_y;
}
