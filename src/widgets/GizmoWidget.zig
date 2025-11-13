const std = @import("std");
const dvui = @import("../dvui.zig");

const Color = dvui.Color;
const Options = dvui.Options;
const Point = dvui.Point;
const Rect = dvui.Rect;
const RectScale = dvui.RectScale;
const Size = dvui.Size;
const Path = dvui.Path;
const Widget = dvui.Widget;
const WidgetData = dvui.WidgetData;

const GizmoWidget = @This();

const defaults: Options = .{
    .name = "GizmoWidget",
    .background = false,
    .border = Rect.all(0),
    .corner_radius = Rect.all(0),
    .padding = Rect.all(0),
};

pub const Axis = enum { horizontal, vertical };

const Handle = union(enum) {
    axis: Axis,
    center,
};

pub const State = struct {
    rect: Rect = .{ .x = 120, .y = 120, .w = 120, .h = 120 },
};

pub const Colors = struct {
    horizontal: Color = Color.red,
    vertical: Color = Color.green.lighten(25),
    center: Color = .{ .r = 40, .g = 120, .b = 210, .a = 255 },
    highlight_mix: f32 = 0.35,
};

pub const InitOptions = struct {
    state: *State,
    min_extent: Size = .{ .w = 120, .h = 120 },
    axis_length: f32 = 150,
    axis_thickness: f32 = 3,
    handle_size: f32 = 10,
    colors: Colors = .{},
};

const Runtime = struct {
    hover: ?Handle = null,
    drag: ?Handle = null,
};

const AxisShape = struct {
    axis: Axis,
    shaft: Rect.Physical,
    hit: Rect.Physical,
    tip: ArrowTip,
};

const ArrowTip = struct {
    tip: Point.Physical,
    base_a: Point.Physical,
    base_b: Point.Physical,

    fn fill(self: ArrowTip, color: Color) void {
        var builder = Path.Builder.init(dvui.currentWindow().lifo());
        defer builder.deinit();
        builder.addPoint(self.tip);
        builder.addPoint(self.base_a);
        builder.addPoint(self.base_b);
        builder.addPoint(self.tip);
        builder.build().fillConvex(.{ .color = color });
    }

    fn bounds(self: ArrowTip) Rect.Physical {
        const min_x = @min(self.tip.x, @min(self.base_a.x, self.base_b.x));
        const max_x = @max(self.tip.x, @max(self.base_a.x, self.base_b.x));
        const min_y = @min(self.tip.y, @min(self.base_a.y, self.base_b.y));
        const max_y = @max(self.tip.y, @max(self.base_a.y, self.base_b.y));
        return .{ .x = min_x, .y = min_y, .w = @max(0, max_x - min_x), .h = @max(0, max_y - min_y) };
    }

    fn scaled(self: ArrowTip, factor: f32) ArrowTip {
        if (factor == 1.0) return self;
        const scalePoint = struct {
            fn apply(tip: Point.Physical, base: Point.Physical, f: f32) Point.Physical {
                return .{
                    .x = tip.x + (base.x - tip.x) * f,
                    .y = tip.y + (base.y - tip.y) * f,
                };
            }
        }.apply;
        return .{
            .tip = self.tip,
            .base_a = scalePoint(self.tip, self.base_a, factor),
            .base_b = scalePoint(self.tip, self.base_b, factor),
        };
    }
};

const Geometry = struct {
    scale: RectScale,
    center: Point.Physical,
    center_box: Rect.Physical,
    horizontal: AxisShape,
    vertical: AxisShape,
};

wd: WidgetData,
init_opts: InitOptions,
state: *State,
runtime: *Runtime = undefined,

pub fn init(src: std.builtin.SourceLocation, init_opts: InitOptions, opts: Options) GizmoWidget {
    return .{
        .wd = WidgetData.init(src, .{}, defaults.override(opts)),
        .init_opts = init_opts,
        .state = init_opts.state,
    };
}

pub fn install(self: *GizmoWidget) void {
    self.runtime = dvui.dataGetPtrDefault(null, self.data().id, "_runtime", Runtime, .{});
    self.ensureRectBounds();
    self.syncWidgetRect();
    self.data().register();
    dvui.parentSet(self.widget());
}

