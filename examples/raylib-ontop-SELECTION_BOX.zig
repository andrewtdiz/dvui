const std = @import("std");

const dvui = @import("dvui");
var layout_flex_content_justify = dvui.FlexBoxWidget.ContentPosition.start;
var layout_flex_align_items = dvui.FlexBoxWidget.AlignItems.start;
const RaylibBackend = @import("raylib-backend");
const ray = RaylibBackend.c;

var layout_flex_direction: dvui.enums.Direction = .horizontal;
var layout_flex_align_content: dvui.FlexBoxWidget.AlignContent = .start;

var last_frame_time: i128 = 0;
var frame_count: u64 = 0;
var fps: f64 = 0.0;

const SelectionDragPart = enum {
    move,
    resize_top_left,
    resize_top,
    resize_top_right,
    resize_right,
    resize_bottom_right,
    resize_bottom,
    resize_bottom_left,
    resize_left,

    fn cursor(self: SelectionDragPart) dvui.enums.Cursor {
        return switch (self) {
            .move => .arrow_all,
            .resize_top_left, .resize_bottom_right => .arrow_nw_se,
            .resize_top_right, .resize_bottom_left => .arrow_ne_sw,
            .resize_top, .resize_bottom => .arrow_n_s,
            .resize_left, .resize_right => .arrow_w_e,
        };
    }
};

var use_proportional_scaling = false;
var centered_scaling_enabled = false;
var fixed_increment_scaling_enabled = false;
const fixed_increment_step: f32 = 50;

var selection_rect = dvui.Rect{
    .x = 160,
    .y = 120,
    .w = 280,
    .h = 200,
};
var selection_rotation: f32 = 0.0;

var selection_drag_part: ?SelectionDragPart = null;
var selection_drag_origin_rect = dvui.Rect{
    .x = 160,
    .y = 120,
    .w = 280,
    .h = 200,
};
var selection_drag_origin_anchor = dvui.Point{ .x = 0, .y = 0 };
var selection_drag_offset = dvui.Point.Physical{ .x = 0, .y = 0 };
const selection_min_size = dvui.Size{ .w = 10, .h = 10 };
const selection_handle_visual: f32 = 10;
const selection_edge_handle_thickness: f32 = 16;
const selection_rotate_visual: f32 = 14;
const selection_rotate_gap: f32 = 24;
const selection_outer_hit_thickness: f32 = 12;
const selection_outer_hit_id_base: usize = 100;
const selection_outer_handle_visual_offset: f32 = 18;
var debug_show_hitboxes = false;

fn toggleProportional() void {
    use_proportional_scaling = !use_proportional_scaling;
    logScalingState("Proportional", use_proportional_scaling);
}

fn toggleCentered() void {
    centered_scaling_enabled = !centered_scaling_enabled;
    logScalingState("Centered", centered_scaling_enabled);
}

fn toggleFixedIncrements() void {
    fixed_increment_scaling_enabled = !fixed_increment_scaling_enabled;
    logScalingState("Fixed Increments", fixed_increment_scaling_enabled);
}

fn logScalingState(name: []const u8, enabled: bool) void {
    std.debug.print("{s} scaling {s}\n", .{ name, if (enabled) "enabled" else "disabled" });
}

comptime {
    std.debug.assert(@hasDecl(RaylibBackend, "RaylibBackend"));
}

const window_icon_png = @embedFile("zig-favicon.png");

//TODO:
//Figure out the best way to integrate raylib and dvui Event Handling

