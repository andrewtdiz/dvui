const std = @import("std");
const dvui = @import("../dvui.zig");

const Options = dvui.Options;
const Rect = dvui.Rect;
const RectScale = dvui.RectScale;
const Size = dvui.Size;
const Widget = dvui.Widget;
const WidgetData = dvui.WidgetData;

const FlexBoxWidget = @This();

const Orientation = struct {
    dir: dvui.enums.Direction,

    fn mainSize(self: Orientation, size: Size) f32 {
        return switch (self.dir) {
            .horizontal => size.w,
            .vertical => size.h,
        };
    }

    fn crossSize(self: Orientation, size: Size) f32 {
        return switch (self.dir) {
            .horizontal => size.h,
            .vertical => size.w,
        };
    }

    fn setMainSize(self: Orientation, size: *Size, value: f32) void {
        switch (self.dir) {
            .horizontal => size.w = value,
            .vertical => size.h = value,
        }
    }

    fn setCrossSize(self: Orientation, size: *Size, value: f32) void {
        switch (self.dir) {
            .horizontal => size.h = value,
            .vertical => size.w = value,
        }
    }

    fn addMainOffset(self: Orientation, rect: *Rect, offset: f32) void {
        switch (self.dir) {
            .horizontal => rect.x += offset,
            .vertical => rect.y += offset,
        }
    }

    fn addCrossOffset(self: Orientation, rect: *Rect, offset: f32) void {
        switch (self.dir) {
            .horizontal => rect.y += offset,
            .vertical => rect.x += offset,
        }
    }

    fn advancePointMain(self: Orientation, pt: *dvui.Point, delta: f32) void {
        switch (self.dir) {
            .horizontal => pt.x += delta,
            .vertical => pt.y += delta,
        }
    }

    fn advancePointCross(self: Orientation, pt: *dvui.Point, delta: f32) void {
        switch (self.dir) {
            .horizontal => pt.y += delta,
            .vertical => pt.x += delta,
        }
    }

    fn setMainPosition(self: Orientation, pt: *dvui.Point, value: f32) void {
        switch (self.dir) {
            .horizontal => pt.x = value,
            .vertical => pt.y = value,
        }
    }

    fn setCrossPosition(self: Orientation, pt: *dvui.Point, value: f32) void {
        switch (self.dir) {
            .horizontal => pt.y = value,
            .vertical => pt.x = value,
        }
    }

    fn mainPosition(self: Orientation, pt: dvui.Point) f32 {
        return switch (self.dir) {
            .horizontal => pt.x,
            .vertical => pt.y,
        };
    }

    fn crossPosition(self: Orientation, pt: dvui.Point) f32 {
        return switch (self.dir) {
            .horizontal => pt.y,
            .vertical => pt.x,
        };
    }

    fn defaultCrossGravity(self: Orientation, g: Options.Gravity) bool {
        return switch (self.dir) {
            .horizontal => g.y == 0,
            .vertical => g.x == 0,
        };
    }

    fn containerMain(self: Orientation, rect: Rect) f32 {
        return switch (self.dir) {
            .horizontal => rect.w,
            .vertical => rect.h,
        };
    }

    fn containerCross(self: Orientation, rect: Rect) f32 {
        return switch (self.dir) {
            .horizontal => rect.h,
            .vertical => rect.w,
        };
    }

    fn setContainerMain(self: Orientation, rect: *Rect, value: f32) void {
        switch (self.dir) {
            .horizontal => rect.w = value,
            .vertical => rect.h = value,
        }
    }

    fn setContainerCross(self: Orientation, rect: *Rect, value: f32) void {
        switch (self.dir) {
            .horizontal => rect.h = value,
            .vertical => rect.w = value,
        }
    }
};

pub const InitOptions = struct {
    direction: dvui.enums.Direction = .horizontal,
    /// Imitates `justify-content` in CSS Flexbox.
    justify_content: ContentPosition = .center,
    /// Imitates `align-items` in CSS Flexbox for row alignment.
    align_items: AlignItems = .start,
    /// Aligns the set of lines within the container (CSS `align-content`).
    align_content: AlignContent = .start,
};

pub const ContentPosition = enum { start, center, end, between, around };

pub const AlignItems = enum { start, center, end };

pub const AlignContent = enum { start, center, end };

