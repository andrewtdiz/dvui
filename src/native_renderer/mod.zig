// Native Renderer Module
//
// This module provides the FFI interface for the native renderer.
// It is split into focused submodules for clarity:
//
// - types.zig: Core data structures (Renderer, CommandHeader, etc.)
// - solid_sync.zig: Solid tree synchronization (snapshot & ops)
// - lifecycle.zig: Renderer creation, destruction, logging
// - window.zig: Window lifecycle and frame rendering
// - commands.zig: Command buffer handling
// - events.zig: Event ring buffer helpers
// - exports.zig: All FFI export functions
//

pub const commands = @import("commands.zig");
pub const events = @import("events.zig");
pub const pushEvent = events.pushEvent;
const exports = @import("exports.zig");

pub const lifecycle = @import("lifecycle.zig");
pub const logMessage = lifecycle.logMessage;
pub const solid_sync = @import("solid_sync.zig");

pub const types = @import("types.zig");
pub const Renderer = types.Renderer;
pub const CommandHeader = types.CommandHeader;

pub const window = @import("window.zig");
pub const renderFrame = window.renderFrame;

comptime {
    _ = exports.createRenderer;
    _ = exports.destroyRenderer;
    _ = exports.resizeRenderer;
    _ = exports.presentRenderer;
    _ = exports.commitCommands;
    _ = exports.setRendererText;
    _ = exports.setRendererSolidTree;
    _ = exports.applyRendererSolidOps;
    _ = exports.getEventRingHeader;
    _ = exports.getEventRingBuffer;
    _ = exports.getEventRingDetail;
    _ = exports.acknowledgeEvents;
}