pub fn main() !void {
    if (@import("builtin").os.tag == .windows) { // optional
        // on windows graphical apps have no console, so output goes to nowhere - attach it manually. related: https://github.com/ziglang/zig/issues/4196
        try dvui.Backend.Common.windowsAttachConsole();
    }
    RaylibBackend.enableRaylibLogging();
    var gpa_instance = std.heap.GeneralPurposeAllocator(.{}){};
    const gpa = gpa_instance.allocator();

    defer _ = gpa_instance.deinit();

    // create OS window directly with raylib
    ray.SetConfigFlags(ray.FLAG_WINDOW_RESIZABLE);
    ray.SetConfigFlags(ray.FLAG_VSYNC_HINT);
    ray.InitWindow(800, 600, "DVUI Raylib Ontop Example");
    defer ray.CloseWindow();

    // init Raylib backend
    // init() means the app owns the window (and must call CloseWindow itself)
    var backend = RaylibBackend.init(gpa);
    defer backend.deinit();
    backend.log_events = true;

    // init dvui Window (maps onto a single OS window)
    // OS window is managed by raylib, not dvui
    var win = try dvui.Window.init(@src(), gpa, backend.backend(), .{});
    defer win.deinit();

    while (!ray.WindowShouldClose()) {
        ray.BeginDrawing();

        // FPS calculation
        const current_time = std.time.nanoTimestamp();
        if (last_frame_time != 0) {
            const elapsed_ns = current_time - last_frame_time;
            if (elapsed_ns > 0) {
                fps = 1_000_000_000.0 / @as(f64, @floatFromInt(elapsed_ns));
            }
        }
        last_frame_time = current_time;
        frame_count += 1;
        std.debug.print("FPS: {d:.1}\r", .{fps});

        // marks the beginning of a frame for dvui, can call dvui functions after this
        try win.begin(std.time.nanoTimestamp());

        // send all Raylib events to dvui for processing
        _ = try backend.addAllEvents(&win);

        if (backend.shouldBlockRaylibInput()) {
            // NOTE: I am using raygui here because it has a simple lock-unlock system
            // Non-raygui raylib apps could also easily implement such a system
            ray.GuiLock();
        } else {
            ray.GuiUnlock();
        }
        // if dvui widgets might not cover the whole window, then need to clear
        // the previous frame's render
        ray.ClearBackground(RaylibBackend.dvuiColorToRaylib(dvui.Color.black));

        dvuiStuff();

        // marks end of dvui frame, don't call dvui functions after this
        // - sends all dvui stuff to backend for rendering, must be called before EndDrawing()
        _ = try win.end(.{});

        // cursor management
        if (win.cursorRequestedFloating()) |cursor| {
            // cursor is over floating window, dvui sets it
            backend.setCursor(cursor);
        } else {
            backend.setCursor(win.cursorRequested());
        }

        ray.EndDrawing();
    }
}

fn updateDebugHitboxView() void {
    for (dvui.events()) |*e| {
            switch (e.evt) {
            .key => |ke| {
                if (ke.action == .down) {
                    switch (ke.code) {
                        .f6 => {
                            debug_show_hitboxes = !debug_show_hitboxes;
                        },
                        .left_shift => toggleProportional(),
                        .left_control => toggleCentered(),
                        .left_alt => toggleFixedIncrements(),
                        else => {},
                    }
                    continue;
                }
                if (ke.action == .up) {
                    switch (ke.code) {
                        .left_shift => toggleProportional(),
                        .left_control => toggleCentered(),
                        .left_alt => toggleFixedIncrements(),
                        else => {},
                    }
                    continue;
                }
            },
            .mouse => |me| {
                if (me.action == .press and me.button.pointer()) {
                    const click_nat = dvui.Point.cast(me.p.toNatural());
                    const in_selection = inSelectionHit(click_nat);
                    if (in_selection) {
                        selected = true;
                    } else if (selected) {
                        selected = false;
                    }
                }
            },
            else => {},
        }
    }
}

var hovered = false;
var selected = false;

