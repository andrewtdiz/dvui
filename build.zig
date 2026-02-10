const std = @import("std");
const Build = std.Build;

pub const LinuxDisplayBackend = enum {
    X11,
    Wayland,
    Both,
};

const AccesskitOptions = enum {
    static,
    shared,
    off,
};

const StbOptions = struct {
    image: bool,
    image_write: bool,
};

pub fn build(b: *Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const use_lld = b.option(bool, "use-lld", "Link executables with lld");
    const linux_display_backend = detectLinuxDisplayBackend(b, target);

    const build_options = initBuildOptions(b);
    const msdf_mod = b.createModule(.{
        .root_source_file = b.path("deps/msdf_zig/msdf_zig.zig"),
        .target = target,
        .optimize = optimize,
    });
    const dvui_mod = addDvuiModule(b, target, optimize, build_options, StbOptions{
        .image = false,
        .image_write = false,
    }, msdf_mod);
    const dvui_lib = addDvuiLibrary(b, target, optimize, build_options, StbOptions{
        .image = false,
        .image_write = false,
    }, msdf_mod);
    const wgpu_dep = b.dependency("wgpu_native_zig", .{
        .target = target,
        .optimize = optimize,
    });
    const wgpu_mod = wgpu_dep.module("wgpu");
    const dvui_wgpu_mod = b.createModule(.{
        .root_source_file = b.path("src/dvui.zig"),
        .target = target,
        .optimize = optimize,
    });
    configureDvuiModule(b, dvui_wgpu_mod, target, optimize, build_options, StbOptions{
        .image = false,
        .image_write = false,
    }, msdf_mod);
    const wgpu_backend_mod = b.createModule(.{
        .root_source_file = b.path("src/backends/wgpu.zig"),
        .target = target,
        .optimize = optimize,
    });
    wgpu_backend_mod.addImport("wgpu", wgpu_mod);
    wgpu_backend_mod.addImport("dvui", dvui_wgpu_mod);
    wgpu_backend_mod.addImport("msdf_zig", msdf_mod);
    dvui_wgpu_mod.addImport("backend", wgpu_backend_mod);
    const retained_mod = addRetainedModule(b, target, optimize, dvui_wgpu_mod);
    const raylib_mod = addRaylibBackend(b, target, optimize, linux_display_backend);

    raylib_mod.addImport("dvui", dvui_mod);
    dvui_mod.addImport("backend", raylib_mod);

    const raylib_dep = b.lazyDependency(
        "raylib_zig",
        .{
            .target = target,
            .optimize = optimize,
            .linux_display_backend = linux_display_backend,
        },
    );

    const luaz_dep = b.dependency("luaz", .{
        .target = target,
        .optimize = optimize,
    });

    const event_payload_mod = b.createModule(.{
        .root_source_file = b.path("src/native_renderer/event_payload.zig"),
        .target = target,
        .optimize = optimize,
    });
    event_payload_mod.addImport("luaz", luaz_dep.module("luaz"));
    event_payload_mod.addImport("retained", retained_mod);

    const native_module = b.createModule(.{
        .root_source_file = b.path("src/native_renderer/mod.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    const raylib_input_mod = createRaylibBackendModule(b, target, optimize, linux_display_backend);
    raylib_input_mod.addImport("dvui", dvui_wgpu_mod);
    const webgpu_mod = b.createModule(.{
        .root_source_file = b.path("src/backends/webgpu.zig"),
        .target = target,
        .optimize = optimize,
    });
    if (target.result.os.tag == .macos) {
        webgpu_mod.addCSourceFiles(.{
            .files = &.{"src/backends/webgpu/platform_macos_metal_layer.m"},
            .flags = &.{"-fobjc-arc"},
        });
        webgpu_mod.linkFramework("QuartzCore", .{});
        webgpu_mod.linkFramework("Metal", .{});
    }
    webgpu_mod.addImport("dvui", dvui_wgpu_mod);
    webgpu_mod.addImport("wgpu", wgpu_mod);
    webgpu_mod.addImport("wgpu-backend", wgpu_backend_mod);
    webgpu_mod.addImport("raylib-backend", raylib_input_mod);

    native_module.addImport("dvui", dvui_wgpu_mod);
    native_module.addImport("raylib-backend", raylib_input_mod);
    native_module.addImport("webgpu", webgpu_mod);
    native_module.addImport("wgpu", wgpu_mod);
    native_module.addImport("wgpu-backend", wgpu_backend_mod);
    native_module.addImport("retained", retained_mod);
    native_module.addImport("event_payload", event_payload_mod);

    const solidluau_embedded_mod = b.createModule(.{
        .root_source_file = b.path("solidluau_embedded.zig"),
        .target = target,
        .optimize = optimize,
    });
    native_module.addImport("solidluau_embedded", solidluau_embedded_mod);

    const luau_ui_mod = b.createModule(.{
        .root_source_file = b.path("src/native_renderer/luau_ui.zig"),
        .target = target,
        .optimize = optimize,
    });
    luau_ui_mod.addImport("retained", retained_mod);
    luau_ui_mod.addImport("luaz", luaz_dep.module("luaz"));

    native_module.addImport("luaz", luaz_dep.module("luaz"));
    native_module.addImport("luau_ui", luau_ui_mod);

    const luau_runner_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    luau_runner_mod.addImport("native_renderer", native_module);
    luau_runner_mod.addImport("luaz", luaz_dep.module("luaz"));

    if (target.result.os.tag == .windows) {
        if (b.lazyDependency("win32", .{})) |zigwin32| {
            native_module.addImport("win32", zigwin32.module("win32"));
        }
    }

    const native_lib = b.addLibrary(.{
        .name = "native_renderer",
        .root_module = native_module,
        .linkage = .dynamic,
    });

    if (raylib_dep) |dep| {
        native_lib.linkLibrary(dep.artifact("raylib"));
    }

    b.installArtifact(native_lib);

    const luau_runner_exe = b.addExecutable(.{
        .name = "luau-native-runner",
        .root_module = luau_runner_mod,
        .use_lld = use_lld,
    });
    if (raylib_dep) |dep| {
        luau_runner_exe.linkLibrary(dep.artifact("raylib"));
    }

    b.installArtifact(luau_runner_exe);
    b.installArtifact(dvui_lib);

    const dvui_lib_step = b.step("dvui-lib", "Build the dvui static library");
    dvui_lib_step.dependOn(&dvui_lib.step);

    const luau_run_cmd = b.addRunArtifact(luau_runner_exe);
    if (b.args) |args| {
        luau_run_cmd.addArgs(args);
    }

    const luau_run_step = b.step("luau", "Run the Luau native renderer demo");
    luau_run_step.dependOn(&luau_run_cmd.step);

    const luau_smoke_mod = b.createModule(.{
        .root_source_file = b.path("tools/luau_smoke.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    luau_smoke_mod.addImport("luaz", luaz_dep.module("luaz"));
    luau_smoke_mod.addImport("event_payload", event_payload_mod);
    luau_smoke_mod.addImport("solidluau_embedded", solidluau_embedded_mod);
    luau_smoke_mod.addImport("retained", retained_mod);
    luau_smoke_mod.addImport("luau_ui", luau_ui_mod);

    const luau_smoke_exe = b.addExecutable(.{
        .name = "luau-smoke",
        .root_module = luau_smoke_mod,
        .use_lld = use_lld,
    });

    const luau_smoke_run_cmd = b.addRunArtifact(luau_smoke_exe);
    const luau_smoke_step = b.step("luau-smoke", "Run headless Luau smoke tests");
    luau_smoke_step.dependOn(&luau_smoke_run_cmd.step);

    const luau_layout_dump_mod = b.createModule(.{
        .root_source_file = b.path("tools/luau_layout_dump_main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    luau_layout_dump_mod.addImport("native_renderer", native_module);
    luau_layout_dump_mod.addImport("dvui", dvui_wgpu_mod);
    luau_layout_dump_mod.addImport("retained", retained_mod);

    const luau_layout_dump_exe = b.addExecutable(.{
        .name = "luau-layout-dump",
        .root_module = luau_layout_dump_mod,
        .use_lld = use_lld,
    });
    if (raylib_dep) |dep| {
        luau_layout_dump_exe.linkLibrary(dep.artifact("raylib"));
    }
    b.installArtifact(luau_layout_dump_exe);

    const screenshot_step = b.step("screenshot", "Run the Luau demo and capture a dvui window screenshot");
    const luau_screenshot_step = b.step("luau-screenshot", "Run the Luau demo and capture a dvui window screenshot");
    if (b.graph.host.result.os.tag != .windows or target.result.os.tag != .windows) {
        const fail = b.addFail("luau screenshot requires a Windows host and target");
        screenshot_step.dependOn(&fail.step);
        luau_screenshot_step.dependOn(&fail.step);
    } else {
        const luau_screenshot_run_cmd = b.addRunArtifact(luau_runner_exe);
        if (b.args) |args| {
            luau_screenshot_run_cmd.addArgs(args);
        }
        luau_screenshot_run_cmd.setEnvironmentVariable("DVUI_SCREENSHOT_AUTO", "1");
        luau_screenshot_run_cmd.stdio = .inherit;

        screenshot_step.dependOn(&luau_screenshot_run_cmd.step);
        luau_screenshot_step.dependOn(&luau_screenshot_run_cmd.step);
    }
}

fn detectLinuxDisplayBackend(b: *Build, target: Build.ResolvedTarget) LinuxDisplayBackend {
    if (b.option(LinuxDisplayBackend, "linux_display_backend", "Select the raylib display backend on Linux")) |backend| {
        return backend;
    }

    if (target.result.os.tag != .linux) {
        return .Both;
    }

    return blk: {
        const wayland_display = std.process.getEnvVarOwned(b.allocator, "WAYLAND_DISPLAY") catch |err| switch (err) {
            error.EnvironmentVariableNotFound => break :blk .X11,
            else => @panic("Unknown error checking for WAYLAND_DISPLAY"),
        };
        defer b.allocator.free(wayland_display);

        const x11_display = std.process.getEnvVarOwned(b.allocator, "DISPLAY") catch |err| switch (err) {
            error.EnvironmentVariableNotFound => break :blk .Wayland,
            else => @panic("Unknown error checking for DISPLAY"),
        };
        defer b.allocator.free(x11_display);

        break :blk .Both;
    };
}

fn initBuildOptions(b: *Build) *Build.Step.Options {
    const opts = b.addOptions();
    opts.addOption(?[]const u8, "snapshot_image_suffix", null);
    opts.addOption(?[]const u8, "image_dir", null);
    opts.addOption(?u8, "log_stack_trace", null);
    opts.addOption(?bool, "log_error_trace", null);
    opts.addOption(AccesskitOptions, "accesskit", .off);
    return opts;
}

fn configureDvuiModule(
    b: *Build,
    module: *Build.Module,
    target: Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    build_options: *Build.Step.Options,
    stb: StbOptions,
    msdf_mod: *Build.Module,
) void {
    module.addOptions("build_options", build_options);
    module.addImport("dvui_assets", b.createModule(.{
        .root_source_file = b.path("assets/mod.zig"),
        .target = target,
        .optimize = optimize,
    }));
    module.addImport("svg2tvg", b.dependency("svg2tvg", .{
        .target = target,
        .optimize = optimize,
    }).module("svg2tvg"));
    module.addImport("msdf_zig", msdf_mod);

    if (target.result.os.tag == .windows) {
        module.linkSystemLibrary("comdlg32", .{});
        module.linkSystemLibrary("ole32", .{});
    }

    const stb_source = "vendor/stb/";
    module.addIncludePath(b.path(stb_source));

    if (target.result.cpu.arch == .wasm32 or target.result.cpu.arch == .wasm64) {
        var files: [3][]const u8 = undefined;
        var len: usize = 0;
        if (stb.image) {
            files[len] = stb_source ++ "stb_image_impl.c";
            len += 1;
        }
        if (stb.image_write) {
            files[len] = stb_source ++ "stb_image_write_impl.c";
            len += 1;
        }
        files[len] = stb_source ++ "stb_truetype_impl.c";
        len += 1;
        module.addCSourceFiles(.{
            .files = files[0..len],
            .flags = &.{ "-DINCLUDE_CUSTOM_LIBC_FUNCS=1", "-DSTBI_NO_STDLIB=1", "-DSTBIW_NO_STDLIB=1" },
        });
    } else {
        if (stb.image) {
            module.addCSourceFiles(.{ .files = &.{stb_source ++ "stb_image_impl.c"} });
        }
        if (stb.image_write) {
            module.addCSourceFiles(.{ .files = &.{stb_source ++ "stb_image_write_impl.c"} });
        }
        module.addCSourceFiles(.{ .files = &.{stb_source ++ "stb_truetype_impl.c"} });

        if (b.systemIntegrationOption("freetype", .{})) {
            module.linkSystemLibrary("freetype2", .{});
        } else if (b.lazyDependency("freetype", .{
            .target = target,
            .optimize = optimize,
        })) |fd| {
            module.linkLibrary(fd.artifact("freetype"));
        }
    }
}

fn addDvuiModule(
    b: *Build,
    target: Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    build_options: *Build.Step.Options,
    stb: StbOptions,
    msdf_mod: *Build.Module,
) *Build.Module {
    const dvui_mod = b.addModule("dvui", .{
        .root_source_file = b.path("src/dvui.zig"),
        .target = target,
        .optimize = optimize,
    });
    configureDvuiModule(b, dvui_mod, target, optimize, build_options, stb, msdf_mod);
    return dvui_mod;
}

fn addRetainedModule(
    b: *Build,
    target: Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    dvui_mod: *Build.Module,
) *Build.Module {
    const retained_mod = b.addModule("dvui_retained", .{
        .root_source_file = b.path("src/retained/mod.zig"),
        .target = target,
        .optimize = optimize,
    });
    retained_mod.addImport("dvui", dvui_mod);
    const yoga_dep = b.dependency("zig_yoga", .{
        .target = target,
        .optimize = optimize,
    });
    retained_mod.addImport("yoga-zig", yoga_dep.module("yoga-zig"));
    return retained_mod;
}

fn addDvuiLibrary(
    b: *Build,
    target: Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    build_options: *Build.Step.Options,
    stb: StbOptions,
    msdf_mod: *Build.Module,
) *std.Build.Step.Compile {
    const dvui_module = b.createModule(.{
        .root_source_file = b.path("src/dvui.zig"),
        .target = target,
        .optimize = optimize,
    });

    const dvui_lib = b.addLibrary(.{
        .name = "dvui",
        .linkage = .static,
        .root_module = dvui_module,
    });
    configureDvuiModule(b, dvui_lib.root_module, target, optimize, build_options, stb, msdf_mod);
    return dvui_lib;
}

fn addRaylibBackend(
    b: *Build,
    target: Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    linux_display_backend: LinuxDisplayBackend,
) *Build.Module {
    const raylib_backend_mod = b.addModule("raylib_zig", .{
        .root_source_file = b.path("src/backends/raylib-zig.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    const maybe_ray = b.lazyDependency(
        "raylib_zig",
        .{
            .target = target,
            .optimize = optimize,
            .linux_display_backend = linux_display_backend,
        },
    );
    if (maybe_ray) |ray| {
        raylib_backend_mod.linkLibrary(ray.artifact("raylib"));
        raylib_backend_mod.addImport("raylib", ray.module("raylib"));
        raylib_backend_mod.addImport("raygui", ray.module("raygui"));
    }

    const maybe_glfw = b.lazyDependency(
        "zglfw",
        .{
            .target = target,
            .optimize = optimize,
        },
    );
    if (maybe_glfw) |glfw| {
        raylib_backend_mod.addImport("zglfw", glfw.module("root"));
    }

    return raylib_backend_mod;
}

fn createRaylibBackendModule(
    b: *Build,
    target: Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    linux_display_backend: LinuxDisplayBackend,
) *Build.Module {
    const raylib_backend_mod = b.createModule(.{
        .root_source_file = b.path("src/backends/raylib-zig.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    const maybe_ray = b.lazyDependency(
        "raylib_zig",
        .{
            .target = target,
            .optimize = optimize,
            .linux_display_backend = linux_display_backend,
        },
    );
    if (maybe_ray) |ray| {
        raylib_backend_mod.linkLibrary(ray.artifact("raylib"));
        raylib_backend_mod.addImport("raylib", ray.module("raylib"));
        raylib_backend_mod.addImport("raygui", ray.module("raygui"));
    }

    const maybe_glfw = b.lazyDependency(
        "zglfw",
        .{
            .target = target,
            .optimize = optimize,
        },
    );
    if (maybe_glfw) |glfw| {
        raylib_backend_mod.addImport("zglfw", glfw.module("root"));
    }

    return raylib_backend_mod;
}