pub fn processEvents(self: *GizmoWidget) void {
    var geom = self.geometry();
    self.runtime.hover = null;

    for (dvui.events()) |*event| {
        if (!dvui.eventMatchSimple(event, self.data())) continue;
        switch (event.evt) {
            .mouse => |mouse| switch (mouse.action) {
                .press => {
                    if (!mouse.button.pointer()) break;
                    if (self.hitTest(geom, mouse.p)) |handle| {
                        event.handle(@src(), self.data());
                        dvui.captureMouse(self.data(), event.num);
                        dvui.dragPreStart(mouse.p, .{ .cursor = .hand });
                        self.runtime.drag = handle;
                    }
                },
                .release => {
                    if (!mouse.button.pointer()) break;
                    if (dvui.captured(self.data().id)) {
                        event.handle(@src(), self.data());
                        dvui.captureMouse(null, event.num);
                        dvui.dragEnd();
                        self.runtime.drag = null;
                    }
                },
                .motion => {
                    if (!dvui.captured(self.data().id)) continue;
                    if (self.runtime.drag) |handle| {
                        if (dvui.dragging(mouse.p, null)) |delta| {
                            event.handle(@src(), self.data());
                            if (self.applyDelta(handle, delta, geom.scale)) {
                                dvui.refresh(null, @src(), self.data().id);
                                geom = self.geometry();
                            }
                        }
                    }
                },
                .position => {
                    const hovered = self.hitTest(geom, mouse.p);
                    self.runtime.hover = hovered;
                    if (hovered) |_| dvui.cursorSet(.hand);
                },
                else => {},
            },
            else => {},
        }
    }

    if ((self.runtime.drag != null) or (self.runtime.hover != null)) {
        dvui.cursorSet(.hand);
    }
}

pub fn draw(self: *GizmoWidget) void {
    const geom = self.geometry();
    self.drawCenterBox(geom);
    self.drawAxis(geom.horizontal);
    self.drawAxis(geom.vertical);
}

pub fn deinit(self: *GizmoWidget) void {
    const free_me = self.data().was_allocated_on_widget_stack;
    defer if (free_me) dvui.widgetFree(self);
    defer self.* = undefined;
    self.data().minSizeSetAndRefresh();
    self.data().minSizeReportToParent();
    dvui.parentReset(self.data().id, self.data().parent);
}

pub fn widget(self: *GizmoWidget) Widget {
    return Widget.init(self, data, rectFor, screenRectScale, minSizeForChild);
}

pub fn data(self: *GizmoWidget) *WidgetData {
    return self.wd.validate();
}

pub fn rectFor(self: *GizmoWidget, _: dvui.Id, min_size: Size, e: Options.Expand, g: Options.Gravity) Rect {
    return dvui.placeIn(self.data().contentRect().justSize(), min_size, e, g);
}

pub fn screenRectScale(self: *GizmoWidget, rect: Rect) RectScale {
    return self.data().contentRectScale().rectToRectScale(rect);
}

pub fn minSizeForChild(self: *GizmoWidget, s: Size) void {
    self.data().minSizeMax(self.data().options.padSize(s));
}

fn syncWidgetRect(self: *GizmoWidget) void {
    var wd_ref = self.data();
    wd_ref.rect = self.state.rect;
    wd_ref.options.rect = self.state.rect;
    wd_ref.rect_scale = wd_ref.rectScaleFromParent();
}

fn geometry(self: *GizmoWidget) Geometry {
    const rs = self.data().borderRectScale();
    const center = Point.Physical{ .x = rs.r.x + rs.r.w / 2, .y = rs.r.y + rs.r.h / 2 };
    const center_size = @max(self.init_opts.handle_size * rs.s * 4.5, 48.0);
    const center_box = Rect.Physical{ .x = center.x, .y = center.y - center_size, .w = center_size, .h = center_size };
    return .{
        .scale = rs,
        .center = center,
        .center_box = center_box,
        .horizontal = self.buildAxis(.horizontal, rs, center),
        .vertical = self.buildAxis(.vertical, rs, center),
    };
}

fn buildAxis(self: *GizmoWidget, axis: Axis, rs: RectScale, center: Point.Physical) AxisShape {
    const length_px = @max(self.init_opts.axis_length * rs.s, 1.0);
    const thickness = @max(self.init_opts.axis_thickness * rs.s, 1.0);
    const tip_len = @max(self.init_opts.handle_size * rs.s * 1.8, thickness * 1.5);
    const tip_half = @max(tip_len * 0.35, thickness * 0.6);
    const shaft_len = @max(length_px - tip_len, thickness * 0.25);
    const hit_padding = 12;

    return switch (axis) {
        .horizontal => blk: {
            const start = center.x;
            const shaft = Rect.Physical{ .x = start, .y = center.y - thickness / 2, .w = shaft_len, .h = thickness };
            const tip = ArrowTip{
                .tip = .{ .x = start + length_px, .y = center.y },
                .base_a = .{ .x = start + length_px - tip_len, .y = center.y - tip_half },
                .base_b = .{ .x = start + length_px - tip_len, .y = center.y + tip_half },
            };
            var hit = shaft.insetAll(-hit_padding);
            hit = hit.unionWith(tip.bounds());
            break :blk .{ .axis = axis, .shaft = shaft, .hit = hit, .tip = tip };
        },
        .vertical => blk: {
            const shaft = Rect.Physical{ .x = center.x - thickness / 2, .y = center.y - shaft_len, .w = thickness, .h = shaft_len };
            const tip = ArrowTip{
                .tip = .{ .x = center.x, .y = center.y - length_px },
                .base_a = .{ .x = center.x - tip_half, .y = center.y - length_px + tip_len },
                .base_b = .{ .x = center.x + tip_half, .y = center.y - length_px + tip_len },
            };
            var hit = shaft.insetAll(-hit_padding);
            hit = hit.unionWith(tip.bounds());
            break :blk .{ .axis = axis, .shaft = shaft, .hit = hit, .tip = tip };
        },
    };
}

