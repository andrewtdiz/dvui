const hot_reload = @import("hotreload.zig");
const console = @import("console.zig");
const runtime = @import("runtime.zig");

pub const FrameData = runtime.FrameData;
pub const FrameResult = runtime.FrameResult;
pub const MouseSnapshot = runtime.MouseSnapshot;
pub const MouseEvent = runtime.MouseEvent;
pub const MouseEventKind = runtime.MouseEventKind;
pub const MouseButton = runtime.MouseButton;
pub const KeyEvent = runtime.KeyEvent;
pub const KeyEventKind = runtime.KeyEventKind;
pub const KeyCode = runtime.KeyCode;
pub const EvalResult = runtime.EvalResult;
pub const ConsoleSink = console.ConsoleSink;
pub const SelectionColor = runtime.SelectionColor;

pub const JSRuntime = runtime.JSRuntime;

/// Global pointer for accessing the runtime from decoupled modules.
/// App.init installs the pointer and must clear it during shutdown.
pub var g_runtime: ?*JSRuntime = null;

pub fn enableHotReload(script_path: []const u8) !void {
    try hot_reload.enable(script_path);
}

pub fn shutdownHotReload() void {
    hot_reload.shutdown();
}

pub fn takeHotReloadRequest() bool {
    return hot_reload.takeRequest();
}

pub fn hotReloadScriptPath() ?[]const u8 {
    return hot_reload.scriptPath();
}

pub fn setGlobalRuntime(instance: *JSRuntime) void {
    g_runtime = instance;
}

pub fn clearGlobalRuntime() void {
    g_runtime = null;
}

pub fn setConsoleSink(sink: ConsoleSink) void {
    runtime.setConsoleSink(sink);
}

pub fn clearConsoleSink() void {
    runtime.clearConsoleSink();
}