fn dvuiStuff() void {
    updateDebugHitboxView();

    var overlay = dvui.overlay(@src(), .{
        .expand = .both,
        .name = "SelectionOverlay",
    });
    defer overlay.deinit();

    const selection_box = dvui.widgetAlloc(dvui.BoxWidget);
    selection_box.* = dvui.BoxWidget.init(@src(), .{}, .{
        .rect = selection_rect,
        .background = false, // DONT CHANGE THIS TO TRUE
        .color_fill = dvui.Color{ .r = 0x20, .g = 0x9b, .b = 0xff, .a = 0x40 },
        .border = dvui.Rect.all(if (selected) 1 else if (hovered) 2 else 0),
        .color_border = dvui.Color{ .r = 0x20, .g = 0x9b, .b = 0xff, .a = 0xff },
    });
    selection_box.data().was_allocated_on_widget_stack = true;
    selection_box.install();

    selectionOverlayProcess(selection_box);
    selection_box.drawBackground();
    selection_box.deinit();

    const show_debug = debug_show_hitboxes;

    if (selected) {
        inline for ([_]SelectionDragPart{
            .resize_top_left,
            .resize_top_right,
            .resize_bottom_right,
            .resize_bottom_left,
        }) |handle_part| {
            const handle_color = switch (handle_part) {
                .resize_top_left, .resize_top_right, .resize_bottom_left, .resize_bottom_right => dvui.Color{ .r = 255, .g = 255, .b = 255, .a = 0xff },
                else => dvui.Color{ .r = 255, .g = 255, .b = 255, .a = 0x40 },
            };
            const handle_border = switch (handle_part) {
                .resize_top_left, .resize_top_right, .resize_bottom_left, .resize_bottom_right => dvui.Rect.all(1),
                else => dvui.Rect.all(0),
            };
            var handle = dvui.box(@src(), .{}, .{
                .rect = selectionHandleRect(handle_part),
                .background = true,
                .color_fill = handle_color,
                .border = handle_border,
                .color_border = dvui.Color{ .r = 0x20, .g = 0x9b, .b = 0xff, .a = 0xff },
                .id_extra = @intCast(@intFromEnum(handle_part)),
            });
            defer handle.deinit();
        }

        const outer_color = dvui.Color{ .r = 255, .g = 255, .b = 255, .a = 100 };

        inline for ([_]SelectionDragPart{
            .resize_top_left,
            .resize_top_right,
            .resize_bottom_right,
            .resize_bottom_left,
        }, 0..) |handle_part, idx| {
            const outer_size = selection_handle_visual + (selection_outer_handle_visual_offset * 2);
            var outer_box = dvui.box(@src(), .{}, .{
                .rect = selectionOuterHandleRect(handle_part),
                .background = show_debug,
                .corner_radius = dvui.Rect.all(outer_size),
                .color_fill = outer_color,
                .id_extra = @intCast(selection_outer_hit_id_base + idx),
            });
            defer outer_box.deinit();
        }

        inline for ([_]SelectionDragPart{
            .resize_top,
            .resize_right,
            .resize_bottom,
            .resize_left,
        }) |handle_part| {
            const handle_color = switch (handle_part) {
                .resize_top, .resize_right, .resize_bottom, .resize_left => dvui.Color{ .r = 255, .g = 255, .b = 255, .a = if (show_debug) 0x40 else 0x00 },
                else => dvui.Color{ .r = 255, .g = 255, .b = 255, .a = 0xff },
            };
            const handle_border = switch (handle_part) {
                .resize_top_left, .resize_top_right, .resize_bottom_left, .resize_bottom_right => dvui.Rect.all(1),
                else => dvui.Rect.all(0),
            };
            var handle = dvui.box(@src(), .{}, .{
                .rect = selectionHandleRect(handle_part),
                .background = show_debug,
                .color_fill = handle_color,
                .border = handle_border,
                .color_border = dvui.Color{ .r = 0x20, .g = 0x9b, .b = 0xff, .a = 0xff },
                .id_extra = @intCast(@intFromEnum(handle_part)),
            });
            defer handle.deinit();
        }
    }
}

