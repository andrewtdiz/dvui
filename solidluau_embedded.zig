const std = @import("std");

pub const Module = struct {
    id: []const u8,
    source: []const u8,
};

pub const modules = [_]Module{
    .{ .id = "solidluau", .source = @embedFile("deps/solidluau/src/main.luau") },
    .{ .id = "SolidLuau", .source = @embedFile("deps/solidluau/src/main.luau") },
    .{ .id = "main", .source = @embedFile("deps/solidluau/src/main.luau") },
    .{ .id = "ui", .source = @embedFile("deps/solidluau/src/ui.luau") },
    .{ .id = "ui/index", .source = @embedFile("deps/solidluau/src/ui/index.luau") },
    .{ .id = "ui/dsl", .source = @embedFile("deps/solidluau/src/ui/dsl.luau") },
    .{ .id = "ui/hydrate", .source = @embedFile("deps/solidluau/src/ui/hydrate.luau") },
    .{ .id = "ui/renderer", .source = @embedFile("deps/solidluau/src/ui/renderer.luau") },
    .{ .id = "ui/types", .source = @embedFile("deps/solidluau/src/ui/types.luau") },
    .{ .id = "ui/adapter_types", .source = @embedFile("deps/solidluau/src/ui/adapter_types.luau") },
    .{ .id = "ui/adapters/compat_ui", .source = @embedFile("deps/solidluau/src/ui/adapters/compat_ui.luau") },
    .{ .id = "animation", .source = @embedFile("deps/solidluau/src/animation.luau") },
    .{ .id = "animation/index", .source = @embedFile("deps/solidluau/src/animation/index.luau") },
    .{ .id = "animation/easing", .source = @embedFile("deps/solidluau/src/animation/easing.luau") },
    .{ .id = "animation/spring", .source = @embedFile("deps/solidluau/src/animation/spring.luau") },
    .{ .id = "animation/tween", .source = @embedFile("deps/solidluau/src/animation/tween.luau") },
    .{ .id = "core/reactivity", .source = @embedFile("deps/solidluau/src/core/reactivity.luau") },
    .{ .id = "core/reactivity/index", .source = @embedFile("deps/solidluau/src/core/reactivity/index.luau") },
    .{ .id = "core/reactivity/graph", .source = @embedFile("deps/solidluau/src/core/reactivity/graph.luau") },
    .{ .id = "core/reactivity/scheduler", .source = @embedFile("deps/solidluau/src/core/reactivity/scheduler.luau") },
    .{ .id = "core/reactivity/signal", .source = @embedFile("deps/solidluau/src/core/reactivity/signal.luau") },
    .{ .id = "core/reactivity/effect", .source = @embedFile("deps/solidluau/src/core/reactivity/effect.luau") },
    .{ .id = "core/reactivity/memo", .source = @embedFile("deps/solidluau/src/core/reactivity/memo.luau") },
    .{ .id = "core/reactivity/root", .source = @embedFile("deps/solidluau/src/core/reactivity/root.luau") },
    .{ .id = "core/reactivity/mount", .source = @embedFile("deps/solidluau/src/core/reactivity/mount.luau") },
    .{ .id = "core/reactivity/batch", .source = @embedFile("deps/solidluau/src/core/reactivity/batch.luau") },
    .{ .id = "core/reactivity/untrack", .source = @embedFile("deps/solidluau/src/core/reactivity/untrack.luau") },
    .{ .id = "core/reactivity/cleanup", .source = @embedFile("deps/solidluau/src/core/reactivity/cleanup.luau") },
    .{ .id = "core/reactivity/mergeProps", .source = @embedFile("deps/solidluau/src/core/reactivity/mergeProps.luau") },
    .{ .id = "core/reactivity/splitProps", .source = @embedFile("deps/solidluau/src/core/reactivity/splitProps.luau") },
    .{ .id = "core/renderer", .source = @embedFile("deps/solidluau/src/core/renderer.luau") },
    .{ .id = "core/dsl", .source = @embedFile("deps/solidluau/src/core/dsl.luau") },
    .{ .id = "core/tags", .source = @embedFile("deps/solidluau/src/core/tags.luau") },
    .{ .id = "core/easing", .source = @embedFile("deps/solidluau/src/core/easing.luau") },
    .{ .id = "core/animation", .source = @embedFile("deps/solidluau/src/core/animation.luau") },
    .{ .id = "core/state", .source = @embedFile("deps/solidluau/src/core/state.luau") },
    .{ .id = "example/app", .source = @embedFile("deps/solidluau/src/example/app.luau") },
    .{ .id = "example/state", .source = @embedFile("deps/solidluau/src/example/state.luau") },
};

pub fn get(id: []const u8) ?[]const u8 {
    for (modules) |m| {
        if (std.mem.eql(u8, id, m.id)) return m.source;
    }
    return null;
}

