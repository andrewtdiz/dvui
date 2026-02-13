const std = @import("std");

const dvui = @import("dvui");
const native = @import("native_renderer");
const retained = @import("retained");

const usage =
    \\Usage:
    \\  luau-layout-dump <scene> [options]
    \\  luau-layout-dump --scene <scene> [options]
    \\  luau-layout-dump --lua-entry <path> [options]
    \\  luau-layout-dump --ui-json <path> [options]
    \\
    \\Options:
    \\  --list-scenes
    \\  --scenes <path>            Default: tools/layoutdump_scenes.json
    \\  --update-baseline
    \\
    \\  --lua-entry <path>
    \\  --app-module <id>
    \\  --ui-json <path>
    \\  --width <u32>              Default: 1280
    \\  --height <u32>             Default: 720
    \\  --pixel-width <u32>        Default: width
    \\  --pixel-height <u32>       Default: height
    \\  --frames <u32>             Default: 2
    \\  --dt <f32>                 Default: 0
    \\  --out <path>               Default: artifacts/<scene>.layout.json
    \\  --baseline <path>          Default: snapshots/<scene>.layout.json
    \\  --decimals <u8>            Default: 2
    \\  --text-max <usize>         Default: 64
    \\  --max-diff <usize>         Default: 20
    \\
;

const RunMode = enum {
    luau,
    ui_json,
};

const SceneConfig = struct {
    lua_entry: ?[]const u8 = null,
    app_module: ?[]const u8 = null,
    ui_json: ?[]const u8 = null,
    width: ?u32 = null,
    height: ?u32 = null,
    pixel_width: ?u32 = null,
    pixel_height: ?u32 = null,
    frames: ?u32 = null,
    dt: ?f32 = null,
    out: ?[]const u8 = null,
    baseline: ?[]const u8 = null,
};

const CliOverrides = struct {
    lua_entry: ?[]const u8 = null,
    app_module: ?[]const u8 = null,
    ui_json: ?[]const u8 = null,
    width: ?u32 = null,
    height: ?u32 = null,
    pixel_width: ?u32 = null,
    pixel_height: ?u32 = null,
    frames: ?u32 = null,
    dt: ?f32 = null,
    out: ?[]const u8 = null,
    baseline: ?[]const u8 = null,
    decimals: ?u8 = null,
    text_max: ?usize = null,
    max_diff: ?usize = null,
};

const RunConfig = struct {
    mode: RunMode,
    scene_name: ?[]const u8,
    scene_path: []const u8,
    lua_entry: []const u8,
    app_module: ?[]const u8,
    ui_json: ?[]const u8,
    width: u32,
    height: u32,
    pixel_width: u32,
    pixel_height: u32,
    frames: u32,
    dt: f32,
    out: []const u8,
    baseline: []const u8,
    update_baseline: bool,
    decimals: u8,
    text_max: usize,
    max_diff: usize,
};

fn logCallback(level: u8, msg_ptr: [*]const u8, msg_len: usize) callconv(.c) void {
    const msg = msg_ptr[0..msg_len];
    std.debug.print("[native:{d}] {s}\n", .{ level, msg });
}

pub fn main() !void {
    var arena_state = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const args = try std.process.argsAlloc(arena);

    var scene_name: ?[]const u8 = null;
    var scenes_path: []const u8 = "tools/layoutdump_scenes.json";
    var list_scenes = false;
    var update_baseline = false;
    var overrides: CliOverrides = .{};

    var i: usize = 1;
    while (i < args.len) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            std.debug.print("{s}", .{usage});
            return;
        }
        if (arg.len > 0 and arg[0] != '-') {
            if (scene_name != null) {
                fatalUsage("unexpected positional argument: {s}", .{arg});
            }
            scene_name = arg;
            i += 1;
            continue;
        }
        if (std.mem.eql(u8, arg, "--scene")) {
            scene_name = try nextArg(args, &i);
            continue;
        }
        if (std.mem.eql(u8, arg, "--scenes")) {
            scenes_path = try nextArg(args, &i);
            continue;
        }
        if (std.mem.eql(u8, arg, "--list-scenes")) {
            list_scenes = true;
            i += 1;
            continue;
        }
        if (std.mem.eql(u8, arg, "--update-baseline")) {
            update_baseline = true;
            i += 1;
            continue;
        }
        if (std.mem.eql(u8, arg, "--lua-entry")) {
            overrides.lua_entry = try nextArg(args, &i);
            continue;
        }
        if (std.mem.eql(u8, arg, "--app-module")) {
            overrides.app_module = try nextArg(args, &i);
            continue;
        }
        if (std.mem.eql(u8, arg, "--ui-json")) {
            overrides.ui_json = try nextArg(args, &i);
            continue;
        }
        if (std.mem.eql(u8, arg, "--width")) {
            overrides.width = try parseU32(try nextArg(args, &i));
            continue;
        }
        if (std.mem.eql(u8, arg, "--height")) {
            overrides.height = try parseU32(try nextArg(args, &i));
            continue;
        }
        if (std.mem.eql(u8, arg, "--pixel-width")) {
            overrides.pixel_width = try parseU32(try nextArg(args, &i));
            continue;
        }
        if (std.mem.eql(u8, arg, "--pixel-height")) {
            overrides.pixel_height = try parseU32(try nextArg(args, &i));
            continue;
        }
        if (std.mem.eql(u8, arg, "--frames")) {
            overrides.frames = try parseU32(try nextArg(args, &i));
            continue;
        }
        if (std.mem.eql(u8, arg, "--dt")) {
            overrides.dt = try std.fmt.parseFloat(f32, try nextArg(args, &i));
            continue;
        }
        if (std.mem.eql(u8, arg, "--out")) {
            overrides.out = try nextArg(args, &i);
            continue;
        }
        if (std.mem.eql(u8, arg, "--baseline")) {
            overrides.baseline = try nextArg(args, &i);
            continue;
        }
        if (std.mem.eql(u8, arg, "--decimals")) {
            overrides.decimals = try parseU8(try nextArg(args, &i));
            continue;
        }
        if (std.mem.eql(u8, arg, "--text-max")) {
            overrides.text_max = try parseUsize(try nextArg(args, &i));
            continue;
        }
        if (std.mem.eql(u8, arg, "--max-diff")) {
            overrides.max_diff = try parseUsize(try nextArg(args, &i));
            continue;
        }

        fatalUsage("unknown flag: {s}", .{arg});
    }

    if (list_scenes) {
        const scenes_parsed = loadScenes(arena, scenes_path) catch |err| {
            fatalRuntime("scenes load failed: {s}", .{@errorName(err)});
        };
        listScenes(arena, scenes_parsed.value) catch |err| {
            fatalRuntime("scenes list failed: {s}", .{@errorName(err)});
        };
        return;
    }

    var scene_cfg: SceneConfig = .{};
    if (scene_name != null) {
        const scenes_parsed = loadScenes(arena, scenes_path) catch |err| {
            fatalRuntime("scenes load failed: {s}", .{@errorName(err)});
        };
        scene_cfg = loadSceneConfig(scenes_parsed.value, scene_name.?) catch |err| {
            fatalUsage("scene load failed: {s}", .{@errorName(err)});
        };
    }

    const cfg = resolveConfig(arena, scene_name, scene_cfg, overrides, update_baseline) catch |err| {
        fatalUsage("config error: {s}", .{@errorName(err)});
    };

    run(cfg, arena) catch |err| {
        fatalRuntime("run failed: {s}", .{@errorName(err)});
    };
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