fn selectionOverlayProcess(selection_box: *dvui.BoxWidget) void {
    const data = selection_box.data();
    const rs = data.borderRectScale();
    const handle_half = selection_handle_visual * rs.s * 0.5;
    const interaction_rect = dvui.Rect.Physical{
        .x = rs.r.x - handle_half,
        .y = rs.r.y - handle_half,
        .w = rs.r.w + handle_half * 2,
        .h = rs.r.h + handle_half * 2,
    };

    hovered = false;

    for (dvui.events()) |*e| {
        if (!dvui.eventMatch(e, .{ .id = data.id, .r = interaction_rect })) continue;

        switch (e.evt) {
            .mouse => |me| {
                const hovered_part = selectionOverlayHitTest(rs, me.p);
                const rotate_part = selectionOuterHandleHit(rs, me.p);

                if (hovered_part != null or rotate_part != null) {
                    hovered = true;
                }

                if (dvui.captured(data.id)) {
                    if (selection_drag_part) |part| {
                        switch (me.action) {
                            .motion, .position => {
                                const origin = selection_drag_origin_rect;
                                const anchor_phys = me.p.plus(selection_drag_offset);
                                const anchor_nat = dvui.Point.cast(anchor_phys.toNatural());

                                switch (part) {
                                    .move => {
                                        const delta = dvui.Point{
                                            .x = anchor_nat.x - selection_drag_origin_anchor.x,
                                            .y = anchor_nat.y - selection_drag_origin_anchor.y,
                                        };
                                        selection_rect = origin;
                                        selection_rect.x = origin.x + delta.x;
                                        selection_rect.y = origin.y + delta.y;
                                    },
                                    else => {
                                        selection_rect = resizeWithMode(part, anchor_nat, origin);
                                    },
                                }

                                selectionOverlaySync(data);
                                e.handle(@src(), data);
                                dvui.refresh(null, @src(), data.id);
                                if (part != .move) {
                                    dvui.cursorSet(part.cursor());
                                }
                            },
                            .release => {
                                if (me.button.pointer()) {
                                    e.handle(@src(), data);
                                    dvui.captureMouse(null, e.num);
                                    selection_drag_part = null;
                                    selection_drag_offset = dvui.Point.Physical{ .x = 0, .y = 0 };
                                }
                            },
                            else => {},
                        }
                    }
                    continue;
                }

                switch (me.action) {
                    .press => {
                        if (rotate_part) |rp| {
                            e.handle(@src(), data);
                            dvui.cursorSet(selectionOuterHandleCursor(rp));
                            break;
                        }
                        if (!me.button.pointer()) break;
                        if (hovered_part) |part| {
                            e.handle(@src(), data);
                            dvui.captureMouse(data, e.num);
                            selection_drag_part = part;
                            selection_drag_origin_rect = selection_rect;
                            selection_drag_origin_anchor = selectionAnchorNatural(selection_drag_origin_rect, part);
                            const anchor_phys = selectionAnchorPhysical(rs, part);
                            selection_drag_offset = dvui.Point.Physical.diff(anchor_phys, me.p);
                            if (part != .move) {
                                dvui.cursorSet(part.cursor());
                            }
                        }
                    },
                    .motion, .position => {
                        if (hovered_part) |part| {
                            e.handle(@src(), data);
                            dvui.cursorSet(part.cursor());
                            continue;
                        }
                        if (rotate_part) |rp| {
                            e.handle(@src(), data);
                            dvui.cursorSet(selectionOuterHandleCursor(rp));
                            continue;
                        }
                    },
                    else => {},
                }
            },
            else => {},
        }
    }

    selectionOverlaySync(data);
}

fn selectionOverlaySync(data: *dvui.WidgetData) void {
    data.rect = selection_rect;
    data.options.rect = selection_rect;
    data.rect_scale = data.rectScaleFromParent();
}

fn resizeWithMode(part: SelectionDragPart, anchor_nat: dvui.Point, origin: dvui.Rect) dvui.Rect {
    var rect = if (centered_scaling_enabled)
        resizeCentered(part, anchor_nat, origin)
    else
        resizeFree(part, anchor_nat, origin);

    if (use_proportional_scaling) {
        const aspect = aspectRatio(origin);
        rect = enforceAspect(rect, part, aspect, origin, anchor_nat);
    }

    if (fixed_increment_scaling_enabled) {
        rect = applyFixedIncrements(rect, part);
    }

    return rect;
}

fn resizeFree(part: SelectionDragPart, anchor_nat: dvui.Point, origin: dvui.Rect) dvui.Rect {
    var edges = rectEdgesFromRect(origin);
    const control = partAxisControl(part);
    const min_w = selection_min_size.w;
    const min_h = selection_min_size.h;

    switch (control.horizontal) {
        .min => {
            const max_left = edges.right - min_w;
            edges.left = @min(anchor_nat.x, max_left);
        },
        .max => {
            const min_right = edges.left + min_w;
            edges.right = @max(anchor_nat.x, min_right);
        },
        .both => {
            const center = (edges.left + edges.right) * 0.5;
            const half = @max(min_w * 0.5, @abs(anchor_nat.x - center));
            edges.left = center - half;
            edges.right = center + half;
        },
        .none => {},
    }

    switch (control.vertical) {
        .min => {
            const max_top = edges.bottom - min_h;
            edges.top = @min(anchor_nat.y, max_top);
        },
        .max => {
            const min_bottom = edges.top + min_h;
            edges.bottom = @max(anchor_nat.y, min_bottom);
        },
        .both => {
            const center = (edges.top + edges.bottom) * 0.5;
            const half = @max(min_h * 0.5, @abs(anchor_nat.y - center));
            edges.top = center - half;
            edges.bottom = center + half;
        },
        .none => {},
    }

    return rectFromEdges(edges);
}

