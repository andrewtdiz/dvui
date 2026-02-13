const std = @import("std");
const native = @import("native_renderer");

const usage =
    \\Usage:
    \\  luau-native-runner [options]
    \\
    \\Options:
    \\  --lua-entry <path>         Default: luau/index.luau
    \\  --app-module <id>         Default: (none)
    \\  --width <u32>              Default: 1280
    \\  --height <u32>             Default: 720
    \\  --pixel-width <u32>        Default: width
    \\  --pixel-height <u32>       Default: height
    \\  --screenshot-auto
    \\  --screenshot-out <path>
    \\
;

fn logCallback(level: u8, msg_ptr: [*]const u8, msg_len: usize) callconv(.c) void {
    const msg = msg_ptr[0..msg_len];
    std.debug.print("[native:{d}] {s}\n", .{ level, msg });
}

pub fn main() !void {
    var arena_state = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const args = try std.process.argsAlloc(arena);

    var lua_entry: ?[]const u8 = null;
    var app_module: ?[]const u8 = null;
    var width: u32 = 1280;
    var height: u32 = 720;
    var pixel_width: ?u32 = null;
    var pixel_height: ?u32 = null;
    var screenshot_auto = false;
    var screenshot_out: ?[]const u8 = null;

    var i: usize = 1;
    while (i < args.len) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            std.debug.print("{s}", .{usage});
            return;
        }
        if (std.mem.eql(u8, arg, "--lua-entry")) {
            lua_entry = try nextArg(args, &i);
            continue;
        }
        if (std.mem.eql(u8, arg, "--app-module")) {
            app_module = try nextArg(args, &i);
            continue;
        }
        if (std.mem.eql(u8, arg, "--width")) {
            width = try parseU32(try nextArg(args, &i));
            continue;
        }
        if (std.mem.eql(u8, arg, "--height")) {
            height = try parseU32(try nextArg(args, &i));
            continue;
        }
        if (std.mem.eql(u8, arg, "--pixel-width")) {
            pixel_width = try parseU32(try nextArg(args, &i));
            continue;
        }
        if (std.mem.eql(u8, arg, "--pixel-height")) {
            pixel_height = try parseU32(try nextArg(args, &i));
            continue;
        }
        if (std.mem.eql(u8, arg, "--screenshot-auto")) {
            screenshot_auto = true;
            i += 1;
            continue;
        }
        if (std.mem.eql(u8, arg, "--screenshot-out")) {
            screenshot_out = try nextArg(args, &i);
            continue;
        }

        std.debug.print("unknown flag: {s}\n{s}", .{ arg, usage });
        std.process.exit(2);
    }

    const renderer = native.lifecycle.createRendererWithLuaEntryAndAppImpl(&logCallback, null, lua_entry, app_module) orelse {
        std.debug.print("Failed to create native renderer\n", .{});
        return;
    };
    defer native.lifecycle.destroyRendererImpl(renderer);

    renderer.screenshot_key_enabled = true;
    renderer.screenshot_auto = screenshot_auto;
    renderer.screenshot_out_path = screenshot_out;
    renderer.size = .{ width, height };
    const px_w = pixel_width orelse width;
    const px_h = pixel_height orelse height;
    renderer.pixel_size = .{ px_w, px_h };
    try native.window.ensureWindow(renderer);

    while (!renderer.pending_destroy and !renderer.destroy_started) {
        native.window.renderFrame(renderer);
    }
}

fn nextArg(args: []const []const u8, i: *usize) ![]const u8 {
    const idx = i.*;
    if (idx + 1 >= args.len) return error.MissingArgValue;
    i.* = idx + 2;
    return args[idx + 1];
}

fn parseU32(s: []const u8) !u32 {
    return std.fmt.parseInt(u32, s, 10);
}