wd: WidgetData,
init_options: InitOptions,
direction: dvui.enums.Direction,
/// SAFETY: Set by `install`
prevClip: Rect.Physical = undefined,
insert_pt: dvui.Point = .{},
current_line_size: Size = .{},
curr_line_main_max: f32 = 0.0,
prev_line_main_max: f32 = 0.0,
main_size_without_wrap: f32 = 0.0,
current_line_index: usize = 0,
/// Cached per-line cross maxima from the previous frame. `rectFor` must respond immediately, so alignment is smoothed across frames using this data.
prev_line_cross_max: []const f32 = &[_]f32{},
curr_line_cross_max: std.ArrayListUnmanaged(f32) = .{},
prev_line_item_count: []const u32 = &[_]u32{},
curr_line_item_count: std.ArrayListUnmanaged(u32) = .{},
prev_line_main_total: []const f32 = &[_]f32{},
curr_line_main_total: std.ArrayListUnmanaged(f32) = .{},
pending_line_index: usize = 0,
has_pending_line: bool = false,
arena: std.mem.Allocator = undefined,
allocation_failed: bool = false,
cross_offset_applied: bool = false,
current_line_item_index: usize = 0,

pub fn init(src: std.builtin.SourceLocation, init_opts: InitOptions, opts: Options) FlexBoxWidget {
    const defaults = Options{ .name = "FlexBox" };
    var self = FlexBoxWidget{
        .wd = WidgetData.init(src, .{}, defaults.override(opts)),
        .init_options = init_opts,
        .direction = init_opts.direction,
    };
    self.restoreCachedMetrics();
    self.arena = dvui.currentWindow().arena();
    return self;
}

fn restoreCachedMetrics(self: *FlexBoxWidget) void {
    const stored_dir = dvui.dataGet(null, self.wd.id, "_line_dir", dvui.enums.Direction);
    if (stored_dir) |dir_prev| {
        if (dir_prev != self.direction) return;
    }

    if (dvui.dataGet(null, self.wd.id, "_line_main", f32)) |lm| {
        self.prev_line_main_max = lm;
    } else if (dvui.dataGet(null, self.wd.id, "_mrw", f32)) |legacy| {
        self.prev_line_main_max = legacy;
    }
    if (dvui.dataGetSlice(null, self.wd.id, "_line_cross", []f32)) |line_cross| {
        self.prev_line_cross_max = line_cross;
    } else if (dvui.dataGetSlice(null, self.wd.id, "_row_heights", []f32)) |row_heights| {
        self.prev_line_cross_max = row_heights;
    }
    if (dvui.dataGetSlice(null, self.wd.id, "_line_items", []u32)) |line_counts| {
        self.prev_line_item_count = line_counts;
    }
    if (dvui.dataGetSlice(null, self.wd.id, "_line_main_arr", []f32)) |line_mains| {
        self.prev_line_main_total = line_mains;
    }
}

fn ensureLineState(self: *FlexBoxWidget, line_index: usize) bool {
    if (self.allocation_failed) return false;
    const arena = self.arena;
    while (self.curr_line_item_count.items.len <= line_index) {
        self.curr_line_item_count.append(arena, 0) catch |err| {
            self.allocation_failed = true;
            dvui.logError(@src(), err, "FlexBoxWidget: unable to grow line item cache", .{});
            return false;
        };
    }
    while (self.curr_line_cross_max.items.len <= line_index) {
        self.curr_line_cross_max.append(arena, 0) catch |err| {
            self.allocation_failed = true;
            dvui.logError(@src(), err, "FlexBoxWidget: unable to grow line cross cache", .{});
            return false;
        };
    }
    while (self.curr_line_main_total.items.len <= line_index) {
        self.curr_line_main_total.append(arena, 0) catch |err| {
            self.allocation_failed = true;
            dvui.logError(@src(), err, "FlexBoxWidget: unable to grow line main cache", .{});
            return false;
        };
    }
    return true;
}

fn recordLineCross(self: *FlexBoxWidget, line_index: usize, cross_size: f32) void {
    if (self.allocation_failed) return;
    if (!self.ensureLineState(line_index)) return;
    self.curr_line_cross_max.items[line_index] = @max(self.curr_line_cross_max.items[line_index], cross_size);
}

fn resetLineCross(self: *FlexBoxWidget, line_index: usize) void {
    if (self.allocation_failed) return;
    if (!self.ensureLineState(line_index)) return;
    self.curr_line_cross_max.items[line_index] = 0;
    self.curr_line_item_count.items[line_index] = 0;
    self.curr_line_main_total.items[line_index] = 0;
}

fn prevLineCross(self: *FlexBoxWidget, line_index: usize, fallback: f32) f32 {
    return if (line_index < self.prev_line_cross_max.len) self.prev_line_cross_max[line_index] else fallback;
}

fn prevLineItemCount(self: *FlexBoxWidget, line_index: usize) u32 {
    return if (line_index < self.prev_line_item_count.len) self.prev_line_item_count[line_index] else 0;
}

