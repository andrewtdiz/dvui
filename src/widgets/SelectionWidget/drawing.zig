const std = @import("std");
const dvui = @import("../../dvui.zig");
const transform = @import("transform.zig");

const Color = dvui.Color;
const Rect = dvui.Rect;
const RectScale = dvui.RectScale;
const Point = dvui.Point;

const debug_simple_render = false;
const debug_overlay_width: f32 = 360;
const debug_overlay_padding: f32 = 6;

pub fn draw(self: anytype) void {
    const wd = self.data();
    if (!wd.visible()) return;

    const rs = wd.borderRectScale();
    const rotation_origin = rs.r.center();
    const cw = dvui.currentWindow();

    const fill_color = Color{ .r = 0x00, .g = 0x00, .b = 0x00, .a = 0x00 };
    const border_color = (self.init_opts.color_border orelse Color{ .r = 0x20, .g = 0x9b, .b = 0xff, .a = 0xff }).opacity(cw.alpha);

    if (debug_simple_render) {
        drawQuad(rs.r, rotation_origin, 0, Color{ .r = 0xff, .g = 0x00, .b = 0xff, .a = 0 });
        return;
    }

    drawQuad(rs.r, rotation_origin, self.state.rotation, fill_color);

    const border_thickness: f32 = if (self.state.selected) 1 else if (self.state.hovered) 2 else 0;
    if (border_thickness > 0) {
        drawBorder(self, rs, rotation_origin, border_thickness * rs.s, border_color);
    }

    drawDebugOverlay(self, rs);

    if (!self.state.selected) return;
    drawHandles(self, rs, rotation_origin);
}

fn drawHandles(self: anytype, rs: RectScale, rotation_origin: Point.Physical) void {
    const cw = dvui.currentWindow();
    const handle_fill = (self.init_opts.handle_color_fill orelse Color{ .r = 0xff, .g = 0xff, .b = 0xff, .a = 0xff }).opacity(cw.alpha);
    const handle_border = (self.init_opts.handle_color_border orelse Color{ .r = 0x20, .g = 0x9b, .b = 0xff, .a = 0xff }).opacity(cw.alpha);

    inline for (transform.corner_parts) |part| {
        const rect_nat = transform.selectionHandleRect(self.state.rect, part);
        const rect = transform.rectNaturalToPhysical(self.state.rect, rect_nat, rs);
        drawQuad(rect, rotation_origin, self.state.rotation, handle_fill);
        drawBorderForRect(rect, rotation_origin, self.state.rotation, 1 * rs.s, handle_border);
    }

    inline for (transform.edge_parts) |part| {
        const rect_nat = transform.selectionHandleRect(self.state.rect, part);
        const rect = transform.rectNaturalToPhysical(self.state.rect, rect_nat, rs);
        drawQuad(rect, rotation_origin, self.state.rotation, handle_fill.opacity(0));
    }

    if (self.init_opts.can_rotate) {
        const outer_color = (Color{ .r = 0xff, .g = 0xff, .b = 0xff, .a = 0 }).opacity(cw.alpha);
        inline for (transform.corner_parts) |part| {
            const base_nat = transform.selectionOuterHandleRect(self.state.rect, part);
            const base_rect = transform.rectNaturalToPhysical(self.state.rect, base_nat, rs);
            const base_center = base_rect.center();
            const rotated_center = transform.rotatePointAround(base_center, rotation_origin, self.state.rotation);
            const circle_rect = Rect.Physical{
                .x = rotated_center.x - base_rect.w * 0.5,
                .y = rotated_center.y - base_rect.h * 0.5,
                .w = base_rect.w,
                .h = base_rect.h,
            };
            drawCircle(circle_rect, outer_color);
        }
    }
}

fn drawCircle(rect: Rect.Physical, color: Color) void {
    if (color.a == 0) return;
    const radius = Rect.Physical.all(rect.w);
    rect.fill(radius, .{ .color = color, .fade = 0 });
}

fn drawBorder(self: anytype, rs: RectScale, origin: Point.Physical, thickness: f32, color: Color) void {
    if (thickness <= 0 or color.a == 0) return;
    const rect = rs.r;
    const inset = thickness * 0.5;
    const top = Rect.Physical{ .x = rect.x, .y = rect.y - inset, .w = rect.w, .h = thickness };
    const bottom = Rect.Physical{ .x = rect.x, .y = rect.y + rect.h - inset, .w = rect.w, .h = thickness };
    const left = Rect.Physical{ .x = rect.x - inset, .y = rect.y, .w = thickness, .h = rect.h };
    const right = Rect.Physical{ .x = rect.x + rect.w - inset, .y = rect.y, .w = thickness, .h = rect.h };

    drawQuad(top, origin, self.state.rotation, color);
    drawQuad(bottom, origin, self.state.rotation, color);
    drawQuad(left, origin, self.state.rotation, color);
    drawQuad(right, origin, self.state.rotation, color);
}

