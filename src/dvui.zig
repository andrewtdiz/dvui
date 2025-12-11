//! [DVUI](https://david-vanderson.github.io/) is a general purpose Zig GUI toolkit.
//!
//! ![<Examples-demo.png>](Examples-demo.png)
//!
//! `dvui` module contains all the top level declarations provide all declarations required by client code. - i.e. `const dvui = @import("dvui");` is the only required import.
//!
//! Most UI element are expected to be created via high level function like `dvui.button`, which instantiate the corresponding lower level `dvui.ButtonWidget` for you.
//!
//! Custom widget can be done for simple cases my combining different high level function. For more advance usages, the user is expected to copy-paste the content of the high level functions as a starting point to combine the widgets on the lower level. More informations is available in the [project's readme](https://github.com/david-vanderson/dvui/blob/main/README.md).
//!
//! A complete list of available widgets can be found under `dvui.widgets`.
//!
//! ## Backends
//! - [Web](#dvui.backends.web)
//! - [rayLib](#dvui.backends.raylib)
//! - [Dx11](#dvui.backends.dx11)
//! - [WGPU](#dvui.backends.wgpu)
//! - [Testing](#dvui.backends.testing)
//!
const std = @import("std");
pub const math = std.math;
pub const fnv = std.hash.Fnv1a_64;
const builtin = @import("builtin");
const core = @import("core/mod.zig");
const render_mod = @import("render/mod.zig");
const text_mod = @import("text/mod.zig");
const layout_mod = @import("layout/mod.zig");
const theming = @import("theming/mod.zig");
const widgets_mod = @import("widgets/mod.zig");
const window_mod = @import("window/mod.zig");
const accessibility_mod = @import("accessibility/mod.zig");
const platform_mod = @import("platform/mod.zig");
const utils_mod = @import("utils/mod.zig");
const testing_mod = @import("testing/mod.zig");
const backends_mod = @import("backends/mod.zig");

/// Using this in application code will hinder ZLS from referencing the correct backend.
/// To avoid this import the backend directly from the applications build.zig
///
/// ```zig
/// // build.zig (example with the raylib backend)
/// mod.addImport("dvui", dvui_mod);
/// mod.addImport("backend", raylib_mod);
///
/// // src/main.zig
/// const dvui = @import("dvui");
/// const Backend = @import("backend");
/// ```
pub const backend = @import("backend");
const tvg = @import("svg2tvg");

pub const AccessKit = accessibility_mod.AccessKit;
pub const App = window_mod.App;
pub const Backend = backends_mod.Backend;
pub const Color = core.Color;
pub const Data = core.Data;
pub const Dialogs = platform_mod.dialogs;
pub const Dialog = Dialogs.Dialog;
/// Toasts are just specialized dialogs
pub const Toast = Dialog;
pub const ToastIterator = Dialogs.Iterator;
pub const Dragging = window_mod.Dragging;
pub const easing = layout_mod.easing;
pub const enums = core.enums;
pub const Event = window_mod.Event;
pub const Font = text_mod.Font;
pub const FontError = Font.Error;
/// DEPRECATED: Use `Font.Cache.TTFEntry` directly
///
/// The bytes of a truetype font file and whether to free it.
pub const FontBytesEntry = Font.Cache.TTFEntry;
/// DEPRECATED: Use `Font.Cache.Entry` directly
pub const FontCacheEntry = Font.Cache.Entry;
const io_compat = platform_mod.io_compat;
pub const JPGEncoder = render_mod.JPGEncoder;
pub const layout = layout_mod.layout;
pub const BasicLayout = layout_mod.BasicLayout;
pub const Alignment = layout_mod.Alignment;
pub const PlaceOnScreenAvoid = layout_mod.PlaceOnScreenAvoid;
pub const placeOnScreen = layout_mod.placeOnScreen;
pub const native_dialogs = platform_mod.native_dialogs;
pub const dialogWasmFileOpen = native_dialogs.Wasm.open;
pub const wasmFileUploaded = native_dialogs.Wasm.uploaded;
pub const dialogWasmFileOpenMultiple = native_dialogs.Wasm.openMultiple;
pub const wasmFileUploadedMultiple = native_dialogs.Wasm.uploadedMultiple;
pub const dialogNativeFileOpen = native_dialogs.Native.open;
pub const dialogNativeFileOpenMultiple = native_dialogs.Native.openMultiple;
pub const dialogNativeFileSave = native_dialogs.Native.save;
pub const dialogNativeFolderSelect = native_dialogs.Native.folderSelect;
pub const Options = core.Options;
pub const Path = render_mod.Path;
pub const PNGEncoder = render_mod.PNGEncoder;
pub const Point = core.Point;
pub const Rect = core.Rect;
pub const RectScale = core.RectScale;
pub const render = render_mod.render;
pub const RenderCommand = render_mod.RenderCommand;
pub const RenderTarget = render_mod.RenderTarget;
pub const renderTarget = render_mod.RenderTarget.setAsCurrent;
pub const renderTriangles = render.renderTriangles;
pub const renderTextOptions = render.TextOptions;
pub const renderText = render.renderText;
pub const RenderTextureOptions = render.TextureOptions;
pub const renderTexture = render.renderTexture;
pub const renderIcon = render.renderIcon;
pub const renderImage = render.renderImage;
pub const ScrollInfo = layout_mod.ScrollInfo;
pub const selection = text_mod.selection;
pub const Size = core.Size;
pub const struct_ui = utils_mod.struct_ui;
pub const Subwindows = window_mod.Subwindows;
pub const testing = testing_mod.testing;
pub const Texture = render_mod.Texture;
pub const TextureTarget = Texture.Target;
/// Source data for `image()` and `imageSize()`.
pub const ImageSource = Texture.ImageSource;
pub const imageSize = Texture.ImageSource.size;
pub const textureCreate = Texture.create;
pub const textureUpdate = Texture.update;
pub const textureCreateTarget = Texture.Target.create;
pub const textureReadTarget = Texture.readTarget;
pub const textureFromTarget = Texture.fromTarget;
pub const textureDestroyLater = Texture.destroyLater;
pub const Theme = theming.Theme;
pub const TrackingAutoHashMap = utils_mod.tracking_hash_map.TrackingAutoHashMap;
pub const Triangles = render_mod.Triangles;
pub const Vertex = core.Vertex;
pub const Widget = @import("widgets/widget.zig");
pub const WidgetData = @import("widgets/widget_data.zig");
pub const widgets = widgets_mod;
pub const AnimateWidget = widgets.AnimateWidget;
pub const BoxWidget = widgets.BoxWidget;
pub const FlexBoxWidget = widgets.FlexBoxWidget;
pub const ButtonWidget = widgets.ButtonWidget;
pub const IconWidget = widgets.IconWidget;
pub const LabelWidget = widgets.LabelWidget;
pub const ScrollBarWidget = widgets.ScrollBarWidget;
pub const SelectionWidget = widgets.SelectionWidget;
pub const ColorPickerWidget = widgets.ColorPickerWidget;
pub const GizmoWidget = widgets.GizmoWidget;
pub const MenuWidget = widgets.MenuWidget;
pub const MenuItemWidget = widgets.MenuItemWidget;
pub const PanedWidget = widgets.PanedWidget;
pub const PlotWidget = widgets.PlotWidget;
pub const ReorderWidget = widgets.ReorderWidget;
pub const Reorderable = ReorderWidget.Reorderable;
pub const ScaleWidget = widgets.ScaleWidget;
pub const TreeWidget = widgets.TreeWidget;
pub const Window = window_mod.Window;

// Note : Import widgets this way (i.e. importing them via `src/widgets/mod.zig`
// so they are nicely referenced in docs.
// Having `pub const widgets = ` allow to refer the page with `dvui.widgets` in doccoment

/// Accessibility
pub const accesskit_enabled = @import("build_options").accesskit != .off and backend.kind != .testing and backend.kind != .web;

// When linking to accesskit for non-msvc builds, the _fltuser symbol is
// undefined. Zig only defines this symbol for abi = .mscv and abi = .none,
// which makes gnu and musl builds break.  Until we can build and link the
// accesskit c library with zig, we need this work-around as both the msvc and
// mingw builds of accesskit reference this symbol.
comptime {
    if (accesskit_enabled and builtin.os.tag == .windows and builtin.cpu.arch.isX86()) {
        @export(&_fltused, .{ .name = "_fltused", .linkage = .weak });
    }
}
var _fltused: c_int = 1;

/// Gets a texture from the internal texture cache. If a texture
/// isn't used for one frame it gets removed from the cache and
/// destroyed.
///
/// If you want to lazily create a texture, you could do:
/// ```zig
/// const texture = dvui.textureGetCached(key) orelse blk: {
///     const texture = ...; // Create your texture here
///     dvui.textureAddToCache(key, texture);
///     break :blk texture;
/// }
/// ```
pub fn textureGetCached(key: Texture.Cache.Key) ?Texture {
    return currentWindow().texture_cache.get(key);
}
/// See `Texture.Cache.add`
pub fn textureAddToCache(key: Texture.Cache.Key, texture: Texture) void {
    currentWindow().texture_cache.add(currentWindow().gpa, key, texture) catch |err| {
        dvui.logError(@src(), err, "Could not add texture with key {x} to cache", .{key});
        return;
    };
}
/// See `Texture.Cache.invalidate`
pub fn textureInvalidateCache(key: Texture.Cache.Key) void {
    currentWindow().texture_cache.invalidate(currentWindow().gpa, key) catch |err| {
        dvui.logError(@src(), err, "Could not invalidate texture with key {x}", .{key});
        return;
    };
}

/// See `Dragging.preStart`
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn dragPreStart(p: Point.Physical, options: Dragging.StartOptions) void {
    currentWindow().dragging.preStart(p, options);
}
/// See `Dragging.start`
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn dragStart(p: Point.Physical, options: Dragging.StartOptions) void {
    currentWindow().dragging.start(p, options);
}
/// Get offset previously given to `dragPreStart` or `dragStart`.
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn dragOffset() Point.Physical {
    return currentWindow().dragging.offset;
}
/// Get rect from mouse position using offset and size previously given to
/// `dragPreStart` or `dragStart`.
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn dragRect() Rect.Physical {
    return currentWindow().dragging.getRect();
}
/// See `Dragging.get`
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn dragging(p: Point.Physical, name: ?[]const u8) ?Point.Physical {
    return currentWindow().dragging.get(p, .{ .name = name, .window_natural_scale = currentWindow().natural_scale });
}
/// True if `dragging` and `dragStart` (or `dragPreStart`) was the given name.
///
/// Use to know when a cross-widget drag is in progress.
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn dragName(name: ?[]const u8) bool {
    return currentWindow().dragging.matchName(name);
}
/// Stop any mouse drag.
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn dragEnd() void {
    currentWindow().dragging.end();
}

pub const wasm = (builtin.target.cpu.arch == .wasm32 or builtin.target.cpu.arch == .wasm64);
pub const useFreeType = !wasm;

/// The amount of physical pixels to scroll per "tick" of the scroll wheel
pub var scroll_speed: f32 = 20;

/// Used as a default maximum in various places:
/// * Options.max_size_content
/// * Font.textSizeEx max_width
///
/// This is a compromise between desires:
/// * gives a decent range
/// * is a normal number (not nan/inf) that works in normal math
/// * can still have some extra added to it (like padding)
/// * float precision in this range (0.125) is small enough so integer stuff still works
///
/// If positions/sizes are getting into this range, then likely something is going wrong.
pub const max_float_safe: f32 = 2_000_000; // 2000000 and 2e6 for searchability

pub const c = @cImport({
    // musl fails to compile saying missing "bits/setjmp.h", and nobody should
    // be using setjmp anyway
    @cDefine("_SETJMP_H", "1");

    if (useFreeType) {
        @cInclude("freetype/ftadvanc.h");
        @cInclude("freetype/ftbbox.h");
        @cInclude("freetype/ftbitmap.h");
        @cInclude("freetype/ftcolor.h");
        @cInclude("freetype/ftlcdfil.h");
        @cInclude("freetype/ftsizes.h");
        @cInclude("freetype/ftstroke.h");
        @cInclude("freetype/fttrigon.h");
    } else {
        @cInclude("stb_truetype.h");
    }

    if (wasm) {
        @cDefine("STBI_NO_STDIO", "1");
        @cDefine("STBI_NO_STDLIB", "1");
        @cDefine("STBIW_NO_STDLIB", "1");
    }
    @cInclude("stb_image.h");
    @cInclude("stb_image_write.h");

    // Used by native dialogs
    if (!wasm) {
        @cInclude("tinyfiledialogs.h");
    }
});

pub var ft2lib: if (useFreeType) c.FT_Library else void = undefined;

pub const Error = std.mem.Allocator.Error || StbImageError || TvgError || FontError;
pub const TvgError = error{tvgError};
pub const StbImageError = error{stbImageError};

pub const log = std.log.scoped(.dvui);
const dvui = @This();

/// A generic id created by hashing `std.builting.SourceLocation`'s (from `@src()`)
pub const Id = enum(u64) {
    zero = 0,
    // This may not work in future and is illegal behaviour / arch specific to compare to undefined.
    undef = 0xAAAAAAAAAAAAAAAA,
    _,

    /// Make a unique id from `src` and `id_extra`, possibly starting with start
    /// (usually a parent widget id).  This is how the initial parent widget id is
    /// created, and also toasts and dialogs from other threads.
    ///
    /// See `Widget.extendId` which calls this with the widget id as start.
    ///
    /// ```zig
    /// dvui.parentGet().extendId(@src(), id_extra)
    /// ```
    /// is how new widgets get their id, and can be used to make a unique id without
    /// making a widget.
    pub fn extendId(start: ?Id, src: std.builtin.SourceLocation, id_extra: usize) Id {
        var hash = fnv.init();
        if (start) |s| {
            hash.value = s.asU64();
        }
        hash.update(std.mem.asBytes(&src.module.ptr));
        hash.update(std.mem.asBytes(&src.file.ptr));
        hash.update(std.mem.asBytes(&src.line));
        hash.update(std.mem.asBytes(&src.column));
        hash.update(std.mem.asBytes(&id_extra));
        return @enumFromInt(hash.final());
    }

    /// Make a new id by combining id with some data, commonly a string key like `"_value"`.
    /// This is how dvui tracks things in `dataGet`/`dataSet`, `animation`, and `timer`.
    pub fn update(id: Id, input: []const u8) Id {
        var h = fnv.init();
        h.value = id.asU64();
        h.update(input);
        return @enumFromInt(h.final());
    }

    pub fn asU64(self: Id) u64 {
        return @intFromEnum(self);
    }

    /// ALWAYS prefer using `asU64` unless a `usize` is required as it could
    /// loose precision and uniqueness on non-64bit platforms (like wasm32).
    ///
    /// Using an `Id` as `Options.id_extra` would be a valid use of this function
    pub fn asUsize(self: Id) usize {
        // usize might be u32 (like on wasm32)
        return @truncate(@intFromEnum(self));
    }

    pub fn format(self: *const Id, writer: *std.Io.Writer) !void {
        try writer.print("{x}", .{self.asU64()});
    }
};

/// Current `Window` (i.e. the one that widgets will be added to).
/// Managed by `Window.begin` / `Window.end`
pub var current_window: ?*Window = null;