fn prevLineMain(self: *FlexBoxWidget, line_index: usize, fallback: f32) f32 {
    if (line_index < self.prev_line_main_total.len) return self.prev_line_main_total[line_index];
    if (self.prev_line_main_max != 0) return self.prev_line_main_max;
    return fallback;
}

fn prevTotalCross(self: *FlexBoxWidget) f32 {
    var total: f32 = 0;
    for (self.prev_line_cross_max) |v| total += v;
    return total;
}

pub fn install(self: *FlexBoxWidget) void {
    self.data().register();
    dvui.parentSet(self.widget());

    self.arena = dvui.currentWindow().arena();
    self.prevClip = dvui.clip(self.data().contentRectScale().r);
}

pub fn drawBackground(self: *FlexBoxWidget) void {
    const clip = dvui.clipGet();
    dvui.clipSet(self.prevClip);
    self.data().borderAndBackground(.{});
    dvui.clipSet(clip);
}

pub fn widget(self: *FlexBoxWidget) Widget {
    return Widget.init(self, data, rectFor, screenRectScale, minSizeForChild);
}

pub fn data(self: *FlexBoxWidget) *WidgetData {
    return self.wd.validate();
}

pub fn rectFor(self: *FlexBoxWidget, id: dvui.Id, min_size: Size, e: Options.Expand, g: Options.Gravity) Rect {
    _ = id;
    _ = e;

    const orient: Orientation = .{ .dir = self.direction };
    var container = self.data().contentRect();
    const opts = self.data().options;
    if (orient.containerMain(container) == 0) {
        var fallback = orient.mainSize(opts.min_size_contentGet());
        if (fallback == 0) fallback = 500;
        orient.setContainerMain(&container, fallback);
    }
    if (orient.containerCross(container) == 0) {
        var fallback = orient.crossSize(opts.min_size_contentGet());
        if (fallback == 0) fallback = 500;
        orient.setContainerCross(&container, fallback);
    }

    const child_main = orient.mainSize(min_size);
    const child_cross = orient.crossSize(min_size);

    if (!self.cross_offset_applied) {
        self.cross_offset_applied = true;
        const total_cross_prev = self.prevTotalCross();
        const container_cross = orient.containerCross(container);
        const leftover_total = @max(@as(f32, 0), container_cross - total_cross_prev);
        const offset = switch (self.init_options.align_content) {
            .start => @as(f32, 0),
            .center => leftover_total / 2,
            .end => leftover_total,
        };
        orient.setCrossPosition(&self.insert_pt, offset);
    }

    if (orient.mainPosition(self.insert_pt) > 0 and orient.mainPosition(self.insert_pt) + child_main > orient.containerMain(container)) {
        const previous_cross = orient.crossSize(self.current_line_size);
        orient.setMainPosition(&self.insert_pt, 0);
        orient.advancePointCross(&self.insert_pt, previous_cross);
        self.current_line_index += 1;
        self.current_line_size = .{};
        self.current_line_item_index = 0;
    }

    self.pending_line_index = self.current_line_index;
    self.has_pending_line = true;
    if (!self.allocation_failed and orient.mainSize(self.current_line_size) == 0) {
        self.resetLineCross(self.current_line_index);
    }

    if (child_cross > orient.crossSize(self.current_line_size)) {
        orient.setCrossSize(&self.current_line_size, child_cross);
    }

    var ret = Rect.fromPoint(self.insert_pt).toSize(min_size);
    const line_main_prev = self.prevLineMain(self.current_line_index, orient.mainSize(self.current_line_size));
    const leftover_main = @max(@as(f32, 0), orient.containerMain(container) - line_main_prev);
    const prev_count = self.prevLineItemCount(self.current_line_index);
    const idx_f = @as(f32, @floatFromInt(self.current_line_item_index));
    const offset_main = switch (self.init_options.justify_content) {
        .start => @as(f32, 0),
        .center => leftover_main / 2,
        .end => leftover_main,
        .between => blk: {
            if (prev_count <= 1) break :blk 0;
            const spacing = leftover_main / @as(f32, @floatFromInt(prev_count - 1));
            break :blk spacing * idx_f;
        },
        .around => blk: {
            if (prev_count == 0) break :blk 0;
            const spacing = leftover_main / @as(f32, @floatFromInt(prev_count));
            break :blk spacing * idx_f + spacing / 2;
        },
    };
    orient.addMainOffset(&ret, offset_main);

    if (!self.allocation_failed and self.init_options.align_items != .start and orient.defaultCrossGravity(g)) {
        const fallback_cross = orient.crossSize(self.current_line_size);
        const line_cross_prev = self.prevLineCross(self.current_line_index, fallback_cross);
        const container_cross = orient.containerCross(container);
        const baseline_cross = if (self.current_line_index == 0 and orient.crossPosition(self.insert_pt) == 0)
            @max(line_cross_prev, container_cross)
        else
            line_cross_prev;
        const leftover = baseline_cross - child_cross;
        if (leftover > 0) switch (self.init_options.align_items) {
            .start => {},
            .center => orient.addCrossOffset(&ret, leftover / 2),
            .end => orient.addCrossOffset(&ret, leftover),
        };
    }

    orient.advancePointMain(&self.insert_pt, child_main);
    self.current_line_item_index += 1;

    return ret;
}