fn resizeCentered(part: SelectionDragPart, anchor_nat: dvui.Point, origin: dvui.Rect) dvui.Rect {
    var rect = origin;
    const control = partAxisControl(part);
    const center_x = origin.x + origin.w * 0.5;
    const center_y = origin.y + origin.h * 0.5;
    var half_w = origin.w * 0.5;
    var half_h = origin.h * 0.5;
    const min_half_w = selection_min_size.w * 0.5;
    const min_half_h = selection_min_size.h * 0.5;

    if (control.horizontal != .none) {
        half_w = @max(min_half_w, @abs(anchor_nat.x - center_x));
    }
    if (control.vertical != .none) {
        half_h = @max(min_half_h, @abs(anchor_nat.y - center_y));
    }

    rect.x = center_x - half_w;
    rect.y = center_y - half_h;
    rect.w = half_w * 2;
    rect.h = half_h * 2;
    return rect;
}

const AxisControl = enum { none, min, max, both };

const PartAxisControl = struct {
    horizontal: AxisControl,
    vertical: AxisControl,
};

fn partAxisControl(part: SelectionDragPart) PartAxisControl {
    return switch (part) {
        .move => .{ .horizontal = .none, .vertical = .none },
        .resize_top_left => .{ .horizontal = .min, .vertical = .min },
        .resize_top => .{ .horizontal = .none, .vertical = .min },
        .resize_top_right => .{ .horizontal = .max, .vertical = .min },
        .resize_right => .{ .horizontal = .max, .vertical = .none },
        .resize_bottom_right => .{ .horizontal = .max, .vertical = .max },
        .resize_bottom => .{ .horizontal = .none, .vertical = .max },
        .resize_bottom_left => .{ .horizontal = .min, .vertical = .max },
        .resize_left => .{ .horizontal = .min, .vertical = .none },
    };
}

fn axisControlForMode(control: AxisControl) AxisControl {
    if (control == .none) return .none;
    if (centered_scaling_enabled) return .both;
    return control;
}

fn applyFixedIncrements(rect_in: dvui.Rect, part: SelectionDragPart) dvui.Rect {
    var rect = rect_in;
    const control = partAxisControl(part);
    const horizontal = axisControlForMode(control.horizontal);
    const vertical = axisControlForMode(control.vertical);

    if (horizontal != .none) {
        const snapped_w = snapDimension(rect.w, fixed_increment_step, selection_min_size.w);
        rect = adjustWidth(rect, horizontal, snapped_w);
    }
    if (vertical != .none) {
        const snapped_h = snapDimension(rect.h, fixed_increment_step, selection_min_size.h);
        rect = adjustHeight(rect, vertical, snapped_h);
    }

    return rect;
}

const RectEdges = struct {
    left: f32,
    right: f32,
    top: f32,
    bottom: f32,
};

fn rectEdgesFromRect(rect: dvui.Rect) RectEdges {
    return .{
        .left = rect.x,
        .right = rect.x + rect.w,
        .top = rect.y,
        .bottom = rect.y + rect.h,
    };
}

fn rectFromEdges(edges: RectEdges) dvui.Rect {
    return dvui.Rect{
        .x = edges.left,
        .y = edges.top,
        .w = edges.right - edges.left,
        .h = edges.bottom - edges.top,
    };
}

fn adjustWidth(rect: dvui.Rect, control: AxisControl, new_width: f32) dvui.Rect {
    var result = rect;
    const min_w = selection_min_size.w;
    const width = @max(min_w, new_width);
    const left = rect.x;
    const right = rect.x + rect.w;
    switch (control) {
        .min => {
            result.x = right - width;
        },
        .max => {
            result.x = left;
        },
        .both, .none => {
            const center = left + rect.w * 0.5;
            result.x = center - width * 0.5;
        },
    }
    result.w = width;
    return result;
}