fn parseU8(s: []const u8) !u8 {
    return std.fmt.parseInt(u8, s, 10);
}

fn parseUsize(s: []const u8) !usize {
    return std.fmt.parseInt(usize, s, 10);
}

fn fatalUsage(comptime fmt: []const u8, args: anytype) noreturn {
    std.debug.print(fmt ++ "\n", args);
    std.debug.print("{s}", .{usage});
    std.process.exit(2);
}

fn fatalRuntime(comptime fmt: []const u8, args: anytype) noreturn {
    std.debug.print(fmt ++ "\n", args);
    std.process.exit(3);
}

fn loadScenes(allocator: std.mem.Allocator, path: []const u8) !std.json.Parsed(std.json.Value) {
    const bytes = try readFileAlloc(allocator, path, 4 * 1024 * 1024);
    return std.json.parseFromSlice(std.json.Value, allocator, bytes, .{ .allocate = .alloc_always });
}

fn listScenes(allocator: std.mem.Allocator, root: std.json.Value) !void {
    if (root != .object) return error.InvalidScenesFile;
    const obj = root.object;
    const scenes_val = obj.get("scenes") orelse return error.InvalidScenesFile;
    if (scenes_val != .object) return error.InvalidScenesFile;

    const scenes_obj = scenes_val.object;
    var keys: std.ArrayList([]const u8) = .empty;
    defer keys.deinit(allocator);

    var it = scenes_obj.iterator();
    while (it.next()) |entry| {
        try keys.append(allocator, entry.key_ptr.*);
    }
    if (keys.items.len > 1) {
        std.sort.pdq([]const u8, keys.items, {}, lessThanString);
    }
    for (keys.items) |k| {
        std.debug.print("{s}\n", .{k});
    }
}

fn lessThanString(_: void, a: []const u8, b: []const u8) bool {
    return std.mem.lessThan(u8, a, b);
}

fn loadSceneConfig(root: std.json.Value, name: []const u8) !SceneConfig {
    if (root != .object) return error.InvalidScenesFile;
    const obj = root.object;
    const scenes_val = obj.get("scenes") orelse return error.InvalidScenesFile;
    if (scenes_val != .object) return error.InvalidScenesFile;
    const scenes_obj = scenes_val.object;
    const scene_val = scenes_obj.get(name) orelse return error.MissingScene;
    return parseSceneConfig(scene_val);
}

fn parseSceneConfig(val: std.json.Value) !SceneConfig {
    if (val != .object) return error.InvalidScene;
    const obj = val.object;

    var cfg: SceneConfig = .{};
    if (obj.get("luaEntry")) |v| {
        if (v != .string) return error.InvalidScene;
        cfg.lua_entry = v.string;
    }
    if (obj.get("appModule")) |v| {
        if (v != .string) return error.InvalidScene;
        cfg.app_module = v.string;
    }
    if (obj.get("uiJson")) |v| {
        if (v != .string) return error.InvalidScene;
        cfg.ui_json = v.string;
    }
    if (obj.get("width")) |v| cfg.width = try parseJsonU32(v);
    if (obj.get("height")) |v| cfg.height = try parseJsonU32(v);
    if (obj.get("pixelWidth")) |v| cfg.pixel_width = try parseJsonU32(v);
    if (obj.get("pixelHeight")) |v| cfg.pixel_height = try parseJsonU32(v);
    if (obj.get("frames")) |v| cfg.frames = try parseJsonU32(v);
    if (obj.get("dt")) |v| cfg.dt = try parseJsonF32(v);
    if (obj.get("out")) |v| {
        if (v != .string) return error.InvalidScene;
        cfg.out = v.string;
    }
    if (obj.get("baseline")) |v| {
        if (v != .string) return error.InvalidScene;
        cfg.baseline = v.string;
    }

    return cfg;
}