/// Get the current `dvui.Window` which corresponds to the OS window we are
/// currently adding widgets to.
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn currentWindow() *Window {
    return current_window orelse unreachable;
}

/// Allocates space for a widget to the alloc stack, or the arena
/// if the stack overflows.
///
/// The caller is responsible for ensuring that the widget calls
/// `dvui.widgetFree` in it's `deinit`. Usually this is done by
/// setting `dvui.WidgetData.was_allocated_on_widget_stack` to true
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn widgetAlloc(comptime T: type) *T {
    const cw = currentWindow();
    const alloc = cw._widget_stack.allocator();
    const ptr = alloc.create(T) catch @panic("OOM");
    return ptr;
}

/// Pops a widget off the alloc stack, if it was allocated there.
///
/// This should always be called in `deinit` to ensure the widget
/// is popped.
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn widgetFree(ptr: anytype) void {
    const ws = &currentWindow()._widget_stack;
    ws.allocator().destroy(ptr);
}

pub fn logError(src: std.builtin.SourceLocation, err: anyerror, comptime fmt: []const u8, args: anytype) void {
    @branchHint(.cold);
    const stack_trace_frame_count = @import("build_options").log_stack_trace orelse if (builtin.mode == .Debug) 12 else 0;
    const stack_trace_enabled = stack_trace_frame_count > 0;
    const err_trace_enabled = if (@import("build_options").log_error_trace) |enabled| enabled else stack_trace_enabled;

    var addresses: [stack_trace_frame_count]usize = @splat(0);
    var stack_trace = std.builtin.StackTrace{ .instruction_addresses = &addresses, .index = 0 };
    if (!builtin.strip_debug_info) std.debug.captureStackTrace(@returnAddress(), &stack_trace);

    const error_trace_fmt, const err_trace_arg = if (err_trace_enabled)
        .{ "\nError trace: {?f}", @errorReturnTrace() }
    else
        .{ "{s}", "" }; // Needed to keep the arg count the same
    const stack_trace_fmt, const trace_arg = if (stack_trace_enabled)
        .{ "\nStack trace: {f}", stack_trace }
    else
        .{ "{s}", "" }; // Needed to keep the arg count the sames

    // There is no nice way to combine a comptime tuple and a runtime tuple
    const combined_args = switch (std.meta.fields(@TypeOf(args)).len) {
        0 => .{ src.file, src.line, src.column, src.fn_name, @errorName(err), err_trace_arg, trace_arg },
        1 => .{ src.file, src.line, src.column, src.fn_name, @errorName(err), args[0], err_trace_arg, trace_arg },
        2 => .{ src.file, src.line, src.column, src.fn_name, @errorName(err), args[0], args[1], err_trace_arg, trace_arg },
        3 => .{ src.file, src.line, src.column, src.fn_name, @errorName(err), args[0], args[1], args[2], err_trace_arg, trace_arg },
        4 => .{ src.file, src.line, src.column, src.fn_name, @errorName(err), args[0], args[1], args[2], args[3], err_trace_arg, trace_arg },
        5 => .{ src.file, src.line, src.column, src.fn_name, @errorName(err), args[0], args[1], args[2], args[3], args[4], err_trace_arg, trace_arg },
        else => @compileError("Too many arguments"),
    };
    log.err("{s}:{d}:{d}: {s} got {s}: " ++ fmt ++ error_trace_fmt ++ stack_trace_fmt, combined_args);
}

/// Get the active theme.
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn themeGet() Theme {
    return currentWindow().theme;
}

/// Set the active theme.
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn themeSet(theme: Theme) void {
    currentWindow().theme = theme;
}

/// Toggle showing the debug window (run during `Window.end`).
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn toggleDebugWindow() void {
    var cw = currentWindow();
    cw.debug.open = !cw.debug.open;
}

pub const TagData = struct {
    id: Id,
    rect: Rect.Physical,
    visible: bool,
};

pub fn tag(name: []const u8, data: TagData) void {
    var cw = currentWindow();

    if (cw.tags.map.getPtr(name)) |old_data| {
        if (old_data.used) {
            dvui.log.err("duplicate tag name \"{s}\" id {x} (highlighted in red); you may need to pass .{{.id_extra=<loop index>}} as widget options (see https://github.com/david-vanderson/dvui/blob/master/readme-implementation.md#widget-ids )\n", .{ name, data.id });
            cw.debug.widget_id = data.id;
        }

        old_data.*.inner = data;
        old_data.used = true;
        return;
    }

    //std.debug.print("tag dupe {s}\n", .{name});
    const name_copy = cw.gpa.dupe(u8, name) catch |err| {
        dvui.log.err("tag() got {any} for name {s}\n", .{ err, name });
        return;
    };

    cw.tags.put(cw.gpa, name_copy, data) catch |err| {
        dvui.log.err("tag() \"{s}\" got {any} for id {x}\n", .{ name, err, data.id });
        cw.gpa.free(name_copy);
    };
}

pub fn tagGet(name: []const u8) ?TagData {
    return currentWindow().tags.get(name);
}

/// Nanosecond timestamp for this frame.
///
/// Updated during `Window.begin`.  Will not go backwards.
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn frameTimeNS() i128 {
    return currentWindow().frame_time_ns;
}

/// Add font to be referenced later by name.
///
/// ttf_bytes are the bytes of the ttf file
///
/// If ttf_bytes_allocator is not null, it will be used to free `ttf_bytes` AND `name` in
/// `Window.deinit`.
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn addFont(name: []const u8, ttf_bytes: []const u8, ttf_bytes_allocator: ?std.mem.Allocator) (std.mem.Allocator.Error || FontError)!void {
    var cw = currentWindow();
    try cw.fonts.database.ensureUnusedCapacity(cw.gpa, 1);
    // Test if we can successfully open this font
    // TODO: Find some more elegant way of validating ttf files
    const font = Font{ .id = .fromName(name), .size = 14 };
    var entry = try Font.Cache.Entry.init(ttf_bytes, font, name);
    // Try and cache the entry since the work is already done
    cw.fonts.cache.put(cw.gpa, font.hash(), entry) catch entry.deinit(cw.gpa, cw.backend);
    cw.fonts.database.putAssumeCapacity(font.id, .{
        .name = name,
        .bytes = ttf_bytes,
        .allocator = ttf_bytes_allocator,
    });
}

// Get or load the underlying font at an integer size <= font.size (guaranteed to have a minimum pixel size of 1)
pub fn fontCacheGet(font: Font) std.mem.Allocator.Error!*Font.Cache.Entry {
    const cw = currentWindow();
    return cw.fonts.getOrCreate(cw.gpa, font);
}

// Load the underlying font at an integer size <= font.size (guaranteed to have a minimum pixel size of 1)
pub fn fontCacheInit(ttf_bytes: []const u8, font: Font, name: []const u8) FontError!Font.Cache.Entry {
    return Font.Cache.Entry.init(ttf_bytes, font, name);
}

/// Takes in svg bytes and returns a tvg bytes that can be used
/// with `icon` or `iconTexture`
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn svgToTvg(allocator: std.mem.Allocator, svg_bytes: []const u8) (std.mem.Allocator.Error || TvgError)![]const u8 {
    return tvg.tvg_from_svg(allocator, svg_bytes, .{}) catch |err| switch (err) {
        error.OutOfMemory => |e| return e,
        else => {
            log.debug("svgToTvg returned {any}", .{err});
            return TvgError.tvgError;
        },
    };
}

/// Get the width of an icon at a specified height.
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn iconWidth(name: []const u8, tvg_bytes: []const u8, height: f32) TvgError!f32 {
    if (height == 0) return 0.0;
    const reader_state = io_compat.FixedSliceReader.init(tvg_bytes);
    var parser = tvg.tvg.parse(currentWindow().arena(), reader_state) catch |err| {
        log.warn("iconWidth Tinyvg error {any} parsing icon {s}\n", .{ err, name });
        return TvgError.tvgError;
    };
    defer parser.deinit();

    return height * @as(f32, @floatFromInt(parser.header.width)) / @as(f32, @floatFromInt(parser.header.height));
}
pub const IconRenderOptions = struct {
    /// if null uses original fill colors, use .transparent to disable fill
    fill_color: ?Color = .white,
    /// if null uses original stroke width
    stroke_width: ?f32 = null,
    /// if null uses original stroke colors
    stroke_color: ?Color = .white,

    // note: IconWidget tests against default values
};

/// Id of the currently focused subwindow.
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn focusedSubwindowId() Id {
    return currentWindow().subwindows.focused_id;
}

/// Focus a subwindow.
///
/// If you are doing this in response to an `Event`, you can pass that `Event`'s
/// "num" to change the focus of any further `Event`s in the list.
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn focusSubwindow(subwindow_id: ?Id, event_num: ?u16) void {
    currentWindow().focusSubwindow(subwindow_id, event_num);
}

/// Raise a subwindow to the top of the stack.
///
/// Any subwindows directly above it with "stay_above_parent_window" set will also be moved to stay above it.
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn raiseSubwindow(subwindow_id: Id) void {
    const cw = currentWindow();
    cw.subwindows.raise(subwindow_id) catch |err| {
        logError(@src(), err, "subwindow id {x}", .{subwindow_id});
    };
}

/// Focus a widget in the given subwindow (if null, the current subwindow).
///
/// To focus a widget in a different subwindow (like from a menu), you must
/// have both the widget id and the subwindow id that widget is in.  See
/// `subwindowCurrentId()`.
///
/// If you are doing this in response to an `Event`, you can pass that `Event`'s
/// num to change the focus of any further `Event`s in the list.
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn focusWidget(id: ?Id, subwindow_id: ?Id, event_num: ?u16) void {
    currentWindow().focusWidget(id, subwindow_id, event_num);
}

/// Id of the focused widget (if any) in the focused subwindow.
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn focusedWidgetId() ?Id {
    const cw = currentWindow();
    const sw = cw.subwindows.focused() orelse return null;
    return sw.focused_widget_id;
}

/// Id of the focused widget (if any) in the current subwindow.
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn focusedWidgetIdInCurrentSubwindow() ?Id {
    const cw = currentWindow();
    const sw = cw.subwindows.current() orelse blk: {
        log.warn("failed to find the focused subwindow, using base window\n", .{});
        break :blk &cw.subwindows.stack.items[0];
    };
    return sw.focused_widget_id;
}

/// Last widget id we saw this frame that was the focused widget.
///
/// Pass result to `lastFocusedIdInFrameSince` to know if any widget was focused
/// between the two calls.
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn lastFocusedIdInFrame() Id {
    return currentWindow().last_focused_id_this_frame;
}

/// Pass result from `lastFocusedIdInFrame`.  Returns the id of a widget that
/// was focused between the two calls, if any.
///
/// If so, this means one of:
/// * a widget had focus when it called `WidgetData.register`
/// * `focusWidget` with the id of the last widget to call `WidgetData.register`
/// * `focusWidget` with the id of a widget in the parent chain
///
/// If return is non null, can pass to `eventMatch` .focus_id to match key
/// events the focused widget got but didn't handle.
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn lastFocusedIdInFrameSince(prev: Id) ?Id {
    const last_focused_id = lastFocusedIdInFrame();
    if (prev != last_focused_id) {
        return last_focused_id;
    } else {
        return null;
    }
}

/// Last widget id we saw in the current subwindow that was focused.
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn lastFocusedIdInSubwindow() Id {
    return currentWindow().last_focused_id_in_subwindow;
}

/// Set cursor the app should use if not already set this frame.
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn cursorSet(cursor: enums.Cursor) void {
    const cw = currentWindow();
    if (cw.cursor_requested == null) {
        cw.cursor_requested = cursor;
    }
}

/// Called by floating widgets to participate in subwindow stacking - the order
/// in which multiple subwindows are drawn and which subwindow mouse events are
/// tagged with.
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn subwindowAdd(id: Id, rect: Rect, rect_pixels: Rect.Physical, modal: bool, stay_above_parent_window: ?Id, mouse_events: bool) void {
    const cw = currentWindow();
    cw.subwindows.add(cw.gpa, id, rect, rect_pixels, modal, stay_above_parent_window, mouse_events) catch |err| {
        logError(@src(), err, "Could not insert {f} {f} into subwindow list, events in this or other subwindows might not work properly", .{ id, rect_pixels });
    };
}

pub const subwindowCurrentSetReturn = struct {
    id: Id,
    rect: Rect.Natural,
};

/// Used by floating windows (subwindows) to install themselves as the current
/// subwindow (the subwindow that widgets run now will be in).
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn subwindowCurrentSet(id: Id, rect: ?Rect.Natural) subwindowCurrentSetReturn {
    const cw = currentWindow();
    const prev_id, const prev_rect = cw.subwindows.setCurrent(id, rect);
    return .{ .id = prev_id, .rect = prev_rect };
}

/// Id of current subwindow (the one widgets run now will be in).
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn subwindowCurrentId() Id {
    const cw = currentWindow();
    return cw.subwindows.current_id;
}

/// The difference between the final mouse position this frame and last frame.
/// Use `mouseTotalMotion().nonZero()` to detect if any mouse motion has occurred.
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn mouseTotalMotion() Point.Physical {
    const cw = currentWindow();
    return .diff(cw.mouse_pt, cw.mouse_pt_prev);
}

/// Used to track which widget holds mouse capture.
pub const CaptureMouse = struct {
    /// widget ID
    id: Id,
    /// physical pixels (aka capture zone)
    rect: Rect.Physical,
    /// subwindow id the widget with capture is in
    subwindow_id: Id,
};

/// Capture the mouse for this widget's data.
/// (i.e. `eventMatch` return true for this widget and false for all others)
/// and capture is explicitly released when passing `null`.
///
/// Tracks the widget's id / subwindow / rect, so that `.position` mouse events can still
/// be presented to widgets who's rect overlap with the widget holding the capture.
/// (which is what you would expect for e.g. background highlight)
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn captureMouse(wd: ?*const WidgetData, event_num: u16) void {
    const cm = if (wd) |data| CaptureMouse{
        .id = data.id,
        .rect = data.borderRectScale().r,
        .subwindow_id = subwindowCurrentId(),
    } else null;
    captureMouseCustom(cm, event_num);
}
/// In most cases, use `captureMouse` but if you want to customize the
/// "capture zone" you can use this function instead.
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn captureMouseCustom(cm: ?CaptureMouse, event_num: u16) void {
    const cw = currentWindow();
    defer cw.capture = cm;
    if (cm) |capture| {
        // log.debug("Mouse capture (event {d}): {any}", .{ event_num, cm });
        cw.captured_last_frame = true;
        cw.captureEvents(event_num, capture.id);
    } else {
        // Unmark all following mouse events
        cw.captureEvents(event_num, null);
        // log.debug("Mouse uncapture (event {d}): {?any}", .{ event_num, cw.capture });
        // for (dvui.events()) |*e| {
        //     if (e.evt == .mouse) {
        //         log.debug("{s}: win {?x}, widget {?x}", .{ @tagName(e.evt.mouse.action), e.target_windowId, e.target_widgetId });
        //     }
        // }
    }
}
/// If the widget ID passed has mouse capture, this maintains that capture for
/// the next frame.  This is usually called for you in `WidgetData.init`.
///
/// This can be called every frame regardless of capture.
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn captureMouseMaintain(cm: CaptureMouse) void {
    const cw = currentWindow();
    if (cw.capture != null and cw.capture.?.id == cm.id) {
        // to maintain capture, we must be on or above the
        // top modal window
        var i = cw.subwindows.stack.items.len;
        while (i > 0) : (i -= 1) {
            const sw = &cw.subwindows.stack.items[i - 1];
            if (sw.id == cw.subwindows.current_id) {
                // maintaining capture
                // either our floating window is above the top modal
                // or there are no floating modal windows
                cw.capture.?.rect = cm.rect;
                cw.captured_last_frame = true;
                return;
            } else if (sw.modal) {
                // found modal before we found current
                // cancel the capture, and cancel
                // any drag being done
                //
                // mark all events as not captured, we are being interrupted by
                // a modal dialog anyway
                captureMouse(null, 0);
                dragEnd();
                return;
            }
        }
    }
}

