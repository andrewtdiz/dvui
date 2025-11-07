const std = @import("std");
const builtin = @import("builtin");

const alloc = @import("../alloc.zig");

const Wyhash = std.hash.Wyhash;

const WatchState = struct {
    allocator: std.mem.Allocator,
    thread: ?std.Thread = null,
    stop_flag: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
    reload_flag: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
    digest: u64 = 0,
    digest_initialized: bool = false,
    directory_path: []u8 = &.{},
    script_path: []u8 = &.{},
};

const poll_interval_ns: u64 = 200 * std.time.ns_per_ms;
const watch_extensions = [_][]const u8{ ".js", ".ts" };

var g_state: ?*WatchState = null;

pub fn enable(script_path: []const u8) !void {
    if (builtin.mode != .Debug) return;

    if (g_state) |state| {
        _ = state; // already running
        return;
    }

    const allocator = alloc.allocator();

    const dir_slice = std.fs.path.dirname(script_path) orelse ".";
    const abs_dir = std.fs.cwd().realpathAlloc(allocator, dir_slice) catch {
        return;
    };
    errdefer allocator.free(abs_dir);

    const script_copy = allocator.dupe(u8, script_path) catch {
        allocator.free(abs_dir);
        return;
    };
    errdefer allocator.free(script_copy);

    var new_state = allocator.create(WatchState) catch {
        allocator.free(abs_dir);
        allocator.free(script_copy);
        return;
    };
    errdefer allocator.destroy(new_state);

    new_state.* = .{
        .allocator = allocator,
        .directory_path = abs_dir,
        .script_path = script_copy,
    };

    const thread = std.Thread.spawn(.{}, watchThread, .{new_state}) catch {
        allocator.destroy(new_state);
        allocator.free(abs_dir);
        allocator.free(script_copy);
        return;
    };

    new_state.thread = thread;
    g_state = new_state;
}

pub fn shutdown() void {
    if (builtin.mode != .Debug) return;

    if (g_state) |state| {
        state.stop_flag.store(true, .release);
        if (state.thread) |thread| {
            thread.join();
        }

        const allocator = state.allocator;
        allocator.free(state.directory_path);
        allocator.free(state.script_path);
        allocator.destroy(state);
        g_state = null;
    }
}

pub fn takeRequest() bool {
    if (builtin.mode != .Debug) return false;
    if (g_state) |state| {
        return state.reload_flag.swap(false, .acq_rel);
    }
    return false;
}

pub fn scriptPath() ?[]const u8 {
    if (builtin.mode != .Debug) return null;
    if (g_state) |state| return state.script_path;
    return null;
}

fn watchThread(state: *WatchState) void {
    while (!state.stop_flag.load(.acquire)) {
        if (scanForChanges(state)) {
            state.reload_flag.store(true, .release);
        }
        std.Thread.sleep(poll_interval_ns);
    }
}

fn scanForChanges(state: *WatchState) bool {
    var dir = std.fs.cwd().openDir(state.directory_path, .{ .iterate = true }) catch {
        return false;
    };
    defer dir.close();

    var hasher = Wyhash.init(0);

    var iterator = dir.iterate();
    while (iterator.next() catch return false) |entry| {
        if (entry.kind != .file) continue;
        if (!matchesExtension(entry.name)) continue;

        const stat = dir.statFile(entry.name) catch continue;
        var mtime = stat.mtime;
        var size = stat.size;
        hasher.update(std.mem.asBytes(&mtime));
        hasher.update(std.mem.asBytes(&size));
    }

    const digest = hasher.final();
    if (!state.digest_initialized) {
        state.digest = digest;
        state.digest_initialized = true;
        return false;
    }

    if (state.digest != digest) {
        state.digest = digest;
        return true;
    }

    return false;
}

fn matchesExtension(name: []const u8) bool {
    for (watch_extensions) |ext| {
        if (std.mem.endsWith(u8, name, ext)) return true;
    }
    return false;
}