fn parseJsonU32(v: std.json.Value) !u32 {
    return switch (v) {
        .integer => |n| blk: {
            if (n < 0) return error.InvalidNumber;
            break :blk @intCast(n);
        },
        .float => |f| blk: {
            if (f < 0) return error.InvalidNumber;
            break :blk @intFromFloat(@round(f));
        },
        else => error.InvalidNumber,
    };
}

fn parseJsonF32(v: std.json.Value) !f32 {
    return switch (v) {
        .integer => |n| @floatFromInt(n),
        .float => |f| @floatCast(f),
        else => error.InvalidNumber,
    };
}

fn resolveConfig(
    allocator: std.mem.Allocator,
    scene_name: ?[]const u8,
    scene: SceneConfig,
    overrides: CliOverrides,
    update_baseline: bool,
) !RunConfig {
    const lua_entry = overrides.lua_entry orelse scene.lua_entry orelse "luau/index.luau";
    const app_module = overrides.app_module orelse scene.app_module;
    const ui_json = overrides.ui_json orelse scene.ui_json;
    const mode: RunMode = if (ui_json != null) .ui_json else .luau;
    const width = overrides.width orelse scene.width orelse 1280;
    const height = overrides.height orelse scene.height orelse 720;
    const pixel_width = overrides.pixel_width orelse scene.pixel_width orelse width;
    const pixel_height = overrides.pixel_height orelse scene.pixel_height orelse height;
    const frames = overrides.frames orelse scene.frames orelse 2;
    if (frames == 0) return error.InvalidFrames;
    const dt = overrides.dt orelse scene.dt orelse 0;

    const out = overrides.out orelse scene.out orelse try defaultOutPath(allocator, scene_name);
    const baseline = overrides.baseline orelse scene.baseline orelse try defaultBaselinePath(allocator, scene_name);

    const decimals = overrides.decimals orelse 2;
    const text_max = overrides.text_max orelse 64;
    const max_diff = overrides.max_diff orelse 20;

    const scene_path = if (mode == .ui_json) ui_json.? else if (app_module != null) app_module.? else lua_entry;

    return .{
        .mode = mode,
        .scene_name = scene_name,
        .scene_path = scene_path,
        .lua_entry = lua_entry,
        .app_module = app_module,
        .ui_json = ui_json,
        .width = width,
        .height = height,
        .pixel_width = pixel_width,
        .pixel_height = pixel_height,
        .frames = frames,
        .dt = dt,
        .out = out,
        .baseline = baseline,
        .update_baseline = update_baseline,
        .decimals = decimals,
        .text_max = text_max,
        .max_diff = max_diff,
    };
}

fn defaultOutPath(allocator: std.mem.Allocator, scene_name: ?[]const u8) ![]const u8 {
    const name = scene_name orelse "app";
    return std.fmt.allocPrint(allocator, "artifacts/{s}.layout.json", .{name});
}

fn defaultBaselinePath(allocator: std.mem.Allocator, scene_name: ?[]const u8) ![]const u8 {
    const name = scene_name orelse "app";
    return std.fmt.allocPrint(allocator, "snapshots/{s}.layout.json", .{name});
}

fn readFileAlloc(allocator: std.mem.Allocator, path: []const u8, max_bytes: usize) ![]u8 {
    const file = if (std.fs.path.isAbsolute(path))
        try std.fs.openFileAbsolute(path, .{ .mode = .read_only })
    else
        try std.fs.cwd().openFile(path, .{ .mode = .read_only });
    defer file.close();
    return file.readToEndAlloc(allocator, max_bytes);
}

fn writeFile(path: []const u8, bytes: []const u8) !void {
    if (std.fs.path.dirname(path)) |dir| {
        std.fs.cwd().makePath(dir) catch |err| switch (err) {
            error.PathAlreadyExists => {},
            else => return err,
        };
    }

    const file = if (std.fs.path.isAbsolute(path))
        try std.fs.createFileAbsolute(path, .{ .truncate = true })
    else
        try std.fs.cwd().createFile(path, .{ .truncate = true });
    defer file.close();
    try file.writeAll(bytes);
}

const NodeRow = struct {
    id: u32,
    parent_id: ?u32,
    kind: []const u8,
    tag: []const u8,
    class_name: []const u8,
    key_path: []const u8,
    parent_key_path: ?[]const u8,
    rect: ?retained.Rect,
    child_rect: ?retained.Rect,
    text: []const u8,
    text_hash: u64,
};

fn nodeRowLessThan(_: void, a: NodeRow, b: NodeRow) bool {
    if (std.mem.eql(u8, a.key_path, b.key_path)) {
        if (std.mem.eql(u8, a.kind, b.kind)) {
            if (std.mem.eql(u8, a.tag, b.tag)) {
                return a.id < b.id;
            }
            return std.mem.lessThan(u8, a.tag, b.tag);
        }
        return std.mem.lessThan(u8, a.kind, b.kind);
    }
    return std.mem.lessThan(u8, a.key_path, b.key_path);
}

