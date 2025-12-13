// jsruntime module - Minimal stub for FFI interop
// This replaced the old QuickJS integration.
// Event dispatch now uses the event ring buffer in solid/events/.

pub const image_loader = @import("image_loader.zig");
const runtime = @import("runtime.zig");
pub const JSRuntime = runtime.JSRuntime;
