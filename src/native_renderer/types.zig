const std = @import("std");
const dvui = @import("dvui");
const RaylibBackend = @import("raylib-backend");
const webgpu = @import("webgpu");
const luaz = @import("luaz");
const luau_ui = @import("luau_ui");
const profiling = @import("profiling.zig");

// ============================================================
// Callback Types
// ============================================================

pub const LogFn = fn (level: u8, msg_ptr: [*]const u8, msg_len: usize) callconv(.c) void;
pub const EventFn = fn (name_ptr: [*]const u8, name_len: usize, data_ptr: [*]const u8, data_len: usize) callconv(.c) void;

// ============================================================
// Command Header
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
    webgpu: ?webgpu.Renderer = null,
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
    retained_store_ready: bool = false,
    retained_store_ptr: ?*anyopaque = null,
    frame_count: u64 = 0,
    profiler: profiling.FrameProfiler = .{},
    // Event ring buffer for retained UI (Lua dispatch).
    retained_event_ring_ptr: ?*anyopaque = null,
    retained_event_ring_ready: bool = false,
    lua_entry_path: ?[]const u8 = null,
    lua_app_module: ?[]const u8 = null,
    // Luau VM state for retained UI
    lua_state: ?*luaz.Lua = null,
    lua_ui: ?*luau_ui.LuaUi = null,
    lua_ready: bool = false,
    screenshot_key_enabled: bool = false,
    screenshot_index: u32 = 0,
    screenshot_auto: bool = false,
    screenshot_out_path: ?[]const u8 = null,
};

// ============================================================
// Constants
// ============================================================

pub const flag_absolute: u8 = 1;
pub const frame_event_interval: u64 = 6; // ~10fps when running at 60fps

// ============================================================
// Helper Functions
// ============================================================