/// Test if the passed widget ID currently has mouse capture.
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn captured(id: Id) bool {
    if (captureMouseGet()) |cm| {
        return id == cm.id;
    }
    return false;
}

/// Get the widget ID that currently has mouse capture or null if none.
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn captureMouseGet() ?CaptureMouse {
    return currentWindow().capture;
}

/// Get current screen rectangle in pixels that drawing is being clipped to.
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn clipGet() Rect.Physical {
    return currentWindow().clipRect;
}

/// Intersect the given physical rect with the current clipping rect and set
/// as the new clipping rect.
///
/// Returns the previous clipping rect, use `clipSet` to restore it.
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn clip(new: Rect.Physical) Rect.Physical {
    const cw = currentWindow();
    const ret = cw.clipRect;
    clipSet(cw.clipRect.intersect(new));
    return ret;
}

/// Set the current clipping rect to the given physical rect.
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn clipSet(r: Rect.Physical) void {
    currentWindow().clipRect = r;
}

/// Multiplies the current alpha value with the passed in multiplier.
/// If `mult` is 0 then it will be completely transparent, 0.5 would be
/// half of the current alpha and so on.
///
/// Returns the previous alpha value, use `alphaSet` to restore it.
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn alpha(mult: f32) f32 {
    const cw = currentWindow();
    const ret = cw.alpha;
    alphaSet(cw.alpha * mult);
    return ret;
}

/// Set the current alpha value [0-1] where 1 is fully opaque.
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn alphaSet(a: f32) void {
    const cw = currentWindow();
    cw.alpha = std.math.clamp(a, 0, 1);
}

/// Set snap_to_pixels setting.  If true:
/// * fonts are rendered at @floor(font.size)
/// * drawing is generally rounded to the nearest pixel
///
/// Returns the previous setting.
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn snapToPixelsSet(snap: bool) bool {
    const cw = currentWindow();
    const old = cw.snap_to_pixels;
    cw.snap_to_pixels = snap;
    return old;
}

/// Get current snap_to_pixels setting.  See `snapToPixelsSet`.
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn snapToPixels() bool {
    const cw = currentWindow();
    return cw.snap_to_pixels;
}

/// Set kerning setting.  If true:
/// * textSize includes kerning by default
/// * renderText include kerning by default
///
/// Returns the previous setting.
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn kerningSet(kern: bool) bool {
    const cw = currentWindow();
    const old = cw.kerning;
    cw.kerning = kern;
    return old;
}

/// Requests another frame to be shown.
///
/// This only matters if you are using dvui to manage the framerate (by calling
/// `Window.waitTime` and using the return value to wait with event
/// interruption - for example `backend.waitEventTimeout` at the end of each
/// frame).
///
/// src and id are for debugging, which is enabled by calling
/// `Window.debugRefresh(true)`.  The debug window has a toggle button for this.
///
/// Can be called from any thread.
///
/// If called from non-GUI thread or outside `Window.begin`/`Window.end`, you must
/// pass a pointer to the Window you want to refresh.  In that case dvui will
/// go through the backend because the gui thread might be waiting.
pub fn refresh(win: ?*Window, src: std.builtin.SourceLocation, id: ?Id) void {
    if (win) |w| {
        // we are being called from non gui thread, the gui thread might be
        // sleeping, so need to trigger a wakeup via the backend
        w.refreshBackend(src, id);
    } else if (current_window) |cw| {
        cw.refreshWindow(src, id);
    } else {
        log.err("{s}:{d} refresh current_window was null, pass a *Window as first parameter if calling from other thread or outside window.begin()/end()", .{ src.file, src.line });
    }
}

/// Get the textual content of the system clipboard.  Caller must copy.
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn clipboardText() []const u8 {
    const cw = currentWindow();
    return cw.backend.clipboardText() catch |err| blk: {
        logError(@src(), err, "Could not get clipboard text", .{});
        break :blk "";
    };
}

/// Set the textual content of the system clipboard.
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn clipboardTextSet(text: []const u8) void {
    const cw = currentWindow();
    cw.backend.clipboardTextSet(text) catch |err| {
        logError(@src(), err, "Could not set clipboard text '{s}'", .{text});
    };
}

/// Ask the system to open the given url.
/// http:// and https:// urls can be opened.
/// returns true if the backend reports the URL was opened.
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn openURL(url: []const u8) bool {
    const parsed = std.Uri.parse(url) catch return false;
    if (!std.ascii.eqlIgnoreCase(parsed.scheme, "http") and
        !std.ascii.eqlIgnoreCase(parsed.scheme, "https"))
    {
        return false;
    }
    if (parsed.host != null and parsed.host.?.isEmpty()) {
        return false;
    }

    const cw = currentWindow();
    cw.backend.openURL(url) catch |err| {
        logError(@src(), err, "Could not open url '{s}'", .{url});
        return false;
    };
    return true;
}

test openURL {
    try std.testing.expect(openURL("notepad.exe") == false);
    try std.testing.expect(openURL("https://") == false);
    try std.testing.expect(openURL("file:///") == false);
}

/// Seconds elapsed between last frame and current.  This value can be quite
/// high after a period with no user interaction.
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn secondsSinceLastFrame() f32 {
    return currentWindow().secs_since_last_frame;
}

/// Average frames per second over the past 30 frames.
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn FPS() f32 {
    return currentWindow().FPS();
}

/// Get the Widget that would be the parent of a new widget.
///
/// ```zig
/// dvui.parentGet().extendId(@src(), id_extra)
/// ```
/// is how new widgets get their id, and can be used to make a unique id without
/// making a widget.
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn parentGet() Widget {
    return currentWindow().current_parent;
}

/// Make w the new parent widget.  See `parentGet`.
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn parentSet(w: Widget) void {
    const cw = currentWindow();
    cw.current_parent = w;
}

/// Make a previous parent widget the current parent.
///
/// Pass the current parent's id.  This is used to detect a coding error where
/// a widget's `.deinit()` was accidentally not called.
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn parentReset(id: Id, prev_parent: Widget) void {
    const cw = currentWindow();
    const currentId = cw.current_parent.data().id;
    if (id != currentId) {
        cw.debug.widget_id = currentId;

        log.err("widget is not closed within its parent. did you forget to call `.deinit()`?", .{});

        var iter = cw.current_parent.data().iterator();

        while (iter.next()) |wd| {
            log.err("  {s}:{d} {s} {x}", .{
                wd.src.file,
                wd.src.line,
                wd.options.name orelse "???",
                wd.id,
            });
        }
    }
    cw.current_parent = prev_parent;
}

/// Set if dvui should immediately render, and return the previous setting.
///
/// If false, the render functions defer until `Window.end`.
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn renderingSet(r: bool) bool {
    const cw = currentWindow();
    const ret = cw.render_target.rendering;
    cw.render_target.rendering = r;
    return ret;
}

/// Get the OS window size in natural pixels.  Physical pixels might be more on
/// a hidpi screen or if the user has content scaling.  See `windowRectPixels`.
///
/// Natural pixels is the unit for subwindow sizing and placement.
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn windowRect() Rect.Natural {
    // Window.data().rect is the definition of natural
    return .cast(currentWindow().data().rect);
}

/// Get the OS window size in pixels.  See `windowRect`.
///
/// Pixels is the unit for rendering and user input.
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn windowRectPixels() Rect.Physical {
    return currentWindow().rect_pixels;
}

/// Get the Rect and scale factor for the OS window.  The Rect is in pixels,
/// and the scale factor is how many pixels per natural pixel.  See
/// `windowRect`.
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn windowRectScale() RectScale {
    return currentWindow().rectScale();
}

/// The natural scale is how many pixels per natural pixel.  Useful for
/// converting between user input and subwindow size/position.  See
/// `windowRect`.
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn windowNaturalScale() f32 {
    return currentWindow().natural_scale;
}

/// True if this is the first frame we've seen this widget id, meaning we don't
/// know its min size yet.  The widget will record its min size in `.deinit()`.
///
/// If a widget is not seen for a frame, its min size will be forgotten and
/// firstFrame will return true the next frame we see it.
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn firstFrame(id: Id) bool {
    return minSizeGet(id) == null;
}

/// Get the min size recorded for id from last frame or null if id was not seen
/// last frame.
///
/// Usually you want `minSize` to combine min size from last frame with a min
/// size provided by the user code.
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn minSizeGet(id: Id) ?Size {
    return currentWindow().min_sizes.get(id);
}

/// Return the maximum of min_size and the min size for id from last frame.
///
/// See `minSizeGet` to get only the min size from last frame.
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn minSize(id: Id, min_size: Size) Size {
    var size = min_size;

    // Need to take the max of both given and previous.  ScrollArea could be
    // passed a min size Size{.w = 0, .h = 200} meaning to get the width from the
    // previous min size.
    if (minSizeGet(id)) |ms| {
        size = Size.max(size, ms);
    }

    return size;
}

/// DEPRECATED: See `dvui.Id.extendId`
pub const hashSrc = void;
/// DEPRECATED: See `dvui.Id.update`
pub const hashIdKey = void;

// Used for all the data functions
fn currentOverrideOrPanic(win: ?*Window) *Window {
    return win orelse current_window orelse @panic("dataSet current_window was null, pass a *Window as first parameter if calling from other thread or outside window.begin()/end()");
}

/// Set key/value pair for given id.
///
/// Can be called from any thread.
///
/// If called from non-GUI thread or outside `Window.begin`/`Window.end`, you must
/// pass a pointer to the `Window` you want to add the data to.
///
/// Stored data with the same id/key will be overwritten if it has the same size,
/// otherwise the data will be freed at the next call to `Window.end`. This means
/// that if a pointer to the same id/key was retrieved earlier, the value behind
/// that pointer would be modified.
///
/// If you want to store the contents of a slice, use `dataSetSlice`.
pub fn dataSet(win: ?*Window, id: Id, key: []const u8, data: anytype) void {
    const w = currentOverrideOrPanic(win);
    (w.data_store.set(w.gpa, id.update(key), data)) catch |err| {
        dvui.logError(@src(), err, "id {x} key {s}", .{ id, key });
    };
}

/// Set key/value pair for given id, copying the slice contents. Can be passed
/// a slice or pointer to an array.
///
/// Can be called from any thread.
///
/// Stored data with the same id/key will be overwritten if it has the same size,
/// otherwise the data will be freed at the next call to `Window.end`. This means
/// that if the slice with the same id/key was retrieved earlier, the value behind
/// that slice would be modified.
///
/// If called from non-GUI thread or outside `Window.begin`/`Window.end`, you must
/// pass a pointer to the `Window` you want to add the data to.
pub fn dataSetSlice(win: ?*Window, id: Id, key: []const u8, data: anytype) void {
    const w = currentOverrideOrPanic(win);
    (w.data_store.setSlice(w.gpa, id.update(key), data)) catch |err| {
        dvui.logError(@src(), err, "id {x} key {s}", .{ id, key });
    };
}

/// Same as `dataSetSlice`, but will copy data `num_copies` times all concatenated
/// into a single slice.  Useful to get dvui to allocate a specific number of
/// entries that you want to fill in after.
pub fn dataSetSliceCopies(win: ?*Window, id: Id, key: []const u8, data: anytype, num_copies: usize) void {
    const w = currentOverrideOrPanic(win);
    (w.data_store.setSliceCopies(w.gpa, id.update(key), data, num_copies)) catch |err| {
        dvui.logError(@src(), err, "id {x} key {s}", .{ id, key });
    };
}

/// Set key/value pair for given id.
///
/// Can be called from any thread.
///
/// If called from non-GUI thread or outside `Window.begin`/`Window.end`, you must
/// pass a pointer to the `Window` you want to add the data to.
///
/// Stored data with the same id/key will be freed at next `win.end()`.
///
/// If `copy_slice` is true, data must be a slice or pointer to array, and the
/// contents are copied into internal storage. If false, only the slice itself
/// (ptr and len) and stored.
pub fn dataSetAdvanced(win: ?*Window, id: Id, key: []const u8, data: anytype, comptime copy_slice: bool, num_copies: usize) void {
    if (copy_slice) {
        return dataSetSliceCopies(win, id, key, data, num_copies);
    } else {
        return dataSet(win, id, key, data);
    }
}

/// Retrieve the value for given key associated with id.
///
/// Can be called from any thread.
///
/// If called from non-GUI thread or outside `Window.begin`/`Window.end`, you must
/// pass a pointer to the `Window` you want to add the data to.
///
/// If you want a pointer to the stored data, use `dataGetPtr`.
///
/// If you want to get the contents of a stored slice, use `dataGetSlice`.
pub fn dataGet(win: ?*Window, id: Id, key: []const u8, comptime T: type) ?T {
    const w = currentOverrideOrPanic(win);
    return if (w.data_store.getPtr(id.update(key), T)) |v| v.* else null;
}

/// Retrieve the value for given key associated with id.  If no value was stored, store default and then return it.
///
/// Can be called from any thread.
///
/// If called from non-GUI thread or outside `Window.begin`/`Window.end`, you must
/// pass a pointer to the `Window` you want to add the data to.
///
/// If you want a pointer to the stored data, use `dataGetPtrDefault`.
///
/// If you want to get the contents of a stored slice, use `dataGetSlice`.
pub fn dataGetDefault(win: ?*Window, id: Id, key: []const u8, comptime T: type, default: T) T {
    const w = currentOverrideOrPanic(win);
    if (w.data_store.getPtr(id.update(key), T)) |v| return v.* else {
        w.data_store.set(w.gpa, id.update(key), default);
        return default;
    }
}

/// Retrieve a pointer to the value for given key associated with id.  If no
/// value was stored, store default and then return a pointer to the stored
/// value.
///
/// Can be called from any thread.
///
/// If called from non-GUI thread or outside `Window.begin`/`Window.end`, you must
/// pass a pointer to the `Window` you want to add the data to.
///
/// Returns a pointer to internal storage, which will be freed after a frame
/// where there is no call to any `dataGet`/`dataSet` functions for that id/key
/// combination.
///
/// The pointer will always be valid until the next call to `Window.end`.
///
/// If you want to get the contents of a stored slice, use `dataGetSlice`.
pub fn dataGetPtrDefault(win: ?*Window, id: Id, key: []const u8, comptime T: type, default: T) *T {
    const w = currentOverrideOrPanic(win);
    return w.data_store.getPtrDefault(w.gpa, id.update(key), T, default) catch |err| {
        dvui.logError(@src(), err, "id {x} key {s}", .{ id, key });
        @panic("dataGetPtrDefault failed");
    };
}