fn drawBorderForRect(rect: Rect.Physical, origin: Point.Physical, rotation: f32, thickness: f32, color: Color) void {
    if (thickness <= 0 or color.a == 0) return;
    const inset = thickness * 0.5;
    const top = Rect.Physical{ .x = rect.x, .y = rect.y - inset, .w = rect.w, .h = thickness };
    const bottom = Rect.Physical{ .x = rect.x, .y = rect.y + rect.h - inset, .w = rect.w, .h = thickness };
    const left = Rect.Physical{ .x = rect.x - inset, .y = rect.y, .w = thickness, .h = rect.h };
    const right = Rect.Physical{ .x = rect.x + rect.w - inset, .y = rect.y, .w = thickness, .h = rect.h };

    drawQuad(top, origin, rotation, color);
    drawQuad(bottom, origin, rotation, color);
    drawQuad(left, origin, rotation, color);
    drawQuad(right, origin, rotation, color);
}

fn drawQuad(rect: Rect.Physical, origin: Point.Physical, rotation: f32, color: Color) void {
    if (rect.w <= 0 or rect.h <= 0 or color.a == 0) return;
    const cw = dvui.currentWindow();
    var path = dvui.Path.Builder.init(cw.lifo());
    defer path.deinit();
    path.addRect(rect, .all(0));
    var triangles = path.build().fillConvexTriangles(cw.lifo(), .{ .color = color }) catch return;
    defer triangles.deinit(cw.lifo());
    if (rotation != 0) {
        triangles.rotate(origin, rotation);
    }
    dvui.renderTriangles(triangles, null) catch {};
}

fn drawDebugOverlay(self: anytype, rs: RectScale) void {
    if (!self.init_opts.debug_overlay) return;
    const info = self.runtime.debug_info;
    const theme = dvui.themeGet();
    const font = theme.font_caption;
    const color = theme.color(.content, .text);
    const line_height = font.size * font.line_height_factor * rs.s;
    const line_count: f32 = 5;
    const start_x = rs.r.x;
    var start_y = rs.r.y + rs.r.h + debug_overlay_padding * rs.s;
    const bg_rect = Rect.Physical{
        .x = start_x - debug_overlay_padding * rs.s,
        .y = start_y - debug_overlay_padding * rs.s,
        .w = debug_overlay_width * rs.s + debug_overlay_padding * 2 * rs.s,
        .h = line_height * line_count + debug_overlay_padding * 2 * rs.s,
    };
    drawQuad(bg_rect, bg_rect.center(), 0, theme.focus.opacity(0.15));

    debugPrintLine(rs, font, color, start_x, start_y, "event #{d} action={s} match={} capture={}", .{
        info.last_event_num orelse 0,
        info.last_event_action,
        info.event_matched,
        info.has_capture,
    });
    start_y += line_height;
    debugPrintLine(rs, font, color, start_x, start_y, "pointer=({d:0.1},{d:0.1}) hover={s} selected={}", .{
        info.last_pointer.x,
        info.last_pointer.y,
        transform.partName(info.hovered_part),
        info.selected,
    });
    start_y += line_height;
    debugPrintLine(rs, font, color, start_x, start_y, "drag={s} count={d} offset=({d:0.1},{d:0.1})", .{
        transform.partName(info.drag_part),
        info.drag_apply_count,
        info.drag_offset.x,
        info.drag_offset.y,
    });
    start_y += line_height;
    debugPrintLine(rs, font, color, start_x, start_y, "rect=({d:0.1},{d:0.1},{d:0.1},{d:0.1})", .{
        info.last_rect.x,
        info.last_rect.y,
        info.last_rect.w,
        info.last_rect.h,
    });
    start_y += line_height;
    debugPrintLine(rs, font, color, start_x, start_y, "interaction=({d:0.1},{d:0.1},{d:0.1},{d:0.1})", .{
        info.interaction_rect.x,
        info.interaction_rect.y,
        info.interaction_rect.w,
        info.interaction_rect.h,
    });
}

fn debugPrintLine(
    rs: RectScale,
    font: dvui.Font,
    color: Color,
    x: f32,
    y: f32,
    comptime fmt: []const u8,
    args: anytype,
) void {
    var buf: [192]u8 = undefined;
    const text_slice = std.fmt.bufPrint(&buf, fmt, args) catch return;
    const text_rect = Rect.Physical{
        .x = x,
        .y = y,
        .w = debug_overlay_width * rs.s,
        .h = font.size * font.line_height_factor * rs.s,
    };
    dvui.renderText(.{
        .font = font,
        .text = text_slice,
        .rs = RectScale{ .r = text_rect, .s = rs.s },
        .color = color,
    }) catch {};
}

test {
    @import("std").testing.refAllDecls(@This());
}