fn run(cfg: RunConfig, allocator: std.mem.Allocator) !void {
    const renderer = native.lifecycle.createRendererWithLuaEntryAndAppImpl(&logCallback, null, cfg.lua_entry, cfg.app_module) orelse {
        return error.RendererInitFailed;
    };
    defer native.lifecycle.destroyRendererImpl(renderer);

    renderer.size = .{ cfg.width, cfg.height };
    renderer.pixel_size = .{ cfg.pixel_width, cfg.pixel_height };
    try native.window.ensureWindow(renderer);

    const store = try native.lifecycle.ensureRetainedStore(renderer);

    var out_bytes: std.ArrayList(u8) = .empty;
    defer out_bytes.deinit(allocator);

    if (renderer.window) |*win| {
        var time_ns: i128 = 0;
        try win.begin(time_ns);

        if (cfg.mode == .ui_json) {
            const cw = dvui.currentWindow();
            const scale = dvui.windowNaturalScale();
            const root_w: f32 = if (scale != 0) cw.rect_pixels.w / scale else cw.rect_pixels.w;
            const root_h: f32 = if (scale != 0) cw.rect_pixels.h / scale else cw.rect_pixels.h;
            try loadUiJsonSnapshot(allocator, store, cfg.ui_json.?, root_w, root_h);
        }

        const dt_ns = dtToNs(cfg.dt);
        var frame: u32 = 0;
        while (frame < cfg.frames) : (frame += 1) {
            if (cfg.mode == .luau) {
                try luaUpdate(renderer, cfg.dt);
            }
            retained.updateLayouts(store);

            if (frame + 1 == cfg.frames) {
                try dumpLayout(allocator, cfg, store, &out_bytes);
            }

            _ = try win.end(.{});
            if (renderer.webgpu) |*wgpu_renderer| {
                try wgpu_renderer.render();
            }

            time_ns += dt_ns;
            if (frame + 1 < cfg.frames) {
                try win.begin(time_ns);
            }
        }
    } else {
        return error.WindowMissing;
    }

    try writeFile(cfg.out, out_bytes.items);

    if (cfg.update_baseline) {
        try writeFile(cfg.baseline, out_bytes.items);
        return;
    }

    const baseline_bytes = readFileAlloc(allocator, cfg.baseline, 16 * 1024 * 1024) catch |err| {
        std.debug.print("baseline read failed: {s}\n", .{@errorName(err)});
        std.process.exit(2);
    };

    if (std.mem.eql(u8, baseline_bytes, out_bytes.items)) {
        return;
    }

    diffBaseline(allocator, cfg.baseline, baseline_bytes, cfg.out, out_bytes.items, cfg.max_diff) catch |err| {
        std.debug.print("diff failed: {s}\n", .{@errorName(err)});
    };
    std.process.exit(1);
}

fn dtToNs(dt: f32) i128 {
    const scaled: f64 = @as(f64, dt) * 1_000_000_000.0;
    const rounded: i128 = @intFromFloat(@round(scaled));
    return if (rounded >= 1000) rounded else 1000;
}

fn loadUiJsonSnapshot(
    allocator: std.mem.Allocator,
    store: *retained.NodeStore,
    path: []const u8,
    root_w: f32,
    root_h: f32,
) !void {
    const bytes = try readFileAlloc(allocator, path, 16 * 1024 * 1024);
    defer allocator.free(bytes);

    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, bytes, .{ .allocate = .alloc_always });
    defer parsed.deinit();

    const ok = retained.ui_json.setSnapshotFromUiJsonValue(store, null, parsed.value, root_w, root_h);
    if (!ok) return error.UiJsonLoadFailed;
}

fn luaUpdate(renderer: *native.Renderer, dt: f32) !void {
    if (!renderer.lua_ready) return;
    const lua_state = renderer.lua_state orelse return;
    if (!native.lifecycle.isLuaFuncPresent(lua_state, "update")) return;

    const globals = lua_state.globals();
    const window_rect = dvui.windowRect();
    const input_table = lua_state.createTable(.{ .rec = 12 });
    defer input_table.deinit();

    try input_table.set("width", window_rect.w);
    try input_table.set("height", window_rect.h);
    try input_table.set("mouseX", @as(f32, 0));
    try input_table.set("mouseY", @as(f32, 0));
    try input_table.set("mouseDown", false);
    try input_table.set("shift", false);
    try input_table.set("ctrl", false);
    try input_table.set("alt", false);
    try input_table.set("cmd", false);

    const call_result = globals.call("update", .{ dt, input_table }, void) catch |err| {
        native.lifecycle.logLuaError(renderer, "update", err);
        return error.LuaUpdateFailed;
    };
    switch (call_result) {
        .ok => {},
        else => return error.LuaUpdateFailed,
    }
}