/// Retrieve a pointer to the value for given key associated with id.
///
/// Can be called from any thread.
///
/// If called from non-GUI thread or outside `Window.begin`/`Window.end`, you must
/// pass a pointer to the `Window` you want to add the data to.
///
/// Returns a pointer to internal storage, which will be freed after a frame
/// where there is no call to any `dataGet`/`dataSet` functions for that id/key
/// combination.
///
/// The pointer will always be valid until the next call to `Window.end`.
///
/// If you want to get the contents of a stored slice, use `dataGetSlice`.
pub fn dataGetPtr(win: ?*Window, id: Id, key: []const u8, comptime T: type) ?*T {
    const w = currentOverrideOrPanic(win);
    return w.data_store.getPtr(id.update(key), T);
}

/// Retrieve slice contents for given key associated with id.
///
/// `dataSetSlice` strips const from the slice type, so always call
/// `dataGetSlice` with a mutable slice type ([]u8, not []const u8).
///
/// Can be called from any thread.
///
/// If called from non-GUI thread or outside `Window.begin`/`Window.end`, you must
/// pass a pointer to the `Window` you want to add the data to.
///
/// The returned slice points to internal storage, which will be freed after
/// a frame where there is no call to any `dataGet`/`dataSet` functions for that
/// id/key combination.
///
/// The slice will always be valid until the next call to `Window.end`.
pub fn dataGetSlice(win: ?*Window, id: Id, key: []const u8, comptime T: type) ?T {
    const w = currentOverrideOrPanic(win);
    return w.data_store.getSlice(id.update(key), T);
}

/// Retrieve slice contents for given key associated with id.
///
/// If the id/key doesn't exist yet, store the default slice into internal
/// storage, and then return the internal storage slice.
///
/// Can be called from any thread.
///
/// If called from non-GUI thread or outside `Window.begin`/`Window.end`, you must
/// pass a pointer to the `Window` you want to add the data to.
///
/// The returned slice points to internal storage, which will be freed after
/// a frame where there is no call to any `dataGet`/`dataSet` functions for that
/// id/key combination.
///
/// The slice will always be valid until the next call to `Window.end`.
pub fn dataGetSliceDefault(win: ?*Window, id: Id, key: []const u8, comptime T: type, default: []const @typeInfo(T).pointer.child) T {
    const w = currentOverrideOrPanic(win);
    return w.data_store.getSliceDefault(w.gpa, id.update(key), T, default) catch |err| {
        dvui.logError(@src(), err, "id {x} key {s}", .{ id, key });
        @panic("dataGetSliceDefault failed");
    };
}

// returns the backing slice of bytes if we have it
pub fn dataGetInternal(win: ?*Window, id: Id, key: []const u8, comptime T: type, slice: bool) ?[]u8 {
    if (slice) {
        return dataGetPtr(win, id, key, T);
    } else {
        return dataGetSlice(win, id, key, T);
    }
}

/// Remove key (and data if any) for given id.  The data will be freed at next
/// `Window.end`.
///
/// Can be called from any thread.
///
/// If called from non-GUI thread or outside `Window.begin`/`Window.end`, you must
/// pass a pointer to the `Window` you want to add the dialog to.
pub fn dataRemove(win: ?*Window, id: Id, key: []const u8) void {
    const w = currentOverrideOrPanic(win);
    return w.data_store.remove(w.gpa, id.update(key)) catch |err| {
        dvui.logError(@src(), err, "id {x} key {s}", .{ id, key });
    };
}

/// Return a rect that fits inside avail given the options. avail wins over
/// `min_size`.
pub fn placeIn(avail: Rect, min_size: Size, e: Options.Expand, g: Options.Gravity) Rect {
    var size = min_size;

    // you never get larger than available
    size.w = @min(size.w, avail.w);
    size.h = @min(size.h, avail.h);

    switch (e) {
        .none => {},
        .horizontal => {
            size.w = avail.w;
        },
        .vertical => {
            size.h = avail.h;
        },
        .both => {
            size = avail.size();
        },
        .ratio => {
            if (min_size.w > 0 and min_size.h > 0 and avail.w > 0 and avail.h > 0) {
                const ratio = min_size.w / min_size.h;
                if (min_size.w > avail.w or min_size.h > avail.h) {
                    // contracting
                    const wratio = avail.w / min_size.w;
                    const hratio = avail.h / min_size.h;
                    if (wratio < hratio) {
                        // width is constraint
                        size.w = avail.w;
                        size.h = @min(avail.h, wratio * min_size.h);
                    } else {
                        // height is constraint
                        size.h = avail.h;
                        size.w = @min(avail.w, hratio * min_size.w);
                    }
                } else {
                    // expanding
                    const aratio = (avail.w - size.w) / (avail.h - size.h);
                    if (aratio > ratio) {
                        // height is constraint
                        size.w = @min(avail.w, avail.h * ratio);
                        size.h = avail.h;
                    } else {
                        // width is constraint
                        size.w = avail.w;
                        size.h = @min(avail.h, avail.w / ratio);
                    }
                }
            }
        },
    }

    var r = avail.shrinkToSize(size);
    r.x = avail.x + g.x * (avail.w - r.w);
    r.y = avail.y + g.y * (avail.h - r.h);

    return r;
}

/// Get the slice of `Event`s for this frame.
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn events() []Event {
    return currentWindow().events.items;
}

/// Wrapper around `eventMatch` for normal usage.
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn eventMatchSimple(e: *Event, wd: *WidgetData) bool {
    return eventMatch(e, .{ .id = wd.id, .r = wd.borderRectScale().r });
}

/// Data for matching events to widgets.  See `eventMatch`.
pub const EventMatchOptions = struct {
    /// Id of widget, used for keyboard focus and mouse capture.
    id: Id,

    /// Additional Id for keyboard focus, use to match children with
    /// `lastFocusedIdInFrame()`.
    focus_id: ?Id = null,

    /// Physical pixel rect used to match pointer events.
    r: Rect.Physical,

    /// During a drag, only match pointer events if this is the dragName.
    drag_name: ?[]const u8 = null,

    /// true means match all focus-based events routed to the subwindow with
    /// id.  This is how subwindows catch things like tab if no widget in that
    /// subwindow has focus.
    cleanup: bool = false,

    /// (Only in Debug) If true, `eventMatch` will log a reason when returning
    /// false.  Useful to understand why you aren't matching some event.
    debug: if (builtin.mode == .Debug) bool else void = if (builtin.mode == .Debug) false else undefined,
};

/// Should e be processed by a widget with the given id and screen rect?
///
/// This is the core event matching logic and includes keyboard focus and mouse
/// capture.  Call this on each event in `events` to know whether to process.
///
/// If asking whether an existing widget would process an event (if you are
/// wrapping a widget), that widget should have a `matchEvent` which calls this
/// internally but might extend the logic, or use that function to track state
/// (like whether a modifier key is being pressed).
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn eventMatch(e: *Event, opts: EventMatchOptions) bool {
    if (e.handled) {
        if (builtin.mode == .Debug and opts.debug) {
            log.debug("eventMatch {f} already handled", .{e});
        }
        return false;
    }

    switch (e.evt) {
        .key, .text => {
            if (e.target_windowId) |wid| {
                // focusable event
                if (opts.cleanup) {
                    // window is catching all focus-routed events that didn't get
                    // processed (maybe the focus widget never showed up)
                    if (wid != opts.id) {
                        // not the focused window
                        if (builtin.mode == .Debug and opts.debug) {
                            log.debug("eventMatch {f} (cleanup) focus not to this window", .{e});
                        }
                        return false;
                    }
                } else {
                    if (e.target_widgetId != opts.id and (opts.focus_id == null or opts.focus_id.? != e.target_widgetId)) {
                        // not the focused widget
                        if (builtin.mode == .Debug and opts.debug) {
                            log.debug("eventMatch {f} focus not to this widget", .{e});
                        }
                        return false;
                    }
                }
            }
        },
        .mouse => |me| {
            var other_capture = false;
            if (e.target_widgetId) |fwid| {
                // this event is during a mouse capture
                if (fwid == opts.id) {
                    // we have capture, we get all capturable mouse events (excludes wheel)
                    return true;
                } else {
                    // someone else has capture
                    other_capture = true;
                }
            }

            const cw = currentWindow();
            if (cw.dragging.state == .dragging and cw.dragging.name != null and (opts.drag_name == null or !std.mem.eql(u8, cw.dragging.name.?, opts.drag_name.?))) {
                // a cross-widget drag is happening that we don't know about
                if (builtin.mode == .Debug and opts.debug) {
                    log.debug("eventMatch {f} drag_name ({?s}) given but current drag is ({?s})", .{ e, opts.drag_name, cw.dragging.name });
                }
                return false;
            }

            if (me.floating_win != subwindowCurrentId()) {
                // floating window is above us
                if (builtin.mode == .Debug and opts.debug) {
                    log.debug("eventMatch {f} floating window above", .{e});
                }
                return false;
            }

            if (!opts.r.contains(me.p)) {
                // mouse not in our rect
                if (builtin.mode == .Debug and opts.debug) {
                    log.debug("eventMatch {f} not in rect", .{e});
                }
                return false;
            }

            if (!clipGet().contains(me.p)) {
                // mouse not in clip region

                // prevents widgets that are scrolled off a
                // scroll area from processing events
                if (builtin.mode == .Debug and opts.debug) {
                    log.debug("eventMatch {f} not in clip", .{e});
                }
                return false;
            }

            if (other_capture) {
                if (captureMouseGet()) |capture| {
                    // someone else has capture, but otherwise we would have gotten
                    // this mouse event
                    if (me.action == .position and capture.subwindow_id == subwindowCurrentId() and !capture.rect.intersect(opts.r).empty()) {
                        // we might be trying to highlight a background around the widget with capture:
                        // * we are in the same subwindow
                        // * our rect overlaps with the capture rect
                        return true;
                    }
                }

                if (builtin.mode == .Debug and opts.debug) {
                    log.debug("eventMatch {f} captured by other widget", .{e});
                }
                return false;
            }
        },
    }

    return true;
}

pub const ClickOptions = struct {
    /// Is set to true if the cursor is hovering the click rect
    hovered: ?*bool = null,

    /// If not null, this will be set when the cursor is within the click rect
    hover_cursor: ?enums.Cursor = .hand,

    /// The rect in which clicks are checked
    ///
    /// Defaults to the border rect of the `WidgetData`
    rect: ?Rect.Physical = null,

    /// Which mouse buttons to react to.
    buttons: enum { pointer, any } = .pointer,
};

pub fn clickedEx(wd: *const WidgetData, opts: ClickOptions) ?Event.EventTypes {
    var click_event: ?Event.EventTypes = null;

    const click_rect = opts.rect orelse wd.borderRectScale().r;
    for (dvui.events()) |*e| {
        if (!dvui.eventMatch(e, .{ .id = wd.id, .r = click_rect }))
            continue;

        switch (e.evt) {
            .mouse => |me| {
                if (me.action == .focus) {
                    e.handle(@src(), wd);

                    // focus this widget for events after this one (starting with e.num)
                    dvui.focusWidget(wd.id, null, e.num);
                } else if (me.action == .press and (if (opts.buttons == .pointer) me.button.pointer() else true)) {
                    e.handle(@src(), wd);
                    dvui.captureMouse(wd, e.num);

                    // for touch events, we want to cancel our click if a drag is started
                    dvui.dragPreStart(me.p, .{});
                } else if (me.action == .release and (if (opts.buttons == .pointer) me.button.pointer() else true)) {
                    // mouse button was released, do we still have mouse capture?
                    if (dvui.captured(wd.id)) {
                        e.handle(@src(), wd);

                        // cancel our capture
                        dvui.captureMouse(null, e.num);
                        dvui.dragEnd();

                        // if the release was within our border, the click is successful
                        if (click_rect.contains(me.p)) {

                            // if the user interacts successfully with a
                            // widget, it usually means part of the GUI is
                            // changing, so the convention is to call refresh
                            // so the user doesn't have to remember
                            dvui.refresh(null, @src(), wd.id);

                            click_event = .{ .mouse = me };
                        }
                    }
                } else if (me.action == .motion and me.button.touch()) {
                    if (dvui.captured(wd.id)) {
                        if (dvui.dragging(me.p, null)) |_| {
                            // touch: if we overcame the drag threshold, then
                            // that means the person probably didn't want to
                            // touch this button, they were trying to scroll
                            dvui.captureMouse(null, e.num);
                            dvui.dragEnd();
                        }
                    }
                } else if (me.action == .position) {
                    // Usually you don't want to mark .position events as
                    // handled, so that multiple widgets can all do hover
                    // highlighting.

                    // a single .position mouse event is at the end of each
                    // frame, so this means the mouse ended above us
                    if (opts.hover_cursor) |cursor| {
                        dvui.cursorSet(cursor);
                    }
                    if (opts.hovered) |hovered| {
                        hovered.* = true;
                    }
                }
            },
            .key => |ke| {
                if (ke.action == .down and ke.matchBind("activate")) {
                    e.handle(@src(), wd);
                    click_event = .{ .key = ke };
                    dvui.refresh(null, @src(), wd.id);
                }
            },
            else => {},
        }
    }
    return click_event;
}

/// Handles all events needed for clicking behaviour, used by `ButtonWidget`.
pub fn clicked(wd: *const WidgetData, opts: ClickOptions) bool {
    if (clickedEx(wd, opts)) |_| {
        return true;
    }

    return false;
}

/// Animation state - see `animation` and `animationGet`.
///
/// start_time and `end_time` are relative to the current frame time.  At the
/// start of each frame both are reduced by the micros since the last frame.
///
/// An animation will be active thru a frame where its `end_time` is <= 0, and be
/// deleted at the beginning of the next frame.  See `spinner` for an example of
/// how to have a seamless continuous animation.
pub const Animation = struct {
    easing: *const easing.EasingFn = easing.linear,
    start_val: f32 = 0,
    end_val: f32 = 1,
    start_time: i32 = 0,
    end_time: i32,

    /// Get the interpolated value between `start_val` and `end_val`
    ///
    /// For some easing functions, this value can extend above or bellow
    /// `start_val` and `end_val`. If this is an issue, you can choose
    /// a different easing function or use `std.math.clamp`
    pub fn value(a: *const Animation) f32 {
        if (a.start_time >= 0) return a.start_val;
        if (a.done()) return a.end_val;
        const frac = @as(f32, @floatFromInt(-a.start_time)) / @as(f32, @floatFromInt(a.end_time - a.start_time));
        const t = a.easing(std.math.clamp(frac, 0, 1));
        return std.math.lerp(a.start_val, a.end_val, t);
    }

    // return true on the last frame for this animation
    pub fn done(a: *const Animation) bool {
        if (a.end_time <= 0) {
            return true;
        }

        return false;
    }
};

/// Add animation a to key associated with id.  See `Animation`.
///
/// Only valid between `Window.begin` and `Window.end`.
pub fn animation(id: Id, key: []const u8, a: Animation) void {
    var cw = currentWindow();
    const h = id.update(key);
    cw.animations.put(cw.gpa, h, a) catch |err| switch (err) {
        error.OutOfMemory => {
            log.err("animation got {any} for id {x} key {s}\n", .{ err, id, key });
        },
    };
}

/// Retrieve an animation previously added with `animation`.  See `Animation`.
///
/// Only valid between `Window.begin` and `Window.end`.
pub fn animationGet(id: Id, key: []const u8) ?Animation {
    const h = id.update(key);
    return currentWindow().animations.get(h);
}