fn ensureRectBounds(self: *GizmoWidget) void {
    const span = (self.init_opts.axis_length + self.init_opts.handle_size) * 2;
    if (self.state.rect.w < span) self.state.rect.w = span;
    if (self.state.rect.h < span) self.state.rect.h = span;
}

fn applyDelta(self: *GizmoWidget, handle: Handle, delta: Point.Physical, rs: RectScale) bool {
    const inv = if (rs.s == 0) 1.0 else 1.0 / rs.s;
    var moved = false;
    switch (handle) {
        .axis => |axis| switch (axis) {
            .horizontal => {
                const dx = delta.x * inv;
                if (dx != 0) { self.state.rect.x += dx; moved = true; }
            },
            .vertical => {
                const dy = delta.y * inv;
                if (dy != 0) { self.state.rect.y += dy; moved = true; }
            },
        },
        .center => {
            const dx = delta.x * inv;
            const dy = delta.y * inv;
            if (dx != 0 or dy != 0) {
                self.state.rect.x += dx;
                self.state.rect.y += dy;
                moved = true;
            }
        },
    }
    if (moved) self.syncWidgetRect();
    return moved;
}

fn drawAxis(self: *GizmoWidget, axis_shape: AxisShape) void {
    const highlighted = self.handleIsAxis(self.runtime.drag, axis_shape.axis) or self.handleIsAxis(self.runtime.hover, axis_shape.axis);
    const color = self.axisColor(axis_shape.axis, highlighted);
    axis_shape.hit.fill(.all(0), .{ .color = color.opacity(0) });

    const base_thickness = if (axis_shape.axis == .horizontal) axis_shape.shaft.h else axis_shape.shaft.w;
    const target_thickness = if (highlighted) base_thickness * 2 else base_thickness;
    var shaft_rect = axis_shape.shaft;
    if (axis_shape.axis == .horizontal) {
        const grow = (target_thickness - shaft_rect.h) / 2;
        shaft_rect.y -= grow;
        shaft_rect.h = target_thickness;
    } else {
        const grow = (target_thickness - shaft_rect.w) / 2;
        shaft_rect.x -= grow;
        shaft_rect.w = target_thickness;
    }

    const opacity: f32 = if (highlighted) 1.0 else 0.75;
    shaft_rect.fill(Rect.Physical.all(0), .{ .color = color.opacity(opacity) });
    const tip_shape = if (highlighted) axis_shape.tip.scaled(2.0) else axis_shape.tip;
    tip_shape.fill(color.opacity(opacity));
}

fn drawCenterBox(self: *GizmoWidget, geom: Geometry) void {
    const active = self.handleIsCenter(self.runtime.drag) or self.handleIsCenter(self.runtime.hover);
    const fill = if (active) self.init_opts.colors.center.opacity(0.45) else self.init_opts.colors.center.opacity(0.2);
    var box = geom.center_box;
    if (active) {
        const grow = @max(self.init_opts.handle_size * geom.scale.s * 0.4, 4.0);
        const bottom = box.y + box.h;
        box.w += grow * 2;
        box.h += grow * 2;
        box.y = bottom - box.h;
    }
    box.stroke(Rect.Physical.all(0), .{ .color = self.init_opts.colors.center, .thickness = 1.0 });
    box.fill(Rect.Physical.all(0), .{ .color = fill });
}

fn axisColor(self: *GizmoWidget, axis: Axis, highlight: bool) Color {
    const base = switch (axis) {
        .horizontal => self.init_opts.colors.horizontal,
        .vertical => self.init_opts.colors.vertical,
    };
    return if (highlight)
        base.lerp(Color.white, std.math.clamp(self.init_opts.colors.highlight_mix, 0, 1))
    else
        base;
}

fn hitTest(self: *GizmoWidget, geom: Geometry, p: Point.Physical) ?Handle {
    _ = self;
    if (geom.center_box.contains(p)) return .center;
    if (geom.horizontal.hit.contains(p)) return .{ .axis = .horizontal };
    if (geom.vertical.hit.contains(p)) return .{ .axis = .vertical };
    return null;
}

fn handleIsAxis(self: *GizmoWidget, handle: ?Handle, axis: Axis) bool {
    _ = self;
    if (handle) |h| {
        return switch (h) {
            .axis => |a| a == axis,
            else => false,
        };
    }
    return false;
}

fn handleIsCenter(self: *GizmoWidget, handle: ?Handle) bool {
    _ = self;
    if (handle) |h| {
        return switch (h) {
            .center => true,
            else => false,
        };
    }
    return false;
}

test {
    @import("std").testing.refAllDecls(@This());
}