fn dumpLayout(allocator: std.mem.Allocator, cfg: RunConfig, store: *retained.NodeStore, out: *std.ArrayList(u8)) !void {
    out.clearRetainingCapacity();

    var key_by_id: std.AutoHashMap(u32, []const u8) = std.AutoHashMap(u32, []const u8).init(allocator);
    defer key_by_id.deinit();

    var seen_keys: std.StringHashMapUnmanaged(u32) = .empty;
    defer seen_keys.deinit(allocator);

    const store_root_key = "$root";
    try key_by_id.put(0, store_root_key);
    try seen_keys.putNoClobber(allocator, store_root_key, 0);

    var stack: std.ArrayList(u32) = .empty;
    defer stack.deinit(allocator);
    try stack.append(allocator, 0);

    var rows: std.ArrayList(NodeRow) = .empty;
    defer rows.deinit(allocator);

    while (stack.pop()) |node_id| {
        const node = store.node(node_id) orelse continue;
        const key_path = key_by_id.get(node_id) orelse "root";

        const parent_id = node.parent;
        const parent_key_path = if (parent_id) |pid| key_by_id.get(pid) else null;

        const kind = kindString(node.kind);
        const tag = if (node.kind == .element) node.tag else "";
        const class_name = node.class_name;
        const rect = node.layout.rect;
        const child_rect = node.layout.child_rect;
        const text_full = node.text;
        const text = if (text_full.len > cfg.text_max) text_full[0..cfg.text_max] else text_full;
        const text_hash = node.textContentHash();

        try rows.append(allocator, .{
            .id = node.id,
            .parent_id = parent_id,
            .kind = kind,
            .tag = tag,
            .class_name = class_name,
            .key_path = key_path,
            .parent_key_path = parent_key_path,
            .rect = rect,
            .child_rect = child_rect,
            .text = text,
            .text_hash = text_hash,
        });

        const base_key = key_path;
        const children = node.children.items;
        var child_index: usize = children.len;
        while (child_index > 0) {
            child_index -= 1;
            const child_id = children[child_index];
            if (key_by_id.contains(child_id)) continue;
            const child = store.node(child_id) orelse continue;
            const child_key = try computeKeyPath(allocator, base_key, child, child_index);
            if (seen_keys.get(child_key)) |other_id| {
                std.debug.print("duplicate keyPath: {s} (nodes {d} and {d})\n", .{ child_key, other_id, child_id });
                return error.DuplicateKeyPath;
            }
            try seen_keys.putNoClobber(allocator, child_key, child_id);
            try key_by_id.put(child_id, child_key);
            try stack.append(allocator, child_id);
        }
    }

    if (rows.items.len > 1) {
        std.sort.pdq(NodeRow, rows.items, {}, nodeRowLessThan);
    }

    var w = out.writer(allocator);
    try w.writeAll("{\n");
    try w.writeAll("  \"meta\": {\n");
    try w.writeAll("    \"scene\": ");
    try writeJsonString(&w, cfg.scene_path);
    try w.writeAll(",\n");
    const cw = dvui.currentWindow();
    const win_size = cw.backend.windowSize();
    const px_size = cw.backend.pixelSize();
    const actual_width: u32 = @intFromFloat(@round(win_size.w));
    const actual_height: u32 = @intFromFloat(@round(win_size.h));
    const actual_pixel_width: u32 = @intFromFloat(@round(px_size.w));
    const actual_pixel_height: u32 = @intFromFloat(@round(px_size.h));
    try w.print("    \"width\": {d},\n", .{actual_width});
    try w.print("    \"height\": {d},\n", .{actual_height});
    try w.print("    \"pixelWidth\": {d},\n", .{actual_pixel_width});
    try w.print("    \"pixelHeight\": {d},\n", .{actual_pixel_height});
    try w.print("    \"frame\": {d},\n", .{cfg.frames});
    try w.writeAll("    \"dt\": ");
    try writeFloatFixed(&w, cfg.dt, 6);
    try w.writeAll(",\n");
    try w.print("    \"decimals\": {d}\n", .{cfg.decimals});
    try w.writeAll("  },\n");
    try w.writeAll("  \"nodes\": [\n");

    for (rows.items, 0..) |row, idx| {
        if (idx != 0) try w.writeAll(",\n");
        try w.writeAll("    {\n");
        try w.print("      \"id\": {d},\n", .{row.id});
        try w.writeAll("      \"parent\": ");
        if (row.parent_id) |pid| {
            try w.print("{d}", .{pid});
        } else {
            try w.writeAll("null");
        }
        try w.writeAll(",\n");
        try w.writeAll("      \"kind\": ");
        try writeJsonString(&w, row.kind);
        try w.writeAll(",\n");
        try w.writeAll("      \"tag\": ");
        try writeJsonString(&w, row.tag);
        try w.writeAll(",\n");
        try w.writeAll("      \"class\": ");
        try writeJsonString(&w, row.class_name);
        try w.writeAll(",\n");
        try w.writeAll("      \"keyPath\": ");
        try writeJsonString(&w, row.key_path);
        try w.writeAll(",\n");
        try w.writeAll("      \"parentKeyPath\": ");
        if (row.parent_key_path) |pk| {
            try writeJsonString(&w, pk);
        } else {
            try w.writeAll("null");
        }
        try w.writeAll(",\n");
        try w.writeAll("      \"rect\": ");
        try writeRectOpt(&w, row.rect, cfg.decimals);
        try w.writeAll(",\n");
        try w.writeAll("      \"childRect\": ");
        try writeRectOpt(&w, row.child_rect, cfg.decimals);
        try w.writeAll(",\n");
        try w.writeAll("      \"text\": ");
        try writeJsonString(&w, row.text);
        try w.writeAll(",\n");
        try w.print("      \"textHash\": {d}\n", .{row.text_hash});
        try w.writeAll("    }");
    }

    try w.writeAll("\n  ]\n");
    try w.writeAll("}\n");
}

fn kindString(kind: anytype) []const u8 {
    return switch (kind) {
        .root => "root",
        .element => "element",
        .text => "text",
        .slot => "slot",
    };
}

fn computeKeyPath(allocator: std.mem.Allocator, parent_key: []const u8, child: *retained.SolidNode, index: usize) ![]const u8 {
    if (extractKeyToken(child.class_name)) |token| {
        if (token.len == 0) return error.InvalidKeyToken;
        return token;
    }
    const seg_name = switch (child.kind) {
        .element => if (child.tag.len > 0) child.tag else "element",
        .text => "text",
        .slot => "slot",
        .root => "root",
    };
    return std.fmt.allocPrint(allocator, "{s}/{s}[{d}]", .{ parent_key, seg_name, index });
}