/// Add a timer for id that will be `timerDone` on the first frame after micros
/// has passed.
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn timer(id: Id, micros: i32) void {
    currentWindow().timer(id, micros);
}

/// Return the number of micros left on the timer for id if there is one.  If
/// `timerDone`, this value will be <= 0 and represents how many micros this
/// frame is past the timer expiration.
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn timerGet(id: Id) ?i32 {
    if (animationGet(id, "_timer")) |a| {
        return a.end_time;
    } else {
        return null;
    }
}

/// Return true on the first frame after a timer has expired.
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn timerDone(id: Id) bool {
    if (timerGet(id)) |end_time| {
        if (end_time <= 0) {
            return true;
        }
    }

    return false;
}

/// Return true if `timerDone` or if there is no timer.  Useful for periodic
/// events.
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn timerDoneOrNone(id: Id) bool {
    return timerDone(id) or (timerGet(id) == null);
}

pub const ScrollToOptions = struct {
    // rect in screen coords we want to be visible (might be outside
    // scrollarea's clipping region - we want to scroll to bring it inside)
    screen_rect: dvui.Rect.Physical,

    // whether to scroll outside the current scroll bounds (useful if the
    // current action might be expanding the scroll area)
    over_scroll: bool = false,
};

/// Scroll the current containing scroll area to show the passed in screen rect
pub fn scrollTo(scroll_to: ScrollToOptions) void {
    _ = scroll_to;
}

pub const ScrollDragOptions = struct {
    // mouse point from motion event
    mouse_pt: dvui.Point.Physical,

    // rect in screen coords of the widget doing the drag (scrolling will stop
    // if it wouldn't show more of this rect)
    screen_rect: dvui.Rect.Physical,
};

/// Bubbled from inside a scrollarea to ensure scrolling while dragging
/// if the mouse moves to the edge or outside the scrollarea.
///
/// During dragging, a widget should call this on each pointer motion event.
pub fn scrollDrag(scroll_drag: ScrollDragOptions) void {
    _ = scroll_drag;
}

pub const TabIndex = struct {
    windowId: Id,
    widgetId: Id,
    tabIndex: u16,
};

/// Set the tab order for this widget.  `tab_index` values are visited starting
/// with 1 and going up.
///
/// A zero `tab_index` means this function does nothing and the widget is not
/// added to the tab order.
///
/// A null `tab_index` means it will be visited after all normal values.  All
/// null widgets are visited in order of calling `tabIndexSet`.
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn tabIndexSet(widget_id: Id, tab_index: ?u16) void {
    if (tab_index != null and tab_index.? == 0)
        return;

    var cw = currentWindow();
    const ti = TabIndex{ .windowId = cw.subwindows.current_id, .widgetId = widget_id, .tabIndex = (tab_index orelse math.maxInt(u16)) };
    cw.tab_index.append(cw.gpa, ti) catch |err| {
        logError(@src(), err, "Could not set tab index. This might break keyboard navigation as the widget may become unreachable via tab", .{});
    };
}

/// Move focus to the next widget in tab index order.  Uses the tab index values from last frame.
///
/// If you are calling this due to processing an event, you can pass `Event`'s num
/// and any further events will have their focus adjusted.
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn tabIndexNext(event_num: ?u16) void {
    tabIndexNextEx(event_num, currentWindow().tab_index_prev.items);
}

pub fn tabIndexNextEx(event_num: ?u16, _: []dvui.TabIndex) void {
    const cw = currentWindow();
    const widgetId = focusedWidgetId();
    var oldtab: ?u16 = null;
    if (widgetId != null) {
        for (cw.tab_index_prev.items) |ti| {
            if (ti.windowId == cw.subwindows.focused_id and ti.widgetId == widgetId.?) {
                oldtab = ti.tabIndex;
                break;
            }
        }
    }

    // find the first widget with a tabindex greater than oldtab
    // or the first widget with lowest tabindex if oldtab is null
    var newtab: u16 = math.maxInt(u16);
    var newId: ?Id = null;
    var foundFocus = false;

    for (cw.tab_index_prev.items) |ti| {
        if (ti.windowId == cw.subwindows.focused_id) {
            if (ti.widgetId == widgetId) {
                foundFocus = true;
            } else if (foundFocus == true and oldtab != null and ti.tabIndex == oldtab.?) {
                // found the first widget after current that has the same tabindex
                newtab = ti.tabIndex;
                newId = ti.widgetId;
                break;
            } else if (oldtab == null or ti.tabIndex > oldtab.?) {
                if (newId == null or ti.tabIndex < newtab) {
                    newtab = ti.tabIndex;
                    newId = ti.widgetId;
                }
            }
        }
    }

    focusWidget(newId, null, event_num);
}

/// Move focus to the previous widget in tab index order.  Uses the tab index values from last frame.
///
/// If you are calling this due to processing an event, you can pass `Event`'s num
/// and any further events will have their focus adjusted.
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn tabIndexPrev(event_num: ?u16) void {
    tabIndexPrevEx(event_num, currentWindow().tab_index_prev.items);
}

pub fn tabIndexPrevEx(event_num: ?u16, _: []dvui.TabIndex) void {
    const cw = currentWindow();
    const widgetId = focusedWidgetId();
    var oldtab: ?u16 = null;
    if (widgetId != null) {
        for (cw.tab_index_prev.items) |ti| {
            if (ti.windowId == cw.subwindows.focused_id and ti.widgetId == widgetId.?) {
                oldtab = ti.tabIndex;
                break;
            }
        }
    }

    // find the last widget with a tabindex less than oldtab
    // or the last widget with highest tabindex if oldtab is null
    var newtab: u16 = 1;
    var newId: ?Id = null;
    var foundFocus = false;

    for (cw.tab_index_prev.items) |ti| {
        if (ti.windowId == cw.subwindows.focused_id) {
            if (ti.widgetId == widgetId) {
                foundFocus = true;

                if (oldtab != null and newtab == oldtab.?) {
                    // use last widget before that has the same tabindex
                    // might be none before so we'll go to null
                    break;
                }
            } else if (oldtab == null or ti.tabIndex < oldtab.? or (!foundFocus and ti.tabIndex == oldtab.?)) {
                if (ti.tabIndex >= newtab) {
                    newtab = ti.tabIndex;
                    newId = ti.widgetId;
                }
            }
        }
    }

    focusWidget(newId, null, event_num);
}

/// Widgets that accept text input should call this on frames they have focus.
///
/// It communicates:
/// * text input should happen (maybe shows an on screen keyboard)
/// * rect on screen (position possible IME window)
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn wantTextInput(r: Rect.Natural) void {
    const cw = currentWindow();
    cw.text_input_rect = r;
}

pub const IdMutex = struct {
    id: Id,
    mutex: *std.Thread.Mutex,
};

/// Add a dialog to be displayed on the GUI thread during `Window.end`.
///
/// Returns an id and locked mutex that **must** be unlocked by the caller. Caller
/// does any `Window.dataSet` calls before unlocking the mutex to ensure that
/// data is available before the dialog is displayed.
///
/// Can be called from any thread.
///
/// If called from non-GUI thread or outside `Window.begin`/`Window.end`, you
/// **must** pass a pointer to the Window you want to add the dialog to.
pub fn dialogAdd(win: ?*Window, src: std.builtin.SourceLocation, id_extra: usize, display: Dialog.DisplayFn) IdMutex {
    const w: *Window, const id: Id = if (win) |w|
        // we are being called from non gui thread
        .{ w, Id.extendId(null, src, id_extra) }
    else if (current_window) |cw|
        .{ cw, parentGet().extendId(src, id_extra) }
    else {
        std.debug.panic("{s}:{d} dialogAdd current_window was null, pass a *Window as first parameter if calling from other thread or outside window.begin()/end()\n", .{ src.file, src.line });
    };
    const mutex = w.dialogs.add(w.gpa, .{ .id = id, .display = display }) catch |err| {
        logError(@src(), err, "failed to add dialog", .{});
        w.dialogs.mutex.lock();
        return .{ .id = .zero, .mutex = &w.dialogs.mutex };
    };
    refresh(win, @src(), id);
    return .{ .id = id, .mutex = mutex };
}

/// Only called from gui thread.
pub fn dialogRemove(id: Id) void {
    const cw = currentWindow();
    cw.dialogs.remove(id);
    cw.refreshWindow(@src(), id);
}

pub const DialogCallAfterFn = *const fn (dvui.Id, dvui.enums.DialogResponse) anyerror!void;
pub const DialogOptions = struct {
    id_extra: usize = 0,
    window: ?*Window = null,
    modal: bool = true,
    title: []const u8 = "",
    message: []const u8,
    ok_label: []const u8 = "Ok",
    cancel_label: ?[]const u8 = null,
    default: ?enums.DialogResponse = .ok,
    max_size: ?Options.MaxSize = null,
    displayFn: Dialog.DisplayFn = dialogDisplay,
    callafterFn: ?DialogCallAfterFn = null,
};

/// Add a dialog to be displayed on the GUI thread during `Window.end`.
///
/// user_struct can be anytype, each field will be stored using
/// `dataSet`/`dataSetSlice` for use in `opts.displayFn`
///
/// Can be called from any thread, but if calling from a non-GUI thread or
/// outside `Window.begin`/`Window.end` you must set opts.window.
pub fn dialog(src: std.builtin.SourceLocation, user_struct: anytype, opts: DialogOptions) void {
    const id_mutex = dialogAdd(opts.window, src, opts.id_extra, opts.displayFn);
    const id = id_mutex.id;
    dataSet(opts.window, id, "_modal", opts.modal);
    dataSetSlice(opts.window, id, "_title", opts.title);
    dataSetSlice(opts.window, id, "_message", opts.message);
    dataSetSlice(opts.window, id, "_ok_label", opts.ok_label);
    dataSet(opts.window, id, "_center_on", (opts.window orelse currentWindow()).subwindows.current_rect);
    if (opts.cancel_label) |cl| {
        dataSetSlice(opts.window, id, "_cancel_label", cl);
    }
    if (opts.default) |d| {
        dataSet(opts.window, id, "_default", d);
    }
    if (opts.max_size) |ms| {
        dataSet(opts.window, id, "_max_size", ms);
    }
    if (opts.callafterFn) |ca| {
        dataSet(opts.window, id, "_callafter", ca);
    }

    // add all fields of user_struct
    inline for (@typeInfo(@TypeOf(user_struct)).@"struct".fields) |f| {
        const ft = @typeInfo(f.type);
        if (ft == .pointer and (ft.pointer.size == .slice or (ft.pointer.size == .one and @typeInfo(ft.pointer.child) == .array))) {
            dataSetSlice(opts.window, id, f.name, @field(user_struct, f.name));
        } else {
            dataSet(opts.window, id, f.name, @field(user_struct, f.name));
        }
    }

    id_mutex.mutex.unlock();
}

pub fn dialogDisplay(id: Id) !void {
    const modal = dvui.dataGet(null, id, "_modal", bool) orelse {
        log.err("dialogDisplay lost data for dialog {x}\n", .{id});
        dvui.dialogRemove(id);
        return;
    };

    _ = dvui.dataGetSlice(null, id, "_title", []u8) orelse {
        log.err("dialogDisplay lost data for dialog {x}\n", .{id});
        dvui.dialogRemove(id);
        return;
    };

    const message = dvui.dataGetSlice(null, id, "_message", []u8) orelse {
        log.err("dialogDisplay lost data for dialog {x}\n", .{id});
        dvui.dialogRemove(id);
        return;
    };

    const ok_label = dvui.dataGetSlice(null, id, "_ok_label", []u8) orelse {
        log.err("dialogDisplay lost data for dialog {x}\n", .{id});
        dvui.dialogRemove(id);
        return;
    };

    const center_on = dvui.dataGet(null, id, "_center_on", Rect.Natural) orelse currentWindow().subwindows.current_rect;

    const cancel_label = dvui.dataGetSlice(null, id, "_cancel_label", []u8);
    const default = dvui.dataGet(null, id, "_default", enums.DialogResponse);

    const callafter = dvui.dataGet(null, id, "_callafter", DialogCallAfterFn);

    const maxSize = dvui.dataGet(null, id, "_max_size", Options.MaxSize);

    _ = modal;
    _ = center_on;
    _ = maxSize;

    {
        // Add the buttons at the bottom first, so that they are guaranteed to be shown
        var hbox = dvui.box(@src(), .{ .dir = .horizontal }, .{ .gravity_x = 0.5, .gravity_y = 1.0 });
        defer hbox.deinit();

        if (cancel_label) |cl| {
            var cancel_data: WidgetData = undefined;
            const gravx: f32, const tindex: u16 = switch (currentWindow().button_order) {
                .cancel_ok => .{ 0.0, 1 },
                .ok_cancel => .{ 1.0, 3 },
            };
            if (dvui.button(@src(), cl, .{}, .{ .tab_index = tindex, .data_out = &cancel_data, .gravity_x = gravx })) {
                dvui.dialogRemove(id);
                if (callafter) |ca| {
                    ca(id, .cancel) catch |err| {
                        log.debug("Dialog callafter for {x} returned {any}", .{ id, err });
                    };
                }
                return;
            }
            if (default != null and dvui.firstFrame(hbox.data().id) and default.? == .cancel) {
                dvui.focusWidget(cancel_data.id, null, null);
            }
        }

        var ok_data: WidgetData = undefined;
        if (dvui.button(@src(), ok_label, .{}, .{ .tab_index = 2, .data_out = &ok_data })) {
            dvui.dialogRemove(id);
            if (callafter) |ca| {
                ca(id, .ok) catch |err| {
                    log.debug("Dialog callafter for {x} returned {any}", .{ id, err });
                };
            }
            return;
        }
        if (default != null and dvui.firstFrame(hbox.data().id) and default.? == .ok) {
            dvui.focusWidget(ok_data.id, null, null);
        }
    }

    // Simplified message rendering without scroll/text layout helpers
    _ = dvui.label(@src(), message, .{}, .{ .expand = .both, .background = false, .style = .window });
}

/// Add a toast.  Use `toast` for a simple message.
///
/// If subwindow_id is null, the toast will be shown during `Window.end`.  If
/// subwindow_id is not null, separate code must call `toastsShow` or
/// `toastsFor` with that subwindow_id to retrieve this toast and display it.
///
/// Returns an id and locked mutex that must be unlocked by the caller. Caller
/// does any `dataSet` calls before unlocking the mutex to ensure that data is
/// available before the toast is displayed.
///
/// Can be called from any thread.
///
/// If called from non-GUI thread or outside `Window.begin`/`Window.end`, you must
/// pass a pointer to the Window you want to add the toast to.
pub fn toastAdd(win: ?*Window, src: std.builtin.SourceLocation, id_extra: usize, subwindow_id: ?Id, display: Dialog.DisplayFn, timeout: ?i32) IdMutex {
    const w: *Window, const id: Id = if (win) |w|
        // we are being called from non gui thread
        .{ w, Id.extendId(null, src, id_extra) }
    else if (current_window) |cw|
        .{ cw, parentGet().extendId(src, id_extra) }
    else {
        std.debug.panic("{s}:{d} toastAdd current_window was null, pass a *Window as first parameter if calling from other thread or outside window.begin()/end()", .{ src.file, src.line });
    };
    const mutex = w.toasts.add(w.gpa, .{ .id = id, .subwindow_id = subwindow_id, .display = display }) catch |err| {
        logError(@src(), err, "failed to add toast", .{});
        w.toasts.mutex.lock();
        return .{ .id = .zero, .mutex = &w.toasts.mutex };
    };
    refresh(win, @src(), id);
    if (timeout) |tt| {
        w.timer(id, tt);
    } else {
        w.timerRemove(id);
    }
    return .{ .id = id, .mutex = mutex };
}

