const std = @import("std");

const dvui = @import("dvui");

const types = @import("../core/types.zig");
const events = @import("../events/mod.zig");
const layout = @import("../layout/mod.zig");
const image_loader = @import("image_loader.zig");
const icon_registry = @import("icon_registry.zig");
const paint_cache = @import("cache.zig");
const focus = @import("../events/focus.zig");

const interaction = @import("internal/interaction.zig");
const hover = @import("internal/hover.zig");
const renderers = @import("internal/renderers.zig");
const state = @import("internal/state.zig");
const runtime_mod = @import("internal/runtime.zig");

const DirtyRegionTracker = paint_cache.DirtyRegionTracker;

const RenderRuntime = runtime_mod.RenderRuntime;
pub const FrameTimings = runtime_mod.FrameTimings;

var runtime: RenderRuntime = .{};

pub fn init() void {
    runtime.reset();
    focus.init();
    image_loader.init();
    icon_registry.init();
}

pub fn deinit() void {
    focus.deinit();
    image_loader.deinit();
    icon_registry.deinit();
    runtime.reset();
}

fn updateFrameState(runtime_ptr: *RenderRuntime, mouse: dvui.Point.Physical, input_enabled: bool, layer: state.RenderLayer) void {
    runtime_ptr.last_mouse_pt = mouse;
    runtime_ptr.last_input_enabled = input_enabled;
    runtime_ptr.last_hover_layer = layer;
}

pub fn render(event_ring: ?*events.EventRing, store: *types.NodeStore, input_enabled: bool, timings: ?*FrameTimings) bool {
    const root = store.node(0) orelse return false;
    runtime.timings = timings;
    defer runtime.timings = null;
    if (timings) |t| {
        t.* = .{};
    }

    runtime.input_enabled_state = input_enabled;
    var clear_pressed = false;
    focus.beginFrame(store);
    const layout_start_ns = std.time.nanoTimestamp();
    layout.updateLayouts(store);
    if (timings) |t| {
        t.layout_ns += std.time.nanoTimestamp() - layout_start_ns;
    }

    var arena = std.heap.ArenaAllocator.init(store.allocator);
    defer arena.deinit();
    const scratch = arena.allocator();

    const current_mouse = dvui.currentWindow().mouse_pt;
    const root_ctx = state.RenderContext{ .origin = .{ .x = 0, .y = 0 }, .clip = null, .scale = .{ 1, 1 }, .offset = .{ 0, 0 } };
    runtime.render_layer = .base;
    runtime.hover_layer = .base;
    runtime.pointer_top_overlay_id = 0;
    runtime.modal_overlay_active = false;

    if (runtime.input_enabled_state) {
        var pair: interaction.PickPair = .{};
        var order: u32 = 0;
        const hit_start_ns = std.time.nanoTimestamp();
        interaction.scanPickPair(store, root, current_mouse, root_ctx, &pair, &order, false);
        if (timings) |t| {
            t.hit_test_ns += std.time.nanoTimestamp() - hit_start_ns;
        }
        runtime.pointer_top_base_id = pair.interactive.id;

        const hover_start_ns = std.time.nanoTimestamp();
        const hover_layout_invalidated = hover.syncHoverPath(&runtime, event_ring, store, scratch, pair.hover.id);
        if (timings) |t| {
            t.hover_ns += std.time.nanoTimestamp() - hover_start_ns;
        }
        if (hover_layout_invalidated) {
            const layout_retry_start_ns = std.time.nanoTimestamp();
            layout.updateLayouts(store);
            if (timings) |t| {
                t.layout_ns += std.time.nanoTimestamp() - layout_retry_start_ns;
            }

            pair = .{};
            order = 0;
            const hit_retry_start_ns = std.time.nanoTimestamp();
            interaction.scanPickPair(store, root, current_mouse, root_ctx, &pair, &order, false);
            if (timings) |t| {
                t.hit_test_ns += std.time.nanoTimestamp() - hit_retry_start_ns;
            }
            runtime.pointer_top_base_id = pair.interactive.id;
            const hover_retry_start_ns = std.time.nanoTimestamp();
            _ = hover.syncHoverPath(&runtime, event_ring, store, scratch, pair.hover.id);
            if (timings) |t| {
                t.hover_ns += std.time.nanoTimestamp() - hover_retry_start_ns;
            }
        }
    } else {
        runtime.pointer_top_base_id = 0;
        const hover_clear_start_ns = std.time.nanoTimestamp();
        _ = hover.syncHoverPath(&runtime, event_ring, store, scratch, 0);
        if (timings) |t| {
            t.hover_ns += std.time.nanoTimestamp() - hover_clear_start_ns;
        }
    }

    if (runtime.input_enabled_state) {
        const press_target = runtime.pointer_top_base_id;
        for (dvui.events()) |*e| {
            switch (e.evt) {
                .mouse => |me| {
                    switch (me.action) {
                        .press => {
                            if (me.button.pointer()) runtime.pressed_node_id = press_target;
                        },
                        .release => {
                            if (me.button.pointer()) clear_pressed = true;
                        },
                        else => {},
                    }
                },
                else => {},
            }
        }
    }

    if (root.children.items.len == 0) {
        updateFrameState(&runtime, current_mouse, runtime.input_enabled_state, .base);
        return false;
    }

    var dirty_tracker = DirtyRegionTracker.init(scratch);
    defer dirty_tracker.deinit();

    runtime.render_layer = .base;
    const render_start_ns = std.time.nanoTimestamp();
    renderers.renderChildrenOrdered(&runtime, event_ring, store, root, scratch, &dirty_tracker, root_ctx, false);
    if (timings) |t| {
        t.render_ns += std.time.nanoTimestamp() - render_start_ns;
    }

    const focus_start_ns = std.time.nanoTimestamp();
    focus.endFrame(event_ring, store, runtime.input_enabled_state);
    if (timings) |t| {
        t.focus_ns += std.time.nanoTimestamp() - focus_start_ns;
    }
    runtime.render_layer = .base;
    updateFrameState(&runtime, current_mouse, runtime.input_enabled_state, .base);
    if (clear_pressed) {
        runtime.pressed_node_id = 0;
    }
    return true;
}