fn extractKeyToken(class_name: []const u8) ?[]const u8 {
    var it = std.mem.tokenizeScalar(u8, class_name, ' ');
    var ui_path: ?[]const u8 = null;
    while (it.next()) |tok| {
        if (std.mem.startsWith(u8, tok, "__key=")) {
            return tok["__key=".len..];
        }
        if (ui_path == null and std.mem.startsWith(u8, tok, "ui-path-")) {
            ui_path = tok["ui-path-".len..];
        }
    }
    return ui_path;
}

fn writeJsonString(w: anytype, s: []const u8) !void {
    try w.writeByte('"');
    for (s) |c| {
        switch (c) {
            '"' => try w.writeAll("\\\""),
            '\\' => try w.writeAll("\\\\"),
            '\n' => try w.writeAll("\\n"),
            '\r' => try w.writeAll("\\r"),
            '\t' => try w.writeAll("\\t"),
            0x08 => try w.writeAll("\\b"),
            0x0C => try w.writeAll("\\f"),
            else => {
                if (c < 0x20) {
                    var buf: [6]u8 = undefined;
                    buf[0] = '\\';
                    buf[1] = 'u';
                    buf[2] = '0';
                    buf[3] = '0';
                    buf[4] = toHex(@intCast(c >> 4));
                    buf[5] = toHex(@intCast(c & 0xF));
                    try w.writeAll(&buf);
                } else {
                    try w.writeByte(c);
                }
            },
        }
    }
    try w.writeByte('"');
}

fn toHex(n: u4) u8 {
    return if (n < 10) ('0' + @as(u8, @intCast(n))) else ('a' + @as(u8, @intCast(n - 10)));
}

fn pow10(decimals: u8) i64 {
    var p: i64 = 1;
    var i: u8 = 0;
    while (i < decimals) : (i += 1) {
        p *= 10;
    }
    return p;
}

fn writeFloatFixed(w: anytype, value: f32, decimals: u8) !void {
    const scale = pow10(decimals);
    const scaled: f64 = @as(f64, value) * @as(f64, @floatFromInt(scale));
    const rounded: i64 = @intFromFloat(@round(scaled));
    try writeScaledFixed(w, rounded, decimals);
}

fn writeScaledFixed(w: anytype, scaled: i64, decimals: u8) !void {
    if (decimals == 0) {
        try w.print("{d}", .{scaled});
        return;
    }

    const scale = pow10(decimals);
    const neg = scaled < 0;
    const abs_val: i64 = if (neg) -scaled else scaled;
    const int_part = @divTrunc(abs_val, scale);
    var frac_part: i64 = @mod(abs_val, scale);

    var frac_buf: [18]u8 = undefined;
    if (decimals > frac_buf.len) return error.DecimalsTooLarge;
    var pos: usize = decimals;
    while (pos > 0) {
        pos -= 1;
        const digit: u8 = @intCast(@mod(frac_part, 10));
        frac_part = @divTrunc(frac_part, 10);
        frac_buf[pos] = '0' + digit;
    }

    if (neg) {
        try w.print("-{d}.{s}", .{ int_part, frac_buf[0..decimals] });
    } else {
        try w.print("{d}.{s}", .{ int_part, frac_buf[0..decimals] });
    }
}

fn writeRectOpt(w: anytype, rect_opt: ?retained.Rect, decimals: u8) !void {
    if (rect_opt) |rect| {
        try w.writeByte('[');
        try writeFloatFixed(w, rect.x, decimals);
        try w.writeByte(',');
        try writeFloatFixed(w, rect.y, decimals);
        try w.writeByte(',');
        try writeFloatFixed(w, rect.w, decimals);
        try w.writeByte(',');
        try writeFloatFixed(w, rect.h, decimals);
        try w.writeByte(']');
        return;
    }
    try w.writeAll("null");
}

const ParsedLayout = struct {
    decimals: u8,
    nodes: std.StringHashMapUnmanaged(NodeView),
    parsed: std.json.Parsed(std.json.Value),
};

const NodeView = struct {
    kind: []const u8,
    tag: []const u8,
    class_name: []const u8,
    parent_key_path: ?[]const u8,
    rect: ?[4]i64,
    child_rect: ?[4]i64,
    text_hash: u64,
};

fn diffBaseline(
    allocator: std.mem.Allocator,
    expected_path: []const u8,
    expected_bytes: []const u8,
    got_path: []const u8,
    got_bytes: []const u8,
    max_diff: usize,
) !void {
    var expected_parsed = try parseLayoutFile(allocator, expected_bytes);
    defer expected_parsed.nodes.deinit(allocator);
    defer expected_parsed.parsed.deinit();

    var got_parsed = try parseLayoutFile(allocator, got_bytes);
    defer got_parsed.nodes.deinit(allocator);
    defer got_parsed.parsed.deinit();

    const common_decimals = @max(expected_parsed.decimals, got_parsed.decimals);

    var all_keys: std.ArrayList([]const u8) = .empty;
    defer all_keys.deinit(allocator);

    var key_set: std.StringHashMapUnmanaged(void) = .empty;
    defer key_set.deinit(allocator);

    {
        var it = expected_parsed.nodes.iterator();
        while (it.next()) |entry| {
            const k = entry.key_ptr.*;
            if (!key_set.contains(k)) {
                try key_set.putNoClobber(allocator, k, {});
                try all_keys.append(allocator, k);
            }
        }
    }
    {
        var it = got_parsed.nodes.iterator();
        while (it.next()) |entry| {
            const k = entry.key_ptr.*;
            if (!key_set.contains(k)) {
                try key_set.putNoClobber(allocator, k, {});
                try all_keys.append(allocator, k);
            }
        }
    }

    if (all_keys.items.len > 1) {
        std.sort.pdq([]const u8, all_keys.items, {}, lessThanString);
    }

    std.debug.print("baseline mismatch:\n", .{});
    std.debug.print("  expected: {s}\n", .{expected_path});
    std.debug.print("  got:      {s}\n", .{got_path});

    var printed: usize = 0;
    var total: usize = 0;
    for (all_keys.items) |k| {
        const exp = expected_parsed.nodes.get(k);
        const got = got_parsed.nodes.get(k);
        if (exp == null and got != null) {
            total += 1;
            if (printed < max_diff) {
                std.debug.print("+ keyPath={s}\n", .{k});
                printed += 1;
            }
            continue;
        }
        if (exp != null and got == null) {
            total += 1;
            if (printed < max_diff) {
                std.debug.print("- keyPath={s}\n", .{k});
                printed += 1;
            }
            continue;
        }
        if (exp == null or got == null) continue;

        const exp_view = rescaleNode(exp.?, expected_parsed.decimals, common_decimals);
        const got_view = rescaleNode(got.?, got_parsed.decimals, common_decimals);

        total += try diffNodeFields(k, exp_view, got_view, common_decimals, max_diff, &printed);
    }

    if (total > printed) {
        std.debug.print("... {d} more changes not shown\n", .{total - printed});
    }
}