/// Remove a previously added toast.
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn toastRemove(id: Id) void {
    const cw = currentWindow();
    cw.toasts.remove(id);
    refresh(null, @src(), id);
}

/// Returns toasts that were previously added with non-null subwindow_id.
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn toastsFor(subwindow_id: ?Id) ?ToastIterator {
    const cw = dvui.currentWindow();
    var it = cw.toasts.iterator(subwindow_id);
    it.i = cw.toasts.indexOfSubwindow(subwindow_id) orelse return null;
    return it;
}

pub const ToastOptions = struct {
    id_extra: usize = 0,
    window: ?*Window = null,
    subwindow_id: ?Id = null,
    timeout: ?i32 = 5_000_000,
    message: []const u8,
    displayFn: Dialog.DisplayFn = toastDisplay,
};

/// Add a simple toast.  Use `toastAdd` for more complex toasts.
///
/// If `opts.subwindow_id` is null, the toast will be shown during
/// `Window.end`.  If `opts.subwindow_id` is not null, separate code must call
/// `toastsShow` or `toastsFor` with that subwindow_id to retrieve this toast
/// and display it.
///
/// Can be called from any thread, but if called from a non-GUI thread or
/// outside `Window.begin`/`Window.end`, you must set `opts.window`.
pub fn toast(src: std.builtin.SourceLocation, opts: ToastOptions) void {
    const id_mutex = dvui.toastAdd(opts.window, src, opts.id_extra, opts.subwindow_id, opts.displayFn, opts.timeout);
    const id = id_mutex.id;
    dvui.dataSetSlice(opts.window, id, "_message", opts.message);
    id_mutex.mutex.unlock();
}

pub fn toastDisplay(id: Id) !void {
    const message = dvui.dataGetSlice(null, id, "_message", []u8) orelse {
        log.err("toastDisplay lost data for toast {x}\n", .{id});
        dvui.toastRemove(id);
        return;
    };

    var animator = dvui.animate(@src(), .{ .kind = .alpha, .duration = 500_000 }, .{ .id_extra = id.asUsize() });
    defer animator.deinit();
    var label_wd: WidgetData = undefined;
    dvui.labelNoFmt(@src(), message, .{}, .{ .background = true, .corner_radius = dvui.Rect.all(1000), .padding = .{ .x = 16, .y = 8, .w = 16, .h = 8 }, .data_out = &label_wd });
    if (label_wd.accesskit_node()) |ak_node| {
        AccessKit.nodeSetLive(ak_node, AccessKit.Live.polite);
    }
    if (dvui.timerDone(id)) {
        animator.startEnd();
    }

    if (animator.end()) {
        dvui.toastRemove(id);
    }
}

/// Standard way of showing toasts.  For the main window, this is called with
/// null in Window.end().
///
/// For floating windows or other widgets, pass non-null id. Then it shows
/// toasts that were previously added with non-null subwindow_id, and they are
/// shown on top of the current subwindow.
///
/// Toasts are shown in rect centered horizontally and 70% down vertically.
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn toastsShow(id: ?Id, rect: Rect.Natural) void {
    currentWindow().toastsShow(id, rect);
}

/// Wrapper widget that takes a single child and animates it.
///
/// `AnimateWidget.start` is called for you on the first frame.
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn animate(src: std.builtin.SourceLocation, init_opts: AnimateWidget.InitOptions, opts: Options) *AnimateWidget {
    var ret = widgetAlloc(AnimateWidget);
    ret.* = AnimateWidget.init(src, init_opts, opts);
    ret.data().was_allocated_on_widget_stack = true;
    ret.install();
    return ret;
}

/// Show chosen entry, and click to display all entries in a floating menu.
///
/// Returns true if any entry was selected (even the already chosen one).
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn dropdown(src: std.builtin.SourceLocation, entries: []const []const u8, choice: *usize, opts: Options) bool {
    _ = src;
    _ = entries;
    _ = choice;
    _ = opts;
    return false;
}

/// Show @tagName of choice, and click to display all tags in that enum in a floating menu.
///
/// Returns true if any enum value was selected (even the already chosen one).
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn dropdownEnum(src: std.builtin.SourceLocation, T: type, choice: *T, opts: Options) bool {
    _ = src;
    _ = choice;
    _ = opts;
    return false;
}

pub var expander_defaults: Options = .{
    .name = "Expander",
    .role = .group,
    .padding = Rect.all(4),
    .font_style = .heading,
};

pub const ExpanderOptions = struct {
    default_expanded: bool = false,
};

/// Arrow icon and label that remembers if it has been clicked (expanded).
///
/// Use to divide lots of content into expandable sections.
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn expander(src: std.builtin.SourceLocation, label_str: []const u8, init_opts: ExpanderOptions, opts: Options) bool {
    const options = expander_defaults.override(opts);

    var b = box(src, .{ .dir = .horizontal }, options);
    defer b.deinit();

    dvui.tabIndexSet(b.data().id, b.data().options.tab_index);

    var expanded: bool = init_opts.default_expanded;
    if (dvui.dataGet(null, b.data().id, "_expand", bool)) |e| {
        expanded = e;
    }

    var hovered: bool = false;
    if (dvui.clicked(b.data(), .{ .hovered = &hovered })) {
        expanded = !expanded;
    }

    if (b.data().accesskit_node()) |ak_node| {
        AccessKit.nodeAddAction(ak_node, AccessKit.Action.focus);
        AccessKit.nodeAddAction(ak_node, AccessKit.Action.click);
    }

    b.drawBackground();
    if (b.data().visible() and b.data().id == dvui.focusedWidgetId()) {
        b.data().focusBorder();
    }

    labelNoFmt(@src(), label_str, .{}, options.strip().override(.{ .label = .{ .for_id = b.data().id } }));

    dvui.dataSet(null, b.data().id, "_expand", expanded);
    // Accessibility TODO: Support expand and collapse actions, but can;t find a way to get it to work.

    return expanded;
}

/// Context menu.  Pass a screen space pixel rect in `init_opts`, then
/// `.activePoint()` says whether to show a menu.
///
/// The menu code should happen before `.deinit()`, but don't put regular widgets
/// directly inside Context.
///
/// Only valid between `Window.begin`and `Window.end`.
/// Lays out children according to gravity anywhere inside.  Useful to overlap
/// children.
///
/// See `box`.
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn selectionBox(src: std.builtin.SourceLocation, init_opts: SelectionWidget.InitOptions, opts: Options) *SelectionWidget {
    var ret = widgetAlloc(SelectionWidget);
    ret.* = SelectionWidget.init(src, init_opts, opts);
    ret.data().was_allocated_on_widget_stack = true;
    ret.install();
    ret.processEvents();
    return ret;
}

/// Render a draggable 2D gizmo with horizontal (blue) and vertical (green) vectors.
/// Only valid between `Window.begin` and `Window.end`.
pub fn gizmo2d(src: std.builtin.SourceLocation, init_opts: GizmoWidget.InitOptions, opts: Options) void {
    _ = src;
    _ = init_opts;
    _ = opts;
}

/// Box that packs children with gravity 0 or 1, or anywhere with gravity
/// between (0,1).
///
/// A child with gravity between (0,1) in dir direction is not packed, and
/// instead positioned in the whole box area, like `overlay`.
///
/// A child with gravity 0 or 1 in dir direction is packed either at the start
/// (gravity 0) or end (gravity 1).
///
/// Extra space is allocated evenly to all packed children expanded in dir
/// direction.
///
/// If init_opts.equal_space is true, all packed children get equal space.
///
/// See `flexbox`.
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn box(src: std.builtin.SourceLocation, init_opts: BoxWidget.InitOptions, opts: Options) *BoxWidget {
    var ret = widgetAlloc(BoxWidget);
    ret.* = BoxWidget.init(src, init_opts, opts);
    ret.data().was_allocated_on_widget_stack = true;
    ret.install();
    ret.drawBackground();
    return ret;
}

/// Box laying out children horizontally, making new rows as needed.
///
/// See `box`.
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn flexbox(src: std.builtin.SourceLocation, init_opts: FlexBoxWidget.InitOptions, opts: Options) *FlexBoxWidget {
    var ret = widgetAlloc(FlexBoxWidget);
    ret.* = FlexBoxWidget.init(src, init_opts, opts);
    ret.data().was_allocated_on_widget_stack = true;
    ret.install();
    ret.drawBackground();
    return ret;
}

/// Widget for making thin lines to visually separate other widgets.  Use
/// .min_size_content to control size.
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn separator(src: std.builtin.SourceLocation, opts: Options) WidgetData {
    const defaults: Options = .{
        .name = "Separator",
        .background = true, // TODO: remove this when border and background are no longer coupled
        .color_fill = dvui.themeGet().border,
        .min_size_content = .{ .w = 1, .h = 1 },
    };

    var wd = WidgetData.init(src, .{}, defaults.override(opts));
    wd.register();
    wd.borderAndBackground(.{});
    wd.minSizeSetAndRefresh();
    wd.minSizeReportToParent();
    return wd;
}

/// Empty widget used to take up space with .min_size_content.
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn spacer(src: std.builtin.SourceLocation, opts: Options) WidgetData {
    const defaults: Options = .{ .name = "Spacer" };
    var wd = WidgetData.init(src, .{}, defaults.override(opts));
    wd.register();
    wd.borderAndBackground(.{});
    wd.minSizeSetAndRefresh();
    wd.minSizeReportToParent();
    return wd;
}

pub fn spinner(src: std.builtin.SourceLocation, opts: Options) void {
    var defaults: Options = .{
        .name = "Spinner",
        .min_size_content = .{ .w = 50, .h = 50 },
    };
    const options = defaults.override(opts);
    var wd = WidgetData.init(src, .{}, options);
    wd.register();
    wd.minSizeSetAndRefresh();
    wd.minSizeReportToParent();

    if (wd.rect.empty()) {
        return;
    }

    const rs = wd.contentRectScale();
    const r = rs.r;

    var t: f32 = 0;
    const anim = Animation{ .end_time = 3_000_000 };
    if (animationGet(wd.id, "_t")) |a| {
        // existing animation
        var aa = a;
        if (aa.done()) {
            // this animation is expired, seamlessly transition to next animation
            aa = anim;
            aa.start_time = a.end_time;
            aa.end_time += a.end_time;
            animation(wd.id, "_t", aa);
        }
        t = aa.value();
    } else {
        // first frame we are seeing the spinner
        animation(wd.id, "_t", anim);
    }

    var path: Path.Builder = .init(dvui.currentWindow().lifo());
    defer path.deinit();

    const full_circle = 2 * std.math.pi;
    // start begins fast, speeding away from end
    const start = full_circle * easing.outSine(t);
    // end begins slow, catching up to start
    const end = full_circle * easing.inSine(t);

    path.addArc(r.center(), @min(r.w, r.h) / 3, start, end, false);
    path.build().stroke(.{ .thickness = 3.0 * rs.s, .color = options.color(.text) });
}

pub fn scale(src: std.builtin.SourceLocation, init_opts: ScaleWidget.InitOptions, opts: Options) *ScaleWidget {
    _ = src;
    _ = init_opts;
    _ = opts;
    return widgetAlloc(ScaleWidget);
}

pub fn menu(src: std.builtin.SourceLocation, dir: enums.Direction, opts: Options) *MenuWidget {
    _ = src;
    _ = dir;
    _ = opts;
    return widgetAlloc(MenuWidget);
}

pub fn menuItemLabel(src: std.builtin.SourceLocation, label_str: []const u8, init_opts: MenuItemWidget.InitOptions, opts: Options) ?Rect.Natural {
    _ = src;
    _ = label_str;
    _ = init_opts;
    _ = opts;
    return null;
}

pub fn menuItemIcon(src: std.builtin.SourceLocation, name: []const u8, tvg_bytes: []const u8, init_opts: MenuItemWidget.InitOptions, opts: Options) ?Rect.Natural {
    _ = src;
    _ = name;
    _ = tvg_bytes;
    _ = init_opts;
    _ = opts;
    return null;
}

pub fn menuItem(src: std.builtin.SourceLocation, init_opts: MenuItemWidget.InitOptions, opts: Options) *MenuItemWidget {
    _ = src;
    _ = init_opts;
    _ = opts;
    return widgetAlloc(MenuItemWidget);
}

/// A clickable label.  Good for hyperlinks.
/// Returns true if it's been clicked.
pub fn labelClick(src: std.builtin.SourceLocation, comptime fmt: []const u8, args: anytype, init_opts: LabelWidget.InitOptions, opts: Options) bool {
    const defaults: Options = .{ .name = "LabelClick", .role = .link };
    var lw = LabelWidget.init(src, fmt, args, init_opts, defaults.override(opts));
    // draw border and background
    lw.install();

    dvui.tabIndexSet(lw.data().id, lw.data().options.tab_index);

    const ret = dvui.clicked(lw.data(), .{});

    // draw text
    lw.draw();

    // draw an accent border if we are focused
    if (lw.data().id == dvui.focusedWidgetId()) {
        lw.data().focusBorder();
    }

    // done with lw, have it report min size to parent
    lw.deinit();

    return ret;
}

/// Format and display a label.
///
/// See `labelEx` and `labelNoFmt`.
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn label(src: std.builtin.SourceLocation, comptime fmt: []const u8, args: anytype, opts: Options) void {
    var lw = LabelWidget.init(src, fmt, args, .{}, opts);
    lw.install();
    lw.draw();
    lw.deinit();
}

/// Format and display a label with extra label options.
///
/// See `label` and `labelNoFmt`.
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn labelEx(src: std.builtin.SourceLocation, comptime fmt: []const u8, args: anytype, init_opts: LabelWidget.InitOptions, opts: Options) void {
    var lw = LabelWidget.init(src, fmt, args, init_opts, opts);
    lw.install();
    lw.draw();
    lw.deinit();
}

/// Display a label (no formatting) with extra label options.
///
/// See `label` and `labelEx`.
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn labelNoFmt(src: std.builtin.SourceLocation, str: []const u8, init_opts: LabelWidget.InitOptions, opts: Options) void {
    var lw = LabelWidget.initNoFmt(src, str, init_opts, opts);
    lw.install();
    lw.draw();
    lw.deinit();
}

/// Display an icon rasterized lazily from tvg_bytes.
///
/// See `buttonIcon` and `buttonLabelAndIcon`.
///
/// icon_opts controls the rasterization, and opts.color_text is multiplied in
/// the shader.  If icon_opts is the default, then the text color is multiplied
/// in the shader even if not passed in opts.
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn icon(src: std.builtin.SourceLocation, name: []const u8, tvg_bytes: []const u8, icon_opts: IconRenderOptions, opts: Options) void {
    var iw = IconWidget.init(src, name, tvg_bytes, icon_opts, opts);
    iw.install();
    iw.draw();
    iw.deinit();
}