fn adjustHeight(rect: dvui.Rect, control: AxisControl, new_height: f32) dvui.Rect {
    var result = rect;
    const min_h = selection_min_size.h;
    const height = @max(min_h, new_height);
    const top = rect.y;
    const bottom = rect.y + rect.h;
    switch (control) {
        .min => {
            result.y = bottom - height;
        },
        .max => {
            result.y = top;
        },
        .both, .none => {
            const center = top + rect.h * 0.5;
            result.y = center - height * 0.5;
        },
    }
    result.h = height;
    return result;
}

fn enforceAspect(rect: dvui.Rect, part: SelectionDragPart, aspect: f32, origin: dvui.Rect, anchor_nat: dvui.Point) dvui.Rect {
    var result = rect;
    if (aspect <= 0) return result;
    const control = partAxisControl(part);
    const horizontal_control = axisControlForMode(control.horizontal);
    const vertical_control = axisControlForMode(control.vertical);
    const horizontal_active = horizontal_control != .none;
    const vertical_active = vertical_control != .none;

    if (!horizontal_active and !vertical_active) {
        return result;
    }

    if (horizontal_active and !vertical_active) {
        const new_h = result.w / aspect;
        return adjustHeight(result, vertical_control, new_h);
    }

    if (vertical_active and !horizontal_active) {
        const new_w = result.h * aspect;
        return adjustWidth(result, horizontal_control, new_w);
    }

    const horizontal_offset: f32 = if (horizontal_active)
        axisOffset(anchor_nat.x, origin.x, origin.w, horizontal_control)
    else
        0;
    const vertical_offset: f32 = if (vertical_active)
        axisOffset(anchor_nat.y, origin.y, origin.h, vertical_control)
    else
        0;

    const dominant_horizontal = horizontal_offset >= vertical_offset;
    if (dominant_horizontal) {
        const new_h = result.w / aspect;
        result = adjustHeight(result, vertical_control, new_h);
    } else {
        const new_w = result.h * aspect;
        result = adjustWidth(result, horizontal_control, new_w);
    }
    return result;
}

fn axisOffset(anchor_value: f32, start: f32, size: f32, control: AxisControl) f32 {
    return switch (control) {
        .min => @abs(anchor_value - (start + size)),
        .max => @abs(anchor_value - start),
        .both => @abs(anchor_value - (start + size * 0.5)),
        .none => 0,
    };
}

fn snapDimension(value: f32, increment: f32, min_value: f32) f32 {
    if (increment <= 0) return value;
    const snapped = std.math.round(value / increment) * increment;
    return @max(min_value, snapped);
}

fn aspectRatio(rect: dvui.Rect) f32 {
    if (rect.h <= 0.0001) return 1;
    return rect.w / rect.h;
}

fn selectionOverlayHitTest(rs: dvui.RectScale, p: dvui.Point.Physical) ?SelectionDragPart {
    inline for ([_]SelectionDragPart{
        .resize_top_left,
        .resize_top_right,
        .resize_bottom_right,
        .resize_bottom_left,
    }) |corner_part| {
        if (selectionHandleRectPhysical(rs, corner_part).contains(p)) {
            return corner_part;
        }
    }

    inline for ([_]SelectionDragPart{
        .resize_top,
        .resize_right,
        .resize_bottom,
        .resize_left,
    }) |handle_part| {
        if (selectionHandleRectPhysical(rs, handle_part).contains(p)) {
            return handle_part;
        }
    }

    if (rs.r.contains(p)) return .move;
    return null;
}

fn selectionOuterHandleHit(rs: dvui.RectScale, p: dvui.Point.Physical) ?SelectionDragPart {
    const corners = [_]SelectionDragPart{
        .resize_top_left,
        .resize_top_right,
        .resize_bottom_right,
        .resize_bottom_left,
    };
    for (corners) |corner_part| {
        const outer_rect = rs.rectToPhysical(selectionOuterHandleRect(corner_part));
        const inner_rect = selectionHandleRectPhysical(rs, corner_part);
        if (outer_rect.contains(p) and !inner_rect.contains(p) and !rs.r.contains(p)) {
            return corner_part;
        }
    }
    return null;
}