fn rescaleNode(node: NodeView, from_decimals: u8, to_decimals: u8) NodeView {
    if (from_decimals == to_decimals) return node;
    const mul = pow10(to_decimals - from_decimals);
    var out = node;
    if (out.rect) |r| {
        out.rect = .{ r[0] * mul, r[1] * mul, r[2] * mul, r[3] * mul };
    }
    if (out.child_rect) |r| {
        out.child_rect = .{ r[0] * mul, r[1] * mul, r[2] * mul, r[3] * mul };
    }
    return out;
}

fn diffNodeFields(
    key_path: []const u8,
    expected: NodeView,
    got: NodeView,
    decimals: u8,
    max_diff: usize,
    printed: *usize,
) !usize {
    var changes: usize = 0;

    if (!std.mem.eql(u8, expected.kind, got.kind)) {
        changes += 1;
        if (printed.* < max_diff) {
            std.debug.print("~ keyPath={s} field=kind expected={s} got={s}\n", .{ key_path, expected.kind, got.kind });
            printed.* += 1;
        }
    }
    if (!std.mem.eql(u8, expected.tag, got.tag)) {
        changes += 1;
        if (printed.* < max_diff) {
            std.debug.print("~ keyPath={s} field=tag expected={s} got={s}\n", .{ key_path, expected.tag, got.tag });
            printed.* += 1;
        }
    }
    if (!std.mem.eql(u8, expected.class_name, got.class_name)) {
        changes += 1;
        if (printed.* < max_diff) {
            std.debug.print("~ keyPath={s} field=class expected={s} got={s}\n", .{ key_path, expected.class_name, got.class_name });
            printed.* += 1;
        }
    }
    if (!optStrEq(expected.parent_key_path, got.parent_key_path)) {
        changes += 1;
        if (printed.* < max_diff) {
            std.debug.print("~ keyPath={s} field=parentKeyPath expected=", .{key_path});
            printOptStr(expected.parent_key_path);
            std.debug.print(" got=", .{});
            printOptStr(got.parent_key_path);
            std.debug.print("\n", .{});
            printed.* += 1;
        }
    }
    if (!optRectEq(expected.rect, got.rect)) {
        changes += 1;
        if (printed.* < max_diff) {
            var buf_a: [128]u8 = undefined;
            var buf_b: [128]u8 = undefined;
            const a = rectOptToString(&buf_a, expected.rect, decimals) catch "rect";
            const b = rectOptToString(&buf_b, got.rect, decimals) catch "rect";
            std.debug.print("~ keyPath={s} field=rect expected={s} got={s}\n", .{ key_path, a, b });
            printed.* += 1;
        }
    }
    if (!optRectEq(expected.child_rect, got.child_rect)) {
        changes += 1;
        if (printed.* < max_diff) {
            var buf_a: [128]u8 = undefined;
            var buf_b: [128]u8 = undefined;
            const a = rectOptToString(&buf_a, expected.child_rect, decimals) catch "rect";
            const b = rectOptToString(&buf_b, got.child_rect, decimals) catch "rect";
            std.debug.print("~ keyPath={s} field=childRect expected={s} got={s}\n", .{ key_path, a, b });
            printed.* += 1;
        }
    }
    if (expected.text_hash != got.text_hash) {
        changes += 1;
        if (printed.* < max_diff) {
            std.debug.print("~ keyPath={s} field=textHash expected={d} got={d}\n", .{ key_path, expected.text_hash, got.text_hash });
            printed.* += 1;
        }
    }

    return changes;
}

fn optStrEq(a: ?[]const u8, b: ?[]const u8) bool {
    if (a == null and b == null) return true;
    if (a == null or b == null) return false;
    return std.mem.eql(u8, a.?, b.?);
}

fn printOptStr(v: ?[]const u8) void {
    if (v) |s| {
        std.debug.print("{s}", .{s});
    } else {
        std.debug.print("null", .{});
    }
}

fn optRectEq(a: ?[4]i64, b: ?[4]i64) bool {
    if (a == null and b == null) return true;
    if (a == null or b == null) return false;
    const ra = a.?;
    const rb = b.?;
    return ra[0] == rb[0] and ra[1] == rb[1] and ra[2] == rb[2] and ra[3] == rb[3];
}

