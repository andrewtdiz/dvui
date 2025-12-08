const ConsoleSink = struct {
    context: ?*anyopaque,
    send: *const fn (context: ?*anyopaque, level: []const u8, message: []const u8) void,
};

var g_console_sink: ?ConsoleSink = null;

pub fn setSink(sink: ConsoleSink) void {
    g_console_sink = sink;
}

pub fn clearSink() void {
    g_console_sink = null;
}

pub fn installBindings(_: anytype, _: anytype, _: anytype) !void {
    return;
}

pub const Console = ConsoleSink;