fn inSelectionHit(p: dvui.Point) bool {
    const corners = [_]SelectionDragPart{
        .resize_top_left,
        .resize_top_right,
        .resize_bottom_right,
        .resize_bottom_left,
    };
    inline for (corners) |corner_part| {
        if (selectionHandleRect(corner_part).contains(p)) return true;
    }
    inline for ([_]SelectionDragPart{
        .resize_top,
        .resize_right,
        .resize_bottom,
        .resize_left,
    }) |edge_part| {
        if (selectionHandleRect(edge_part).contains(p)) return true;
    }
    if (selection_rect.contains(p)) return true;
    return false;
}

fn selectionOuterHandleCursor(part: SelectionDragPart) dvui.enums.Cursor {
    return switch (part) {
        .resize_top_left, .resize_bottom_right => .arrow_nw_se,
        .resize_top_right, .resize_bottom_left => .arrow_ne_sw,
        else => .arrow_all,
    };
}

fn selectionAnchorNatural(rect: dvui.Rect, part: SelectionDragPart) dvui.Point {
    return switch (part) {
        .move, .resize_top_left => rect.topLeft(),
        .resize_top => dvui.Point{ .x = rect.x + rect.w * 0.5, .y = rect.y },
        .resize_top_right => rect.topRight(),
        .resize_right => dvui.Point{ .x = rect.x + rect.w, .y = rect.y + rect.h * 0.5 },
        .resize_bottom_right => rect.bottomRight(),
        .resize_bottom => dvui.Point{ .x = rect.x + rect.w * 0.5, .y = rect.y + rect.h },
        .resize_bottom_left => rect.bottomLeft(),
        .resize_left => dvui.Point{ .x = rect.x, .y = rect.y + rect.h * 0.5 },
    };
}

fn selectionAnchorPhysical(rs: dvui.RectScale, part: SelectionDragPart) dvui.Point.Physical {
    const rect = rs.r;
    return switch (part) {
        .move, .resize_top_left => rect.topLeft(),
        .resize_top => dvui.Point.Physical{ .x = rect.x + rect.w * 0.5, .y = rect.y },
        .resize_top_right => rect.topRight(),
        .resize_right => dvui.Point.Physical{ .x = rect.x + rect.w, .y = rect.y + rect.h * 0.5 },
        .resize_bottom_right => rect.bottomRight(),
        .resize_bottom => dvui.Point.Physical{ .x = rect.x + rect.w * 0.5, .y = rect.y + rect.h },
        .resize_bottom_left => rect.bottomLeft(),
        .resize_left => dvui.Point.Physical{ .x = rect.x, .y = rect.y + rect.h * 0.5 },
    };
}

fn selectionHandleRect(part: SelectionDragPart) dvui.Rect {
    const corner_size = selection_handle_visual;
    const corner_half = corner_size * 0.5;
    const edge_size = selection_edge_handle_thickness;
    const edge_half = edge_size * 0.5;
    const horizontal_len = @max(@as(f32, 0), selection_rect.w - corner_size);
    const vertical_len = @max(@as(f32, 0), selection_rect.h - corner_size);
    return switch (part) {
        .resize_top_left => dvui.Rect{
            .x = selection_rect.x - corner_half,
            .y = selection_rect.y - corner_half,
            .w = corner_size,
            .h = corner_size,
        },
        .resize_top => dvui.Rect{
            .x = selection_rect.x + corner_half,
            .y = selection_rect.y - edge_half,
            .w = horizontal_len,
            .h = edge_size,
        },
        .resize_top_right => dvui.Rect{
            .x = selection_rect.x + selection_rect.w - corner_half,
            .y = selection_rect.y - corner_half,
            .w = corner_size,
            .h = corner_size,
        },
        .resize_right => dvui.Rect{
            .x = selection_rect.x + selection_rect.w - edge_half,
            .y = selection_rect.y + corner_half,
            .w = edge_size,
            .h = vertical_len,
        },
        .resize_bottom_right => dvui.Rect{
            .x = selection_rect.x + selection_rect.w - corner_half,
            .y = selection_rect.y + selection_rect.h - corner_half,
            .w = corner_size,
            .h = corner_size,
        },
        .resize_bottom => dvui.Rect{
            .x = selection_rect.x + corner_half,
            .y = selection_rect.y + selection_rect.h - edge_half,
            .w = horizontal_len,
            .h = edge_size,
        },
        .resize_bottom_left => dvui.Rect{
            .x = selection_rect.x - corner_half,
            .y = selection_rect.y + selection_rect.h - corner_half,
            .w = corner_size,
            .h = corner_size,
        },
        .resize_left => dvui.Rect{
            .x = selection_rect.x - edge_half,
            .y = selection_rect.y + corner_half,
            .w = edge_size,
            .h = vertical_len,
        },
        .move => unreachable,
    };
}