pub const ImageInitOptions = struct {
    /// Data to create the texture.
    source: ImageSource,

    /// If min size is larger than the rect we got, how to shrink it:
    /// - null => use expand setting
    /// - none => crop
    /// - horizontal => crop height, fit width
    /// - vertical => crop width, fit height
    /// - both => fit in rect ignoring aspect ratio
    /// - ratio => fit in rect maintaining aspect ratio
    shrink: ?Options.Expand = null,

    uv: Rect = .{ .w = 1, .h = 1 },
};

/// Show raster image.  dvui will handle texture creation/destruction for you,
/// unless the source is .texture.  See ImageSource.InvalidationStrategy.
/// Please pass the .label option to add accessibility text to the image.
///
/// See `imageSize`.
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn image(src: std.builtin.SourceLocation, init_opts: ImageInitOptions, opts: Options) WidgetData {
    const options = (Options{ .name = "image", .role = .image }).override(opts);

    var size = Size{};
    if (options.min_size_content) |msc| {
        // user gave us a min size, use it
        size = msc;
    } else {
        // user didn't give us one, use natural size
        size = dvui.imageSize(init_opts.source) catch .{ .w = 10, .h = 10 };
    }

    var wd = WidgetData.init(src, .{}, options.override(.{ .min_size_content = size }));
    wd.register();

    const cr = wd.contentRect();
    const ms = wd.options.min_size_contentGet();

    var too_big = false;
    if (ms.w > cr.w or ms.h > cr.h) {
        too_big = true;
    }

    var e = wd.options.expandGet();
    if (too_big) {
        e = init_opts.shrink orelse e;
    }
    const g = wd.options.gravityGet();
    var rect = dvui.placeIn(cr, ms, e, g);

    if (too_big and e != .ratio) {
        if (ms.w > cr.w and !e.isHorizontal()) {
            rect.w = ms.w;
            rect.x -= g.x * (ms.w - cr.w);
        }

        if (ms.h > cr.h and !e.isVertical()) {
            rect.h = ms.h;
            rect.y -= g.y * (ms.h - cr.h);
        }
    }

    // rect is the content rect, so expand to the whole rect
    wd.rect = rect.outset(wd.options.paddingGet()).outset(wd.options.borderGet()).outset(wd.options.marginGet());

    var renderBackground: ?Color = if (wd.options.backgroundGet()) wd.options.color(.fill) else null;

    if (wd.options.rotationGet() == 0.0) {
        wd.borderAndBackground(.{});
        renderBackground = null;
    } else {
        if (wd.options.borderGet().nonZero()) {
            dvui.log.debug("image {x} can't render border while rotated\n", .{wd.id});
        }
    }
    const render_tex_opts = RenderTextureOptions{
        .rotation = wd.options.rotationGet(),
        .corner_radius = wd.options.corner_radiusGet(),
        .uv = init_opts.uv,
        .background_color = renderBackground,
    };
    const content_rs = wd.contentRectScale();
    renderImage(init_opts.source, content_rs, render_tex_opts) catch |err| logError(@src(), err, "Could not render image {?s} at {}", .{ opts.name, content_rs });
    wd.minSizeSetAndRefresh();
    wd.minSizeReportToParent();

    return wd;
}

pub fn debugFontAtlases(src: std.builtin.SourceLocation, opts: Options) void {
    const cw = currentWindow();

    var width: u32 = 0;
    var height: u32 = 0;
    var it = cw.fonts.cache.iterator();
    while (it.next()) |kv| {
        const texture_atlas = kv.value_ptr.getTextureAtlas(cw.gpa, cw.backend) catch |err| {
            dvui.logError(@src(), err, "Could not get texture atlast for '{s}' at height {d}", .{ kv.value_ptr.name, kv.value_ptr.height });
            continue;
        };
        width = @max(width, texture_atlas.width);
        height += texture_atlas.height;
    }

    const sizePhys: Size.Physical = .{ .w = @floatFromInt(width), .h = @floatFromInt(height) };

    const ss = parentGet().screenRectScale(Rect{}).s;
    const size = sizePhys.scale(1.0 / ss, Size);

    var wd = WidgetData.init(src, .{}, opts.override(.{ .name = "debugFontAtlases", .min_size_content = size }));
    wd.register();

    wd.borderAndBackground(.{});

    var rs = wd.parent.screenRectScale(placeIn(wd.contentRect(), size, .none, opts.gravityGet()));
    const color = opts.color(.text);

    it = cw.fonts.cache.iterator();
    while (it.next()) |kv| {
        const texture_atlas = kv.value_ptr.getTextureAtlas(cw.gpa, cw.backend) catch continue;
        rs.r = rs.r.toSize(.{
            .w = @floatFromInt(texture_atlas.width),
            .h = @floatFromInt(texture_atlas.height),
        });
        renderTexture(texture_atlas, rs, .{ .colormod = color }) catch |err| {
            logError(@src(), err, "Could not render font atlast for '{s}'", .{kv.value_ptr.name});
        };
        rs.r.y += rs.r.h;
    }

    wd.minSizeSetAndRefresh();
    wd.minSizeReportToParent();
}

pub fn button(src: std.builtin.SourceLocation, label_str: []const u8, init_opts: ButtonWidget.InitOptions, opts: Options) bool {
    // initialize widget and get rectangle from parent
    var bw = ButtonWidget.init(src, init_opts, opts);

    // make ourselves the new parent
    bw.install();

    // process events (mouse and keyboard)
    bw.processEvents();

    // draw background/border
    bw.drawBackground();

    // use pressed text color if desired
    const click = bw.clicked();

    // this child widget:
    // - has bw as parent
    // - gets a rectangle from bw
    // - draws itself
    // - reports its min size to bw
    labelNoFmt(@src(), label_str, .{ .align_x = 0.5, .align_y = 0.5 }, opts.strip().override(bw.style()).override(.{ .gravity_x = 0.5, .gravity_y = 0.5 }));

    // draw focus
    bw.drawFocus();

    // restore previous parent
    // send our min size to parent
    bw.deinit();

    return click;
}

pub fn buttonIcon(src: std.builtin.SourceLocation, name: []const u8, tvg_bytes: []const u8, init_opts: ButtonWidget.InitOptions, icon_opts: IconRenderOptions, opts: Options) bool {
    // set label on the button and clear role on icon so they don't duplicate
    const defaults = Options{ .padding = Rect.all(4), .label = .{ .text = name } };
    var bw = ButtonWidget.init(src, init_opts, defaults.override(opts));
    bw.install();
    bw.processEvents();
    bw.drawBackground();

    // When someone passes min_size_content to buttonIcon, they want the icon
    // to be that size, so we pass it through.
    icon(
        @src(),
        name,
        tvg_bytes,
        icon_opts,
        opts.strip().override(bw.style()).override(.{ .gravity_x = 0.5, .gravity_y = 0.5, .min_size_content = opts.min_size_content, .expand = .ratio, .color_text = opts.color_text, .role = .none }),
    );

    const click = bw.clicked();
    bw.drawFocus();
    bw.deinit();
    return click;
}

pub fn buttonLabelAndIcon(src: std.builtin.SourceLocation, label_str: []const u8, tvg_bytes: []const u8, init_opts: ButtonWidget.InitOptions, opts: Options) bool {
    // initialize widget and get rectangle from parent
    var bw = ButtonWidget.init(src, init_opts, opts);

    // make ourselves the new parent
    bw.install();

    // process events (mouse and keyboard)
    bw.processEvents();
    const options = opts.strip().override(bw.style()).override(.{ .gravity_y = 0.5 });

    // draw background/border
    bw.drawBackground();
    {
        var outer_hbox = box(src, .{ .dir = .horizontal }, .{ .expand = .horizontal });
        defer outer_hbox.deinit();
        icon(@src(), label_str, tvg_bytes, .{}, options.strip().override(.{ .gravity_x = 1.0, .color_text = opts.color_text }));
        labelEx(@src(), "{s}", .{label_str}, .{ .align_x = 0.5 }, options.strip().override(.{ .expand = .both }));
    }

    const click = bw.clicked();

    bw.drawFocus();

    bw.deinit();
    return click;
}

pub var slider_defaults: Options = .{
    .name = "Slider",
    .role = .slider,
    .padding = Rect.all(2),
    .min_size_content = .{ .w = 20, .h = 20 },
    .style = .control,
};

pub const SliderInitOptions = struct {
    fraction: *f32,

    dir: enums.Direction = .horizontal,

    /// Color of the left/top side of the slider.  If null, uses Theme.highlight.fill
    color_bar: ?Color = null,
};

/// returns true if fraction (0-1) was changed
pub fn slider(src: std.builtin.SourceLocation, init_opts: SliderInitOptions, opts: Options) bool {
    std.debug.assert(init_opts.fraction.* >= 0);
    std.debug.assert(init_opts.fraction.* <= 1);

    const options = slider_defaults.override(opts);

    var b = box(src, .{ .dir = init_opts.dir }, options);
    defer b.deinit();

    if (b.data().accesskit_node()) |ak_node| {
        AccessKit.nodeAddAction(ak_node, AccessKit.Action.focus);
        AccessKit.nodeAddAction(ak_node, AccessKit.Action.set_value);
        AccessKit.nodeSetOrientation(ak_node, switch (init_opts.dir) {
            .vertical => AccessKit.Orientation.vertical,
            .horizontal => AccessKit.Orientation.horizontal,
        });
        AccessKit.nodeSetNumericValue(ak_node, init_opts.fraction.*);
        AccessKit.nodeSetMinNumericValue(ak_node, 0);
        AccessKit.nodeSetMaxNumericValue(ak_node, 1);
    }

    tabIndexSet(b.data().id, options.tab_index);

    var hovered: bool = false;
    var ret = false;

    const br = b.data().contentRect();
    const knobsize = @min(br.w, br.h);
    const track = switch (init_opts.dir) {
        .horizontal => Rect{ .x = knobsize / 2, .y = br.h / 2 - 2, .w = br.w - knobsize, .h = 4 },
        .vertical => Rect{ .x = br.w / 2 - 2, .y = knobsize / 2, .w = 4, .h = br.h - knobsize },
    };

    const trackrs = b.widget().screenRectScale(track);

    const rs = b.data().contentRectScale();
    const evts = events();
    for (evts) |*e| {
        if (!eventMatch(e, .{ .id = b.data().id, .r = rs.r }))
            continue;

        switch (e.evt) {
            .mouse => |me| {
                var p: ?Point.Physical = null;
                if (me.action == .focus) {
                    e.handle(@src(), b.data());
                    focusWidget(b.data().id, null, e.num);
                } else if (me.action == .press and me.button.pointer()) {
                    // capture
                    captureMouse(b.data(), e.num);
                    e.handle(@src(), b.data());
                    p = me.p;
                } else if (me.action == .release and me.button.pointer()) {
                    // stop capture
                    captureMouse(null, e.num);
                    dragEnd();
                    e.handle(@src(), b.data());
                } else if (me.action == .motion and captured(b.data().id)) {
                    // handle only if we have capture
                    e.handle(@src(), b.data());
                    p = me.p;
                } else if (me.action == .position) {
                    dvui.cursorSet(.arrow);
                    hovered = true;
                }

                if (p) |pp| {
                    var min: f32 = undefined;
                    var max: f32 = undefined;
                    switch (init_opts.dir) {
                        .horizontal => {
                            min = trackrs.r.x;
                            max = trackrs.r.x + trackrs.r.w;
                        },
                        .vertical => {
                            min = 0;
                            max = trackrs.r.h;
                        },
                    }

                    if (max > min) {
                        const v = if (init_opts.dir == .horizontal) pp.x else (trackrs.r.y + trackrs.r.h - pp.y);
                        init_opts.fraction.* = (v - min) / (max - min);
                        init_opts.fraction.* = @max(0, @min(1, init_opts.fraction.*));
                        ret = true;
                    }
                }
            },
            .key => |ke| {
                if (ke.action == .down or ke.action == .repeat) {
                    switch (ke.code) {
                        .left, .down => {
                            e.handle(@src(), b.data());
                            init_opts.fraction.* = @max(0, @min(1, init_opts.fraction.* - 0.05));
                            ret = true;
                        },
                        .right, .up => {
                            e.handle(@src(), b.data());
                            init_opts.fraction.* = @max(0, @min(1, init_opts.fraction.* + 0.05));
                            ret = true;
                        },
                        else => {},
                    }
                }
            },
            .text => |te| blk: {
                e.handle(@src(), b.data());
                const value: f32 = std.fmt.parseFloat(f32, te.txt) catch break :blk;
                init_opts.fraction.* = std.math.clamp(value, 0.0, 1.0);
            },
        }
    }

    const perc = @max(0, @min(1, init_opts.fraction.*));

    var part = trackrs.r;
    switch (init_opts.dir) {
        .horizontal => part.w *= perc,
        .vertical => {
            const h = part.h * (1 - perc);
            part.y += h;
            part.h = trackrs.r.h - h;
        },
    }
    if (b.data().visible()) {
        part.fill(options.corner_radiusGet().scale(trackrs.s, Rect.Physical), .{ .color = init_opts.color_bar orelse dvui.themeGet().color(.highlight, .fill), .fade = 1.0 });
    }

    switch (init_opts.dir) {
        .horizontal => {
            part.x = part.x + part.w;
            part.w = trackrs.r.w - part.w;
        },
        .vertical => {
            part = trackrs.r;
            part.h *= (1 - perc);
        },
    }
    if (b.data().visible()) {
        part.fill(options.corner_radiusGet().scale(trackrs.s, Rect.Physical), .{ .color = options.color(.fill), .fade = 1.0 });
    }

    const knobRect = switch (init_opts.dir) {
        .horizontal => Rect{ .x = (br.w - knobsize) * perc, .w = knobsize, .h = knobsize },
        .vertical => Rect{ .y = (br.h - knobsize) * (1 - perc), .w = knobsize, .h = knobsize },
    };

    const fill_color: Color = if (captured(b.data().id))
        options.color(.fill_press)
    else if (hovered)
        options.color(.fill_hover)
    else
        options.color(.fill);
    var knob = BoxWidget.init(@src(), .{ .dir = .horizontal }, .{ .rect = knobRect, .padding = .{}, .margin = .{}, .background = true, .border = Rect.all(1), .corner_radius = Rect.all(100), .color_fill = fill_color });
    knob.install();
    knob.drawBackground();
    if (b.data().id == focusedWidgetId()) {
        knob.data().focusBorder();
    }
    knob.deinit();

    if (ret) {
        refresh(null, @src(), b.data().id);
    }

    return ret;
}

pub var progress_defaults: Options = .{
    .role = .progress_indicator,
    .padding = Rect.all(2),
    .min_size_content = .{ .w = 10, .h = 10 },
    .style = .control,
};

pub const Progress_InitOptions = struct {
    dir: enums.Direction = .horizontal,
    percent: f32,

    /// If null, uses Theme.highlight.fill
    color: ?Color = null,
};