pub fn screenRectScale(self: *FlexBoxWidget, rect: Rect) RectScale {
    return self.data().contentRectScale().rectToRectScale(rect);
}

pub fn minSizeForChild(self: *FlexBoxWidget, s: Size) void {
    const orient: Orientation = .{ .dir = self.direction };

    if (!self.allocation_failed and self.has_pending_line) {
        self.recordLineCross(self.pending_line_index, orient.crossSize(s));
        if (!self.allocation_failed and self.ensureLineState(self.pending_line_index)) {
            self.curr_line_item_count.items[self.pending_line_index] += 1;
            self.curr_line_main_total.items[self.pending_line_index] = orient.mainSize(self.current_line_size);
        }
    }
    self.has_pending_line = false;

    const child_main = orient.mainSize(s);
    const child_cross = orient.crossSize(s);

    orient.setMainSize(&self.current_line_size, orient.mainSize(self.current_line_size) + child_main);
    if (child_cross > orient.crossSize(self.current_line_size)) {
        orient.setCrossSize(&self.current_line_size, child_cross);
    }

    self.curr_line_main_max = @max(self.curr_line_main_max, orient.mainSize(self.current_line_size));
    self.main_size_without_wrap += child_main;

    const cross_total = orient.crossPosition(self.insert_pt) + orient.crossSize(self.current_line_size);
    var new_min = switch (self.direction) {
        .horizontal => Size{
            .w = self.main_size_without_wrap,
            .h = cross_total,
        },
        .vertical => Size{
            .w = cross_total,
            .h = self.main_size_without_wrap,
        },
    };
    const option_min = self.data().options.min_size_contentGet();
    const option_max = self.data().options.max_size_contentGet();
    new_min.w = @max(new_min.w, option_min.w);
    new_min.h = @max(new_min.h, option_min.h);
    new_min.w = @min(new_min.w, option_max.w);
    new_min.h = @min(new_min.h, option_max.h);
    self.data().min_size = self.data().options.padSize(new_min);
}

pub fn deinit(self: *FlexBoxWidget) void {
    const should_free = self.data().was_allocated_on_widget_stack;
    defer if (should_free) dvui.widgetFree(self);
    defer self.* = undefined;
    if (!self.allocation_failed) {
        // Persist current frame metrics so the next frame can align immediately despite the single-pass layout contract.
        dvui.dataSetSlice(null, self.data().id, "_line_cross", self.curr_line_cross_max.items);
        dvui.dataSet(null, self.data().id, "_line_main", self.curr_line_main_max);
        dvui.dataSet(null, self.data().id, "_line_dir", self.direction);
        dvui.dataSetSlice(null, self.data().id, "_line_items", self.curr_line_item_count.items);
        // Legacy keys kept for backwards compatibility with existing cached layouts.
        dvui.dataSetSlice(null, self.data().id, "_row_heights", self.curr_line_cross_max.items);
        dvui.dataSet(null, self.data().id, "_mrw", self.curr_line_main_max);
    } else {
        const empty_f32: [0]f32 = .{};
        const empty_u32: [0]u32 = .{};
        dvui.dataSetSlice(null, self.data().id, "_line_cross", empty_f32[0..]);
        dvui.dataSet(null, self.data().id, "_line_main", @as(f32, 0));
        dvui.dataSet(null, self.data().id, "_line_dir", self.direction);
        dvui.dataSetSlice(null, self.data().id, "_line_items", empty_u32[0..]);
        dvui.dataSetSlice(null, self.data().id, "_row_heights", empty_f32[0..]);
        dvui.dataSet(null, self.data().id, "_mrw", @as(f32, 0));
    }
    dvui.clipSet(self.prevClip);
    self.data().minSizeSetAndRefresh();
    self.data().minSizeReportToParent();
    dvui.parentReset(self.data().id, self.data().parent);
}

test {
    @import("std").testing.refAllDecls(@This());
}
