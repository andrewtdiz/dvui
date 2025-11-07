const std = @import("std");

const dvui = @import("../dvui.zig");
const Color = dvui.Color;
const Options = dvui.Options;
const Point = dvui.Point;
const Rect = dvui.Rect;
const RectScale = dvui.RectScale;
const Size = dvui.Size;
const Widget = dvui.Widget;
const WidgetData = dvui.WidgetData;

const transform = @import("SelectionWidget/transform.zig");
const drawing = @import("SelectionWidget/drawing.zig");
const events_module = @import("SelectionWidget/events.zig");

pub const SelectionDragPart = transform.SelectionDragPart;
pub const DragTransform = transform.DragTransform;

const SelectionWidget = @This();

const defaults: Options = .{
    .name = "SelectionWidget",
    .background = false,
    .border = Rect.all(0),
    .corner_radius = Rect.all(0),
};

pub const State = struct {
    rect: Rect,
    rotation: f32 = 0.0,
    hovered: bool = false,
    selected: bool = false,
};

pub const TransformModifiers = struct {
    proportional: bool = true,
    centered: bool = false,
    fixed_increment: bool = false,
    scale_increment: f32 = 10.0,
    rotation_increment: f32 = std.math.pi / 4.0,
};

pub const InitOptions = struct {
    state: *State,
    min_size: Size = .{ .w = 60, .h = 60 },
    can_move: bool = true,
    can_resize: bool = true,
    can_rotate: bool = true,
    color_fill: ?Color = null,
    color_border: ?Color = null,
    handle_color_fill: ?Color = null,
    handle_color_border: ?Color = null,
    debug_overlay: bool = false,
    debug_logging: bool = false,
    transform_modifiers: TransformModifiers = .{},
};

const DebugInfo = struct {
    last_event_num: ?u16 = null,
    last_event_action: []const u8 = "none",
    last_pointer: Point.Physical = .{},
    event_matched: bool = false,
    has_capture: bool = false,
    hovered_part: ?SelectionDragPart = null,
    drag_part: ?SelectionDragPart = null,
    drag_offset: Point.Physical = .{},
    drag_apply_count: u32 = 0,
    last_rect: Rect = .{},
    interaction_rect: Rect.Physical = .{},
    selected: bool = false,
    hover_state: bool = false,
};

const RuntimeState = struct {
    drag_part: ?SelectionDragPart = null,
    drag_origin_rect: Rect = .{},
    drag_origin_anchor: Point = .{},
    drag_pointer_origin: Point = .{},
    drag_pointer_origin_phys: Point.Physical = .{},
    pointer_current_phys: Point.Physical = .{},
    drag_offset: Point.Physical = .{},
    drag_transform: ?DragTransform = null,
    hover_part: ?SelectionDragPart = null,
    drag_origin_angle: f32 = 0,
    drag_origin_rotation: f32 = 0,
    rotation_center_phys: Point.Physical = .{},
    drag_aspect_ratio: f32 = 1.0,
    resize_pivot_world: Point = .{},
    resize_pivot_part: ?SelectionDragPart = null,
    resize_pivot_world_handle: Point = .{},
    resize_pivot_world_center: Point = .{},
    resize_pivot_is_center: bool = false,
    debug_info: DebugInfo = .{},
};

wd: WidgetData,
init_opts: InitOptions,
state: *State,
runtime: *RuntimeState = undefined,
selection_activation_event: ?u16 = null,

pub fn init(src: std.builtin.SourceLocation, init_options: InitOptions, opts: Options) SelectionWidget {
    return .{
        .wd = WidgetData.init(src, .{}, defaults.override(opts)),
        .init_opts = init_options,
        .state = init_options.state,
    };
}

pub fn install(self: *SelectionWidget) void {
    self.runtime = dvui.dataGetPtrDefault(null, self.data().id, "_runtime", RuntimeState, .{});
    self.runtime.debug_info.last_rect = self.state.rect;
    self.runtime.debug_info.selected = self.state.selected;
    self.runtime.debug_info.hover_state = self.state.hovered;
    self.syncWidgetRect();
    self.data().register();
    dvui.parentSet(self.widget());
}

pub fn processEvents(self: *SelectionWidget) void {
    events_module.process(self);
}

pub fn draw(self: *SelectionWidget) void {
    drawing.draw(self);
}

pub fn deinit(self: *SelectionWidget) void {
    const should_free = self.data().was_allocated_on_widget_stack;
    defer if (should_free) dvui.widgetFree(self);
    defer self.* = undefined;
    self.data().minSizeSetAndRefresh();
    self.data().minSizeReportToParent();
    dvui.parentReset(self.data().id, self.data().parent);
}

pub fn widget(self: *SelectionWidget) Widget {
    return Widget.init(self, data, rectFor, screenRectScale, minSizeForChild);
}

pub fn data(self: *SelectionWidget) *WidgetData {
    return self.wd.validate();
}

pub fn rectFor(self: *SelectionWidget, _: dvui.Id, min_size: Size, e: Options.Expand, g: Options.Gravity) Rect {
    return dvui.placeIn(self.data().contentRect().justSize(), min_size, e, g);
}

pub fn screenRectScale(self: *SelectionWidget, rect: Rect) RectScale {
    return self.data().contentRectScale().rectToRectScale(rect);
}

pub fn minSizeForChild(self: *SelectionWidget, s: Size) void {
    self.data().minSizeMax(self.data().options.padSize(s));
}

pub fn pointToSelectionSpaceDuringDrag(self: *SelectionWidget, p: Point.Physical) Point {
    if (self.runtime.drag_transform) |drag_transform| {
        return transform.pointToSelectionSpaceWithTransform(drag_transform, p);
    }
    const rs = self.data().borderRectScale();
    return transform.pointToSelectionSpace(self.state.rect, self.state.rotation, rs, p);
}

pub fn syncWidgetRect(self: *SelectionWidget) void {
    const rect = self.state.rect;
    var wd_ref = self.data();
    wd_ref.rect = rect;
    wd_ref.options.rect = rect;
    wd_ref.rect_scale = wd_ref.rectScaleFromParent();
}

test {
    @import("std").testing.refAllDecls(@This());
}
