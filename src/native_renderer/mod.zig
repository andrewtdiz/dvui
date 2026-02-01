// Native Renderer Module
//
// This module provides the FFI interface for the native renderer.
// It is split into focused submodules for clarity:
//
// - types.zig: Core data structures (Renderer, CommandHeader, etc.)
// - lifecycle.zig: Renderer creation, destruction, logging
// - window.zig: Window lifecycle and frame rendering
// - commands.zig: Command buffer handling
// - exports.zig: All FFI export functions
//

pub const commands = @import("commands.zig");

pub const lifecycle = @import("lifecycle.zig");
pub const logMessage = lifecycle.logMessage;
pub const types = @import("types.zig");
pub const Renderer = types.Renderer;
pub const CommandHeader = types.CommandHeader;

pub const window = @import("window.zig");
pub const renderFrame = window.renderFrame;