fn rectOptToString(buf: []u8, rect: ?[4]i64, decimals: u8) ![]const u8 {
    if (rect == null) return "null";

    var fb = std.io.fixedBufferStream(buf);
    const w = fb.writer();
    try w.writeByte('[');
    try writeScaledFixed(w, rect.?[0], decimals);
    try w.writeByte(',');
    try writeScaledFixed(w, rect.?[1], decimals);
    try w.writeByte(',');
    try writeScaledFixed(w, rect.?[2], decimals);
    try w.writeByte(',');
    try writeScaledFixed(w, rect.?[3], decimals);
    try w.writeByte(']');
    return fb.getWritten();
}

fn parseLayoutFile(allocator: std.mem.Allocator, bytes: []const u8) !ParsedLayout {
    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, bytes, .{ .allocate = .alloc_always });
    errdefer parsed.deinit();

    if (parsed.value != .object) return error.InvalidLayoutFile;
    const root = parsed.value.object;

    const meta_val = root.get("meta") orelse return error.InvalidLayoutFile;
    if (meta_val != .object) return error.InvalidLayoutFile;
    const meta = meta_val.object;
    const decimals = blk: {
        const v = meta.get("decimals") orelse break :blk @as(u8, 2);
        break :blk try parseJsonU8(v);
    };

    const nodes_val = root.get("nodes") orelse return error.InvalidLayoutFile;
    if (nodes_val != .array) return error.InvalidLayoutFile;
    const nodes_arr = nodes_val.array;

    var map: std.StringHashMapUnmanaged(NodeView) = .empty;
    errdefer map.deinit(allocator);

    for (nodes_arr.items) |node_val| {
        if (node_val != .object) return error.InvalidLayoutFile;
        const obj = node_val.object;
        const key_path_val = obj.get("keyPath") orelse return error.InvalidLayoutFile;
        if (key_path_val != .string) return error.InvalidLayoutFile;
        const key_path = key_path_val.string;

        const kind_val = obj.get("kind") orelse return error.InvalidLayoutFile;
        if (kind_val != .string) return error.InvalidLayoutFile;
        const kind = kind_val.string;

        const tag_val = obj.get("tag") orelse return error.InvalidLayoutFile;
        if (tag_val != .string) return error.InvalidLayoutFile;
        const tag = tag_val.string;

        const class_val = obj.get("class") orelse return error.InvalidLayoutFile;
        if (class_val != .string) return error.InvalidLayoutFile;
        const class_name = class_val.string;

        const parent_key_path = blk: {
            const pk = obj.get("parentKeyPath") orelse break :blk null;
            if (pk == .null) break :blk null;
            if (pk != .string) return error.InvalidLayoutFile;
            break :blk pk.string;
        };

        const rect = try parseRectOpt(obj.get("rect"), decimals);
        const child_rect = try parseRectOpt(obj.get("childRect"), decimals);

        const text_hash = blk: {
            const th = obj.get("textHash") orelse break :blk @as(u64, 0);
            break :blk try parseJsonU64(th);
        };

        const view: NodeView = .{
            .kind = kind,
            .tag = tag,
            .class_name = class_name,
            .parent_key_path = parent_key_path,
            .rect = rect,
            .child_rect = child_rect,
            .text_hash = text_hash,
        };

        if (map.contains(key_path)) return error.DuplicateKeyPath;
        try map.putNoClobber(allocator, key_path, view);
    }

    return .{ .decimals = decimals, .nodes = map, .parsed = parsed };
}

fn parseJsonU8(v: std.json.Value) !u8 {
    return switch (v) {
        .integer => |n| blk: {
            if (n < 0 or n > std.math.maxInt(u8)) return error.InvalidNumber;
            break :blk @intCast(n);
        },
        .float => |f| blk: {
            if (f < 0 or f > @as(f64, @floatFromInt(std.math.maxInt(u8)))) return error.InvalidNumber;
            break :blk @intFromFloat(@round(f));
        },
        else => error.InvalidNumber,
    };
}

fn parseJsonU64(v: std.json.Value) !u64 {
    return switch (v) {
        .integer => |n| blk: {
            if (n < 0) return error.InvalidNumber;
            break :blk @intCast(n);
        },
        .float => |f| blk: {
            if (f < 0) return error.InvalidNumber;
            break :blk @intFromFloat(@round(f));
        },
        .number_string => |s| blk: {
            const parsed = std.fmt.parseInt(u64, s, 10) catch return error.InvalidNumber;
            break :blk parsed;
        },
        else => error.InvalidNumber,
    };
}

fn parseRectOpt(val_opt: ?std.json.Value, decimals: u8) !?[4]i64 {
    if (val_opt == null) return null;
    const val = val_opt.?;
    if (val == .null) return null;
    if (val != .array) return error.InvalidLayoutFile;
    const arr = val.array;
    if (arr.items.len != 4) return error.InvalidLayoutFile;
    return .{
        try parseScaledNumber(arr.items[0], decimals),
        try parseScaledNumber(arr.items[1], decimals),
        try parseScaledNumber(arr.items[2], decimals),
        try parseScaledNumber(arr.items[3], decimals),
    };
}

fn parseScaledNumber(v: std.json.Value, decimals: u8) !i64 {
    const scale = pow10(decimals);
    return switch (v) {
        .integer => |n| @as(i64, @intCast(n)) * scale,
        .float => |f| blk: {
            const scaled: f64 = f * @as(f64, @floatFromInt(scale));
            break :blk @intFromFloat(@round(scaled));
        },
        else => error.InvalidNumber,
    };
}
