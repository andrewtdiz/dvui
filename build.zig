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
    const dvui_mod = addDvuiModule(b, target, optimize, build_options, StbOptions{
        .image = false,
        .image_write = false,
    });
    const dvui_lib = addDvuiLibrary(b, target, optimize, build_options, StbOptions{
        .image = false,
        .image_write = false,
    });
    const retained_mod = addRetainedModule(b, target, optimize, dvui_mod);
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

    const root_mod = b.createModule(.{
        .root_source_file = b.path("src/raylib-ontop-zig.zig"),
        .target = target,
        .optimize = optimize,
    });
    root_mod.addImport("dvui", dvui_mod);
    root_mod.addImport("raylib-backend", raylib_mod);

    const retained_harness_mod = b.createModule(.{
        .root_source_file = b.path("src/retained-harness.zig"),
        .target = target,
        .optimize = optimize,
    });
    retained_harness_mod.addImport("dvui", dvui_mod);
    retained_harness_mod.addImport("dvui_retained", retained_mod);
    retained_harness_mod.addImport("raylib-backend", raylib_mod);

    if (raylib_dep) |dep| {
        root_mod.addImport("raylib", dep.module("raylib"));
    }

    const wgpu_dep = b.dependency("wgpu_native_zig", .{
        .target = target,
        .optimize = optimize,
    });
    root_mod.addImport("wgpu", wgpu_dep.module("wgpu"));
    const luaz_dep = b.dependency("luaz", .{
        .target = target,
        .optimize = optimize,
    });
    root_mod.addImport("luaz", luaz_dep.module("luaz"));

    const native_module = b.createModule(.{
        .root_source_file = b.path("src/integrations/native_renderer/mod.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    native_module.addImport("dvui", dvui_mod);
    native_module.addImport("raylib-backend", raylib_mod);
    native_module.addImport("retained", retained_mod);

    // Create solid module for native_renderer

    const solid_mod = b.createModule(.{
        .root_source_file = b.path("src/integrations/solid/mod.zig"),
        .target = target,
        .optimize = optimize,
    });
    solid_mod.addImport("dvui", dvui_mod);

    const luau_ui_mod = b.createModule(.{
        .root_source_file = b.path("src/integrations/luau_ui/mod.zig"),
        .target = target,
        .optimize = optimize,
    });
    luau_ui_mod.addImport("solid", solid_mod);
    luau_ui_mod.addImport("luaz", luaz_dep.module("luaz"));

    native_module.addImport("solid", solid_mod);
    native_module.addImport("luaz", luaz_dep.module("luaz"));
    native_module.addImport("luau_ui", luau_ui_mod);

    const luau_runner_mod = b.createModule(.{
        .root_source_file = b.path("src/luau-native-runner.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    luau_runner_mod.addImport("native_renderer", native_module);
    luau_runner_mod.addImport("luaz", luaz_dep.module("luaz"));
    luau_runner_mod.addImport("solid", solid_mod);

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

    const exe = b.addExecutable(.{
        .name = "raylib-ontop",
        .root_module = root_mod,
        .use_lld = use_lld,
    });
    if (raylib_dep) |dep| {
        exe.linkLibrary(dep.artifact("raylib"));
    }

    if (target.result.os.tag == .windows) {
        exe.win32_manifest = b.path("src/main.manifest");
        exe.subsystem = .Console;
    }

    const retained_exe = b.addExecutable(.{
        .name = "retained-harness",
        .root_module = retained_harness_mod,
        .use_lld = use_lld,
    });
    if (raylib_dep) |dep| {
        retained_exe.linkLibrary(dep.artifact("raylib"));
    }

    const luau_runner_exe = b.addExecutable(.{
        .name = "luau-native-runner",
        .root_module = luau_runner_mod,
        .use_lld = use_lld,
    });
    if (raylib_dep) |dep| {
        luau_runner_exe.linkLibrary(dep.artifact("raylib"));
    }

    if (target.result.os.tag == .windows) {
        retained_exe.win32_manifest = b.path("src/main.manifest");
        retained_exe.subsystem = .Console;
    }

    b.installArtifact(exe);
    b.installArtifact(retained_exe);
    b.installArtifact(luau_runner_exe);
    b.installArtifact(dvui_lib);

    const dvui_lib_step = b.step("dvui-lib", "Build the dvui static library");
    dvui_lib_step.dependOn(&dvui_lib.step);

    const run_cmd = b.addRunArtifact(exe);
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the raylib ontop example");
    run_step.dependOn(&run_cmd.step);

    const retained_run_cmd = b.addRunArtifact(retained_exe);
    if (b.args) |args| {
        retained_run_cmd.addArgs(args);
    }

    const retained_run_step = b.step("run-retained", "Run the retained harness");
    retained_run_step.dependOn(&retained_run_cmd.step);

    const luau_run_cmd = b.addRunArtifact(luau_runner_exe);
    if (b.args) |args| {
        luau_run_cmd.addArgs(args);
    }

    const luau_run_step = b.step("luau", "Run the Luau native renderer demo");
    luau_run_step.dependOn(&luau_run_cmd.step);
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
) void {
    module.addOptions("build_options", build_options);
    module.addImport("svg2tvg", b.dependency("svg2tvg", .{
        .target = target,
        .optimize = optimize,
    }).module("svg2tvg"));

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

        module.addIncludePath(b.path("vendor/tfd"));
        module.addCSourceFiles(.{ .files = &.{"vendor/tfd/tinyfiledialogs.c"} });

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
) *Build.Module {
    const dvui_mod = b.addModule("dvui", .{
        .root_source_file = b.path("src/dvui.zig"),
        .target = target,
        .optimize = optimize,
    });
    configureDvuiModule(b, dvui_mod, target, optimize, build_options, stb);
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
    configureDvuiModule(b, dvui_lib.root_module, target, optimize, build_options, stb);
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