pub fn progress(src: std.builtin.SourceLocation, init_opts: Progress_InitOptions, opts: Options) void {
    const options = progress_defaults.override(opts);

    var b = box(src, .{ .dir = init_opts.dir }, options);
    defer b.deinit();

    const rs = b.data().contentRectScale();

    rs.r.fill(options.corner_radiusGet().scale(rs.s, Rect.Physical), .{ .color = options.color(.fill), .fade = 1.0 });

    const perc = @max(0, @min(1, init_opts.percent));
    if (perc == 0) return;

    var part = rs.r;
    switch (init_opts.dir) {
        .horizontal => {
            part.w *= perc;
        },
        .vertical => {
            const h = part.h * (1 - perc);
            part.y += h;
            part.h = rs.r.h - h;
        },
    }
    part.fill(options.corner_radiusGet().scale(rs.s, Rect.Physical), .{ .color = init_opts.color orelse dvui.themeGet().color(.highlight, .fill), .fade = 1.0 });

    if (b.data().accesskit_node()) |ak_node| {
        AccessKit.nodeSetMinNumericValue(ak_node, 0);
        AccessKit.nodeSetMaxNumericValue(ak_node, 100);
        AccessKit.nodeSetNumericValue(ak_node, perc * 100);
    }
}

pub var checkbox_defaults: Options = .{
    .name = "Checkbox",
    .role = .check_box,
    .corner_radius = dvui.Rect.all(2),
    .padding = Rect.all(6),
};

pub fn checkbox(src: std.builtin.SourceLocation, target: *bool, label_str: ?[]const u8, opts: Options) bool {
    return checkboxEx(src, target, label_str, .{}, opts);
}

pub fn checkboxEx(src: std.builtin.SourceLocation, target: *bool, label_str: ?[]const u8, sel_opts: selection.SelectOptions, opts: Options) bool {
    const options = checkbox_defaults.override(opts);
    var ret = false;

    var b = box(src, .{ .dir = .horizontal }, options);
    defer b.deinit();

    dvui.tabIndexSet(b.data().id, b.data().options.tab_index);

    var hovered: bool = false;
    if (dvui.clicked(b.data(), .{ .hovered = &hovered })) {
        target.* = !target.*;
        ret = true;
        if (sel_opts.selection_info) |sel_info| {
            sel_info.add(sel_opts.selection_id, target.*, b.data());
        }
    }

    if (b.data().accesskit_node()) |ak_node| {
        AccessKit.nodeAddAction(ak_node, AccessKit.Action.focus);
        AccessKit.nodeAddAction(ak_node, AccessKit.Action.click);
        AccessKit.nodeSetToggled(ak_node, if (target.*) AccessKit.Toggled.ak_true else AccessKit.Toggled.ak_false);
    }

    const check_size = options.fontGet().textHeight();
    const s = spacer(@src(), .{ .min_size_content = Size.all(check_size), .gravity_y = 0.5 });

    const rs = s.borderRectScale();

    if (b.data().visible()) {
        const focused = b.data().id == dvui.focusedWidgetId();
        const pressed = dvui.captured(b.data().id);
        checkmark(target.*, focused, rs, pressed, hovered, options);
    }

    if (label_str) |str| {
        _ = spacer(@src(), .{ .min_size_content = .width(checkbox_defaults.paddingGet().w) });
        labelNoFmt(@src(), str, .{}, options.strip().override(.{ .gravity_y = 0.5 }));
    }

    return ret;
}

pub fn checkmark(checked: bool, focused: bool, rs: RectScale, pressed: bool, hovered: bool, opts: Options) void {
    const cornerRad = opts.corner_radiusGet().scale(rs.s, Rect.Physical);
    rs.r.fill(cornerRad, .{ .color = opts.color(.border), .fade = 1.0 });

    if (focused) {
        rs.r.stroke(cornerRad, .{ .thickness = 2 * rs.s, .color = dvui.themeGet().focus });
    }

    var fill: Options.ColorAsk = .fill;
    if (pressed) {
        fill = .fill_press;
    } else if (hovered) {
        fill = .fill_hover;
    }

    var options = opts;
    if (checked) {
        options.style = .highlight;
        rs.r.insetAll(0.5 * rs.s).fill(cornerRad, .{ .color = options.color(fill), .fade = 1.0 });
    } else {
        rs.r.insetAll(rs.s).fill(cornerRad, .{ .color = options.color(fill), .fade = 1.0 });
    }

    if (checked) {
        const r = rs.r.insetAll(0.5 * rs.s);
        const pad = @max(1.0, r.w / 6);

        var thick = @max(1.0, r.w / 5);
        const size = r.w - (thick / 2) - pad * 2;
        const third = size / 3.0;
        const x = r.x + pad + (0.25 * thick) + third;
        const y = r.y + pad + (0.25 * thick) + size - (third * 0.5);

        thick /= 1.5;

        const path: Path = .{ .points = &.{
            .{ .x = x - third, .y = y - third },
            .{ .x = x, .y = y },
            .{ .x = x + third * 2, .y = y - third * 2 },
        } };
        path.stroke(.{ .thickness = thick, .color = options.color(.text), .endcap_style = .square });
    }
}

pub var radio_defaults: Options = .{
    .name = "Radio",
    .role = .radio_button,
    .corner_radius = dvui.Rect.all(2),
    .padding = Rect.all(6),
};

pub fn radio(src: std.builtin.SourceLocation, active: bool, label_str: ?[]const u8, opts: Options) bool {
    const options = radio_defaults.override(opts);
    var ret = false;

    var b = box(src, .{ .dir = .horizontal }, options);
    defer b.deinit();

    dvui.tabIndexSet(b.data().id, b.data().options.tab_index);

    var hovered: bool = false;
    if (dvui.clicked(b.data(), .{ .hovered = &hovered })) {
        ret = true;
    }

    if (b.data().accesskit_node()) |ak_node| {
        AccessKit.nodeAddAction(ak_node, AccessKit.Action.focus);
        AccessKit.nodeAddAction(ak_node, AccessKit.Action.click);
        AccessKit.nodeSetToggled(ak_node, if (active) AccessKit.Toggled.ak_true else AccessKit.Toggled.ak_false);
    }

    const radio_size = options.fontGet().textHeight();
    const s = spacer(@src(), .{ .min_size_content = Size.all(radio_size), .gravity_y = 0.5 });

    const rs = s.borderRectScale();

    if (b.data().visible()) {
        const focused = b.data().id == dvui.focusedWidgetId();
        const pressed = dvui.captured(b.data().id);
        radioCircle(active or ret, focused, rs, pressed, hovered, options);
    }

    if (label_str) |str| {
        _ = spacer(@src(), .{ .min_size_content = .width(radio_defaults.paddingGet().w) });
        labelNoFmt(@src(), str, .{}, options.strip().override(.{ .gravity_y = 0.5 }));
    }

    return ret;
}

pub fn radioCircle(active: bool, focused: bool, rs: RectScale, pressed: bool, hovered: bool, opts: Options) void {
    const cornerRad = Rect.Physical.all(1000);
    const r = rs.r;
    r.fill(cornerRad, .{ .color = opts.color(.border), .fade = 1.0 });

    if (focused) {
        r.stroke(cornerRad, .{ .thickness = 2 * rs.s, .color = dvui.themeGet().focus });
    }

    var fill: Options.ColorAsk = .fill;
    if (pressed) {
        fill = .fill_press;
    } else if (hovered) {
        fill = .fill_hover;
    }

    var options = opts;
    if (active) {
        options.style = .highlight;
        r.insetAll(0.5 * rs.s).fill(cornerRad, .{ .color = options.color(fill), .fade = 1.0 });
    } else {
        r.insetAll(rs.s).fill(cornerRad, .{ .color = opts.color(fill), .fade = 1.0 });
    }

    if (active) {
        const thick = @max(1.0, r.w / 6);

        Path.stroke(.{ .points = &.{r.center()} }, .{ .thickness = thick, .color = options.color(.text) });
    }
}

/// The returned slice is guaranteed to be valid utf8. If the passed in slice
/// already was valid, the same slice will be returned. Otherwise, a new slice
/// will be allocated.
///
/// ```zig
/// const some_text = "This is some maybe utf8 text";
/// const utf8_text = try toUtf8(alloc, some_text);
/// // Detect if the text needs to be freed by checking the
/// defer if (utf8_text.ptr != some_text.ptr) alloc.free(utf8_text);
/// ```
pub fn toUtf8(allocator: std.mem.Allocator, text: []const u8) std.mem.Allocator.Error![]const u8 {
    if (std.unicode.utf8ValidateSlice(text)) return text;
    return std.fmt.allocPrint(allocator, "{f}", .{std.unicode.fmtUtf8(text)});
}

test toUtf8 {
    const alloc = std.testing.allocator;
    const some_text = "This is some maybe utf8 text";
    try std.testing.expect(std.unicode.utf8ValidateSlice(some_text));

    const utf8_text = try toUtf8(alloc, some_text);
    // Detect if the text needs to be freed by checking the
    defer if (utf8_text.ptr != some_text.ptr) alloc.free(utf8_text);

    try std.testing.expect(some_text.ptr == utf8_text.ptr);
    try std.testing.expect(std.unicode.utf8ValidateSlice(utf8_text));

    // And with some invalid utf8:
    const invalid_utf8 = "This \xFF is some\xFF invalid utf8\xFF";
    try std.testing.expect(!std.unicode.utf8ValidateSlice(invalid_utf8));

    const corrected_text = try toUtf8(alloc, invalid_utf8);
    // Detect if the text needs to be freed by checking the
    defer if (corrected_text.ptr != invalid_utf8.ptr) alloc.free(corrected_text);

    try std.testing.expect(invalid_utf8.ptr != corrected_text.ptr);
    try std.testing.expect(std.unicode.utf8ValidateSlice(corrected_text));
}

// pos is clamped to [0, text.len] then if it is in the middle of a multibyte
// utf8 char, we move it back to the beginning
pub fn findUtf8Start(text: []const u8, pos: usize) usize {
    var p = pos;
    p = @min(p, text.len);

    // find start of previous utf8 char
    var start = p -| 1;
    while (start > 0 and start < p and text[start] & 0xc0 == 0x80) {
        start -|= 1;
    }

    if (start < p) {
        const utf8_size = std.unicode.utf8ByteSequenceLength(text[start]) catch 0;
        if (utf8_size != (p - start)) {
            p = start;
        }
    }

    return p;
}

pub const ColorPickerInitOptions = struct {
    hsv: *Color.HSV,
    dir: enums.Direction = .horizontal,
    sliders: enum { rgb, hsv } = .rgb,
    alpha: bool = false,
    /// Shows a `textEntryColor`
    hex_text_entry: bool = true,
};

/// A photoshop style color picker
///
/// Returns true of the color was changed
pub fn colorPicker(src: std.builtin.SourceLocation, init_opts: ColorPickerInitOptions, opts: Options) bool {
    _ = src;
    _ = init_opts;
    _ = opts;
    return false;
}

/// Captures dvui drawing to part of the screen in a `Texture`.
pub const Picture = struct {
    r: Rect.Physical, // pixels captured
    texture: dvui.TextureTarget,
    target: dvui.RenderTarget,

    /// Begin recording drawing to the physical pixels in rect (enlarged to pixel boundaries).
    ///
    /// Returns null in case of failure (e.g. if backend does not support texture targets, if the passed rect is empty ...).
    ///
    /// Only valid between `Window.begin`and `Window.end`.
    pub fn start(rect: Rect.Physical) ?Picture {
        if (rect.empty()) {
            log.err("Picture.start() was called with an empty rect", .{});
            return null;
        }

        var r = rect;
        // enlarge texture to pixels boundaries
        const x_start = @floor(r.x);
        const x_end = @ceil(r.x + r.w);
        r.x = x_start;
        r.w = @round(x_end - x_start);

        const y_start = @floor(r.y);
        const y_end = @ceil(r.y + r.h);
        r.y = y_start;
        r.h = @round(y_end - y_start);

        const texture = dvui.textureCreateTarget(@intFromFloat(r.w), @intFromFloat(r.h), .linear) catch return null;
        const target = dvui.renderTarget(.{ .texture = texture, .offset = r.topLeft() });

        return .{
            .r = r,
            .texture = texture,
            .target = target,
        };
    }

    /// Stop recording.
    pub fn stop(self: *Picture) void {
        _ = dvui.renderTarget(self.target);
    }

    /// Encode texture as png.  Call after `stop` before `deinit`.
    pub fn png(self: *Picture, writer: *std.Io.Writer) !void {
        const pma_pixels = try dvui.textureReadTarget(currentWindow().lifo(), self.texture);
        const pixels = Color.PMA.sliceToRGBA(pma_pixels);
        defer currentWindow().lifo().free(pixels);

        try PNGEncoder.write(writer, pixels, self.texture.width, self.texture.height);
    }

    /// Encode texture as jpg.  Call after `stop` before `deinit`.
    pub fn jpg(self: *Picture, writer: *std.Io.Writer) !void {
        const pma_pixels = try dvui.textureReadTarget(currentWindow().lifo(), self.texture);
        const pixels = Color.PMA.sliceToRGBA(pma_pixels);
        defer currentWindow().lifo().free(pixels);

        try JPGEncoder.write(writer, pixels, self.texture.width, self.texture.height);
    }

    /// Draw recorded texture and destroy it.
    pub fn deinit(self: *Picture) void {
        defer self.* = undefined;
        // Ignore errors as drawing is not critical to Pictures function
        const texture = dvui.textureFromTarget(self.texture) catch return; // destroys self.texture
        dvui.textureDestroyLater(texture);
        dvui.renderTexture(texture, .{ .r = self.r }, .{}) catch {};
    }
};

pub fn plot(src: std.builtin.SourceLocation, plot_opts: PlotWidget.InitOptions, opts: Options) *PlotWidget {
    _ = src;
    _ = plot_opts;
    _ = opts;
    return widgetAlloc(PlotWidget);
}

pub const PlotXYOptions = struct {
    plot_opts: PlotWidget.InitOptions = .{},

    // Logical pixels
    thick: f32 = 1.0,

    // If null, uses Theme.highlight.fill
    color: ?Color = null,

    xs: []const f64,
    ys: []const f64,
};

pub fn plotXY(src: std.builtin.SourceLocation, init_opts: PlotXYOptions, opts: Options) void {
    const defaults: Options = .{ .padding = .{} };
    var p = dvui.plot(src, init_opts.plot_opts, defaults.override(opts));

    var s1 = p.line();
    for (init_opts.xs, init_opts.ys) |x, y| {
        s1.point(x, y);
    }

    s1.stroke(init_opts.thick, init_opts.color orelse dvui.themeGet().color(.highlight, .fill));

    s1.deinit();
    p.deinit();
}

/// Display a struct and allow the user to edit values
///
/// Refer to struct_ui.zig for full API.
/// Call StructOptions(T) to to create display options for the struct or use .{} for defaults.
/// See struct_ui.displayStruct for more details.
///
/// NOTE:
/// Any modifyable string slice fields are assigned to a duplicate copy of the the TextWidget's text.
/// These allocations are automatically cleaned up when Window.deinit() is called.
/// `struct_ui.string_map` can be used to check which strings have been modified and had memory allocated
/// or to remove strings that should not be automatically deallocated by struct_ui.
pub fn structUI(src: std.builtin.SourceLocation, comptime field_name: []const u8, struct_ptr: anytype, comptime depth: usize, struct_options: anytype) void {
    var vbox = dvui.box(src, .{ .dir = .vertical }, .{ .expand = .horizontal });
    defer vbox.deinit();
    const struct_box = struct_ui.displayStruct(@src(), field_name, struct_ptr, depth, .default, struct_options, null);
    if (struct_box) |b| b.deinit();
}

test {
    //std.debug.print("DVUI test\n", .{});
    std.testing.refAllDecls(@This());
}
