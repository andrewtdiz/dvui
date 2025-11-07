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

pub fn build(b: *Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const quickjs_dep = b.dependency("zig_quickjs", .{});
    const use_lld = b.option(bool, "use-lld", "Link executables with lld");
    const linux_display_backend = detectLinuxDisplayBackend(b, target);

    const build_options = initBuildOptions(b);
    const dvui_mod = addDvuiModule(b, target, optimize, build_options, .{
        .image = false,
        .image_write = false,
    });
    const dvui_lib = addDvuiLibrary(b, target, optimize, build_options, .{
        .image = false,
        .image_write = false,
    });
    const raylib_mod = addRaylibBackend(b, target, optimize, linux_display_backend);

    raylib_mod.addImport("dvui", dvui_mod);
    dvui_mod.addImport("backend", raylib_mod);

    const root_mod = b.createModule(.{
        .root_source_file = b.path("examples/raylib-ontop.zig"),
        .target = target,
        .optimize = optimize,
    });
    root_mod.addImport("dvui", dvui_mod);
    root_mod.addImport("raylib-backend", raylib_mod);
    root_mod.addImport("quickjs", quickjs_dep.module("quickjs"));

    if (target.result.os.tag == .windows) {
        if (b.lazyDependency("win32", .{})) |zigwin32| {
            root_mod.addImport("win32", zigwin32.module("win32"));
        }
    }

    const exe = b.addExecutable(.{
        .name = "raylib-ontop",
        .root_module = root_mod,
        .use_lld = use_lld,
    });

    exe.linkLibrary(quickjs_dep.artifact("zig-quickjs"));

    if (target.result.os.tag == .windows) {
        exe.win32_manifest = b.path("src/main.manifest");
        exe.subsystem = .Windows;
    }

    b.installArtifact(exe);
    b.installArtifact(dvui_lib);

    const dvui_lib_step = b.step("dvui-lib", "Build the dvui static library");
    dvui_lib_step.dependOn(&dvui_lib.step);

    const run_cmd = b.addRunArtifact(exe);
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the raylib ontop example");
    run_step.dependOn(&run_cmd.step);
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
    stb: struct {
        image: bool,
        image_write: bool,
    },
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
    stb: struct {
        image: bool,
        image_write: bool,
    },
) *Build.Module {
    const dvui_mod = b.addModule("dvui", .{
        .root_source_file = b.path("src/dvui.zig"),
        .target = target,
        .optimize = optimize,
    });
    configureDvuiModule(b, dvui_mod, target, optimize, build_options, stb);
    return dvui_mod;
}

fn addDvuiLibrary(
    b: *Build,
    target: Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    build_options: *Build.Step.Options,
    stb: struct {
        image: bool,
        image_write: bool,
    },
) *std.Build.Step.Compile {
    const dvui_lib = b.addStaticLibrary(.{
        .name = "dvui",
        .root_source_file = b.path("src/dvui.zig"),
        .target = target,
        .optimize = optimize,
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
    const raylib_mod = b.addModule("raylib-backend", .{
        .root_source_file = b.path("src/backends/raylib.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    const ray_dep = b.lazyDependency("raylib", .{
        .target = target,
        .optimize = optimize,
        .linux_display_backend = linux_display_backend,
    }) orelse std.debug.panic("raylib dependency not available", .{});

    raylib_mod.addIncludePath(ray_dep.path("src"));
    raylib_mod.addIncludePath(ray_dep.path("src/external/glfw/include"));
    raylib_mod.addIncludePath(ray_dep.path("src/external/glfw/include/GLFW"));
    raylib_mod.linkLibrary(ray_dep.artifact("raylib"));

    const raygui_dep = b.lazyDependency("raygui", .{}) orelse std.debug.panic("raygui dependency not available", .{});
    raylib_mod.addIncludePath(raygui_dep.path("src"));

    const write_files = b.addWriteFiles();
    const raygui_impl = write_files.add("raygui.c", "#define RAYGUI_IMPLEMENTATION\n#include \"raygui.h\"\n");
    raylib_mod.addCSourceFile(.{ .file = raygui_impl });

    return raylib_mod;
}
