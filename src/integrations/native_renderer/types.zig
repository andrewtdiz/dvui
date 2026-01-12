const std = @import("std");
const builtin = @import("builtin");

const dvui = @import("dvui");
const RaylibBackend = @import("raylib-backend");
const solid = @import("solid");

// ============================================================
// FFI Callback Types
// ============================================================

pub const LogFn = fn (level: u8, msg_ptr: [*]const u8, msg_len: usize) callconv(.c) void;
pub const EventFn = fn (name_ptr: [*]const u8, name_len: usize, data_ptr: [*]const u8, data_len: usize) callconv(.c) void;

// ============================================================
// Command Header (FFI struct)
// ============================================================

pub const CommandHeader = extern struct {
    opcode: u8,
    flags: u8,
    reserved: u16,
    node_id: u32,
    parent_id: u32,
    x: f32,
    y: f32,
    width: f32,
    height: f32,
    payload_offset: u32,
    payload_size: u32,
    extra: u32,
};

// ============================================================
// Core Renderer State
// ============================================================

pub const Renderer = struct {
    gpa_instance: std.heap.GeneralPurposeAllocator(.{}) = undefined,
    allocator: std.mem.Allocator,
    backend: ?RaylibBackend.RaylibBackend = null,
    window: ?dvui.Window = null,
    log_cb: ?*const LogFn = null,
    event_cb: ?*const EventFn = null,
    headers: std.ArrayListUnmanaged(CommandHeader) = .{},
    payload: std.ArrayListUnmanaged(u8) = .{},
    frame_arena: std.heap.ArenaAllocator,
    size: [2]u32 = .{ 0, 0 },
    pixel_size: [2]u32 = .{ 0, 0 },
    window_ready: bool = false,
    busy: bool = false,
    callback_depth: usize = 0,
    pending_destroy: bool = false,
    destroy_started: bool = false,
    solid_store_ready: bool = false,
    solid_store_ptr: ?*anyopaque = null,
    solid_seq_last: u64 = 0,
    frame_count: u64 = 0,
    // Event ring buffer for Zig→JS event dispatch
    event_ring_ptr: ?*anyopaque = null,
    event_ring_ready: bool = false,
};

// ============================================================
// Constants
// ============================================================

pub const flag_absolute: u8 = 1;
pub const frame_event_interval: u64 = 6; // ~10fps when running at 60fps

// ============================================================
// Helper Functions
// ============================================================

pub fn asOpaquePtr(comptime T: type, raw: ?*anyopaque) ?*T {
    if (raw) |ptr| {
        return @ptrCast(@alignCast(ptr));
    }
    return null;
}

pub fn solidStore(renderer: *Renderer) ?*solid.NodeStore {
    return asOpaquePtr(solid.NodeStore, renderer.solid_store_ptr);
}

pub fn eventRing(renderer: *Renderer) ?*solid.EventRing {
    return asOpaquePtr(solid.EventRing, renderer.event_ring_ptr);
}

pub fn colorFromPacked(value: u32) dvui.Color {
    return .{
        .r = @intCast((value >> 24) & 0xff),
        .g = @intCast((value >> 16) & 0xff),
        .b = @intCast((value >> 8) & 0xff),
        .a = @intCast(value & 0xff),
    };
}
