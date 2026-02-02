const std = @import("std");

const dvui = @import("dvui");
const text_wrap = @import("../layout/text_wrap.zig");
const geometry = @import("geometry.zig");

const Rect = geometry.Rect;
const Size = geometry.Size;

pub const LayoutCache = struct {
    rect: ?Rect = null,
    child_rect: ?Rect = null,
    layout_scale: f32 = 1.0,
    version: u64 = 0,
    intrinsic_size: ?Size = null,
    text_hash: u64 = 0,
    text_layout: text_wrap.LineLayout = .{},
};

pub const PaintCache = struct {
    vertices: std.ArrayList(dvui.Vertex) = .empty,
    indices: std.ArrayList(u16) = .empty,
    version: u64 = 0,
    paint_dirty: bool = true,
    painted_bounds_layout: ?Rect = null,

    pub fn deinit(self: *PaintCache, allocator: std.mem.Allocator) void {
        self.vertices.deinit(allocator);
        self.indices.deinit(allocator);
    }
};