fn selectionOuterHandleRect(part: SelectionDragPart) dvui.Rect {
    const corner_size = selection_handle_visual;
    const outer_size = corner_size + (selection_outer_handle_visual_offset * 2);
    const outer_half = outer_size * 0.5;
    return switch (part) {
        .resize_top_left => dvui.Rect{
            .x = selection_rect.x - outer_half,
            .y = selection_rect.y - outer_half,
            .w = outer_size,
            .h = outer_size,
        },
        .resize_top_right => dvui.Rect{
            .x = selection_rect.x + selection_rect.w - outer_half,
            .y = selection_rect.y - outer_half,
            .w = outer_size,
            .h = outer_size,
        },
        .resize_bottom_right => dvui.Rect{
            .x = selection_rect.x + selection_rect.w - outer_half,
            .y = selection_rect.y + selection_rect.h - outer_half,
            .w = outer_size,
            .h = outer_size,
        },
        .resize_bottom_left => dvui.Rect{
            .x = selection_rect.x - outer_half,
            .y = selection_rect.y + selection_rect.h - outer_half,
            .w = outer_size,
            .h = outer_size,
        },
        else => dvui.Rect{},
    };
}

fn selectionHandleRectPhysical(rs: dvui.RectScale, part: SelectionDragPart) dvui.Rect.Physical {
    const corner_size = selection_handle_visual * rs.s;
    const corner_half = corner_size * 0.5;
    const edge_size = selection_edge_handle_thickness * rs.s;
    const edge_half = edge_size * 0.5;
    const horizontal_len = @max(@as(f32, 0), rs.r.w - corner_size);
    const vertical_len = @max(@as(f32, 0), rs.r.h - corner_size);
    return switch (part) {
        .resize_top_left => dvui.Rect.Physical{
            .x = rs.r.x - corner_half,
            .y = rs.r.y - corner_half,
            .w = corner_size,
            .h = corner_size,
        },
        .resize_top => dvui.Rect.Physical{
            .x = rs.r.x + corner_half,
            .y = rs.r.y - edge_half,
            .w = horizontal_len,
            .h = edge_size,
        },
        .resize_top_right => dvui.Rect.Physical{
            .x = rs.r.x + rs.r.w - corner_half,
            .y = rs.r.y - corner_half,
            .w = corner_size,
            .h = corner_size,
        },
        .resize_right => dvui.Rect.Physical{
            .x = rs.r.x + rs.r.w - edge_half,
            .y = rs.r.y + corner_half,
            .w = edge_size,
            .h = vertical_len,
        },
        .resize_bottom_right => dvui.Rect.Physical{
            .x = rs.r.x + rs.r.w - corner_half,
            .y = rs.r.y + rs.r.h - corner_half,
            .w = corner_size,
            .h = corner_size,
        },
        .resize_bottom => dvui.Rect.Physical{
            .x = rs.r.x + corner_half,
            .y = rs.r.y + rs.r.h - edge_half,
            .w = horizontal_len,
            .h = edge_size,
        },
        .resize_bottom_left => dvui.Rect.Physical{
            .x = rs.r.x - corner_half,
            .y = rs.r.y + rs.r.h - corner_half,
            .w = corner_size,
            .h = corner_size,
        },
        .resize_left => dvui.Rect.Physical{
            .x = rs.r.x - edge_half,
            .y = rs.r.y + corner_half,
            .w = edge_size,
            .h = vertical_len,
        },
        .move => unreachable,
    };
}
