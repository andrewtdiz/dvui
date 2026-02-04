//! Tailwind-like class contract for retained styles.
//!
//! Design tokens live in `dvui.Theme.Tokens` to stay aligned with immediate-mode themes.
//! Supported tokens:
//! - Colors: `bg-{role}`, `text-{role}`, `border-{role}` for theme roles
//!   (`content`, `window`, `control`, `highlight`, `err`, `app1`, `app2`, `app3`)
//!   plus palette names from `colors.zig` (e.g. `slate-900`, `blue-500`).
//! - Spacing: `m-`, `p-`, `gap-`, `top-`, `right-`, `bottom-`, `left-` use `spacing_unit`
//!   and accept numeric scales or bracketed `[Npx]` values.
//! - Sizing: `w-`, `h-` use `dimension_unit` with `full`, `screen`, `px`, or `[Npx]`.
//! - Radii: `rounded-*` tokens from `Tokens.radius_tokens`.
//! - Typography: `text-{xs|sm|base|lg|xl|2xl|3xl}` mapped to `Options.FontStyle`.
//! - Z-layers: `z-{base|dropdown|overlay|modal|popover|tooltip}` plus numeric `z-*`/`z-[N]`.
//! - Layout: `flex`, `flex-row`, `flex-col`, `absolute`, `justify-*`, `items-*`, `content-*`,
//!   `hidden`, `overflow-hidden`, `text-left`, `text-center`, `text-right`, `text-nowrap`, `break-words`.
//! - Extras: `opacity-*`, `cursor-*`, `scale-*`, `font-*`, `italic`, `not-italic`, plus `hover:` variants
//!   for `bg-`, `text-`, `border-`, `opacity-`.
//! - Transitions: `transition*`, `duration-*`, `ease-*`.
const std = @import("std");
const dvui = @import("dvui");

const types = @import("tailwind/types.zig");
const parser = @import("tailwind/parse.zig");
const color_typography = @import("tailwind/parse_color_typography.zig");

const spec_cache_allocator = std.heap.c_allocator;
const SpecCache = std.StringHashMap(types.Spec);
var spec_cache: SpecCache = undefined;
var spec_cache_ready: bool = false;

fn ensureSpecCacheReady() void {
    if (spec_cache_ready) return;
    spec_cache = SpecCache.init(spec_cache_allocator);
    spec_cache_ready = true;
}

fn releaseSpecCache() void {
    if (!spec_cache_ready) return;
    var iter = spec_cache.iterator();
    while (iter.next()) |entry| {
        spec_cache_allocator.free(entry.key_ptr.*);
    }
    spec_cache.deinit();
    spec_cache_ready = false;
}

fn cacheSpec(classes: []const u8, spec: types.Spec) void {
    if (!spec_cache_ready or classes.len == 0) return;
    const key = spec_cache_allocator.dupe(u8, classes) catch return;
    const gop = spec_cache.getOrPut(key) catch {
        spec_cache_allocator.free(key);
        return;
    };
    if (gop.found_existing) {
        spec_cache_allocator.free(key);
        return;
    }
    gop.key_ptr.* = key;
    gop.value_ptr.* = spec;
}

pub const TextAlign = types.TextAlign;
pub const FontRenderMode = types.FontRenderMode;
pub const FontFamily = types.FontFamily;
pub const FontWeight = types.FontWeight;
pub const FontSlant = types.FontSlant;
pub const ThemeColorRef = types.ThemeColorRef;
pub const ColorRef = types.ColorRef;
pub const Spec = types.Spec;
pub const ClassSpec = types.ClassSpec;
pub const EasingStyle = types.EasingStyle;
pub const EasingDirection = types.EasingDirection;
pub const TransitionProps = types.TransitionProps;
pub const TransitionConfig = types.TransitionConfig;
pub const Width = types.Width;
pub const Height = types.Height;
pub const Inset = types.Inset;
pub const Position = types.Position;

pub const resolveFont = color_typography.resolveFont;

fn colorFromPacked(value: u32) dvui.Color {
    const r: u8 = @intCast((value >> 24) & 0xff);
    const g: u8 = @intCast((value >> 16) & 0xff);
    const b: u8 = @intCast((value >> 8) & 0xff);
    const a: u8 = @intCast(value & 0xff);
    return .{ .r = r, .g = g, .b = b, .a = a };
}

pub fn resolveColor(win: *dvui.Window, ref: types.ColorRef) dvui.Color {
    return switch (ref) {
        .palette_packed => |packed_value| colorFromPacked(packed_value),
        .theme => |role| win.theme.color(role.style, role.ask),
    };
}

pub fn resolveColorOpt(win: *dvui.Window, ref: ?types.ColorRef) ?dvui.Color {
    if (ref) |value| return resolveColor(win, value);
    return null;
}

pub fn init() void {
    ensureSpecCacheReady();
}

pub fn deinit() void {
    releaseSpecCache();
}

pub fn parse(classes: []const u8) types.Spec {
    ensureSpecCacheReady();
    if (spec_cache.get(classes)) |cached| return cached;
    const spec = parser.parse(classes);
    cacheSpec(classes, spec);
    return spec;
}

pub fn applyHover(spec: *Spec, hovered: bool) void {
    if (!hovered) return;
    if (spec.hover_background) |bg| spec.background = bg;
    if (spec.hover_text) |tc| spec.text = tc;
    if (spec.hover_text_outline_color) |tc| spec.text_outline_color = tc;
    if (spec.hover_text_outline_thickness) |v| spec.text_outline_thickness = v;
    if (spec.hover_opacity) |value| spec.opacity = value;
    if (spec.hover_margin.any()) {
        if (spec.hover_margin.left) |v| spec.margin.left = v;
        if (spec.hover_margin.right) |v| spec.margin.right = v;
        if (spec.hover_margin.top) |v| spec.margin.top = v;
        if (spec.hover_margin.bottom) |v| spec.margin.bottom = v;
    }
    if (spec.hover_padding.any()) {
        if (spec.hover_padding.left) |v| spec.padding.left = v;
        if (spec.hover_padding.right) |v| spec.padding.right = v;
        if (spec.hover_padding.top) |v| spec.padding.top = v;
        if (spec.hover_padding.bottom) |v| spec.padding.bottom = v;
    }
    if (spec.hover_border.any()) {
        if (spec.hover_border.left) |v| spec.border.left = v;
        if (spec.hover_border.right) |v| spec.border.right = v;
        if (spec.hover_border.top) |v| spec.border.top = v;
        if (spec.hover_border.bottom) |v| spec.border.bottom = v;
    }
    if (spec.hover_border_color) |color| spec.border_color = color;
}

pub fn hasHover(spec: *const Spec) bool {
    return spec.hover_background != null or
        spec.hover_text != null or
        spec.hover_text_outline_color != null or
        spec.hover_text_outline_thickness != null or
        spec.hover_opacity != null or
        spec.hover_margin.any() or
        spec.hover_padding.any() or
        spec.hover_border_color != null or
        spec.hover_border.any();
}

pub fn hasHoverLayout(spec: *const Spec) bool {
    return spec.hover_margin.any() or spec.hover_padding.any();
}

pub fn applyToOptions(win: *dvui.Window, spec: *const Spec, options: *dvui.Options) void {
    if (spec.background) |color_ref| {
        options.color_fill = resolveColor(win, color_ref);
        options.background = true;
    }
    if (spec.text) |color_ref| {
        options.color_text = resolveColor(win, color_ref);
    }
    if (spec.width) |w| {
        switch (w) {
            .full => applyFullWidth(options),
            .pixels => |px| applyFixedWidth(options, px),
        }
    }
    if (spec.height) |h| {
        switch (h) {
            .full => applyFullHeight(options),
            .pixels => |px| applyFixedHeight(options, px),
        }
    }
    options.margin = applySideValues(&spec.margin, options.margin);
    options.padding = applySideValues(&spec.padding, options.padding);
    options.border = applySideValues(&spec.border, options.border);
    if (spec.border_color) |color_ref| {
        options.color_border = resolveColor(win, color_ref);
    }
    if (spec.font_style) |style| {
        options.font_style = style;
    }
    if (spec.corner_radius) |radius| {
        options.corner_radius = dvui.Rect.all(radius);
    }
    if (spec.text_align) |text_alignment| {
        options.gravity_x = switch (text_alignment) {
            .left => 0.0,
            .center => 0.5,
            .right => 1.0,
        };
    }
}

pub fn buildFlexOptions(spec: *const Spec) dvui.FlexBoxWidget.InitOptions {
    var options: dvui.FlexBoxWidget.InitOptions = .{
        .direction = .horizontal,
        .justify_content = .start,
        .align_items = .start,
        .align_content = .start,
    };

    if (spec.direction) |dir| options.direction = dir;
    if (spec.justify) |value| options.justify_content = value;
    if (spec.align_items) |value| options.align_items = value;
    if (spec.align_content) |value| options.align_content = value;

    return options;
}

fn applySideValues(values: *const types.SideValues, current: ?dvui.Rect) ?dvui.Rect {
    if (!values.any()) return current;
    var rect = current orelse dvui.Rect{};
    if (values.left) |v| rect.x = v;
    if (values.top) |v| rect.y = v;
    if (values.right) |v| rect.w = v;
    if (values.bottom) |v| rect.h = v;
    return rect;
}

fn applyFullWidth(options: *dvui.Options) void {
    if (options.expand) |current| {
        options.expand = switch (current) {
            .none, .horizontal => .horizontal,
            .vertical => .both,
            .both => .both,
            .ratio => .ratio,
        };
    } else {
        options.expand = .horizontal;
    }
}

fn applyFixedWidth(options: *dvui.Options, width: f32) void {
    var min_size = options.min_size_content orelse dvui.Size{};
    min_size.w = width;
    options.min_size_content = min_size;

    var max_size = options.max_size_content orelse dvui.Options.MaxSize{
        .w = dvui.max_float_safe,
        .h = dvui.max_float_safe,
    };
    max_size.w = width;
    options.max_size_content = max_size;
}

fn applyFullHeight(options: *dvui.Options) void {
    if (options.expand) |current| {
        options.expand = switch (current) {
            .none, .vertical => .vertical,
            .horizontal => .both,
            .both => .both,
            .ratio => .ratio,
        };
    } else {
        options.expand = .vertical;
    }
}

fn applyFixedHeight(options: *dvui.Options, height: f32) void {
    var min_size = options.min_size_content orelse dvui.Size{};
    min_size.h = height;
    options.min_size_content = min_size;

    var max_size = options.max_size_content orelse dvui.Options.MaxSize{
        .w = dvui.max_float_safe,
        .h = dvui.max_float_safe,
    };
    max_size.h = height;
    options.max_size_content = max_size;
}

test "tailwind transition parsing" {
    const a = parse("transition duration-200 ease-sine ease-in");
    try std.testing.expect(a.transition.enabled);
    try std.testing.expect(a.transition.props.layout);
    try std.testing.expect(a.transition.props.transform);
    try std.testing.expect(a.transition.props.colors);
    try std.testing.expect(a.transition.props.opacity);
    try std.testing.expectEqual(@as(i32, 200_000), a.transition.duration_us);
    try std.testing.expectEqual(EasingStyle.sine, a.transition.easing_style);
    try std.testing.expectEqual(EasingDirection.@"in", a.transition.easing_dir);

    const b = parse("transition-opacity duration-75 ease-linear ease-in-out");
    try std.testing.expect(b.transition.enabled);
    try std.testing.expect(b.transition.props.opacity);
    try std.testing.expect(!b.transition.props.layout);
    try std.testing.expect(!b.transition.props.transform);
    try std.testing.expect(!b.transition.props.colors);
    try std.testing.expectEqual(@as(i32, 75_000), b.transition.duration_us);
    try std.testing.expectEqual(EasingStyle.linear, b.transition.easing_style);

    const c1 = parse("transition ease-in-out ease-quad");
    const c2 = parse("transition ease-quad ease-in-out");
    try std.testing.expectEqual(c1.transition.easing_style, c2.transition.easing_style);
    try std.testing.expectEqual(c1.transition.easing_dir, c2.transition.easing_dir);
}

test "tailwind overflow scroll parsing" {
    const a = parse("overflow-scroll");
    try std.testing.expect(a.scroll_x);
    try std.testing.expect(a.scroll_y);

    const b = parse("overflow-y-scroll");
    try std.testing.expect(!b.scroll_x);
    try std.testing.expect(b.scroll_y);

    const c = parse("overflow-x-scroll");
    try std.testing.expect(c.scroll_x);
    try std.testing.expect(!c.scroll_y);
}

test "tailwind palette color refs" {
    const color_data = @import("colors.zig");
    const ColorMap = std.StaticStringMap(u32).initComptime(color_data.entries);
    const expected = ColorMap.get("slate-900") orelse return error.TestUnexpectedResult;
    const spec = parse("bg-slate-900");
    const bg = spec.background orelse return error.TestUnexpectedResult;
    switch (bg) {
        .palette_packed => |packed_value| try std.testing.expectEqual(expected, packed_value),
        else => return error.TestUnexpectedResult,
    }
}

test "tailwind theme role refs" {
    const bg_spec = parse("bg-content");
    const bg = bg_spec.background orelse return error.TestUnexpectedResult;
    switch (bg) {
        .theme => |role| {
            try std.testing.expectEqual(dvui.Theme.Style.Name.content, role.style);
            try std.testing.expectEqual(dvui.Options.ColorAsk.fill, role.ask);
        },
        else => return error.TestUnexpectedResult,
    }

    const text_spec = parse("text-content");
    const text = text_spec.text orelse return error.TestUnexpectedResult;
    switch (text) {
        .theme => |role| {
            try std.testing.expectEqual(dvui.Theme.Style.Name.content, role.style);
            try std.testing.expectEqual(dvui.Options.ColorAsk.text, role.ask);
        },
        else => return error.TestUnexpectedResult,
    }
}

test "tailwind hover theme role ask preserved" {
    var spec = parse("hover:bg-content");
    try std.testing.expect(spec.background == null);
    const hover_bg = spec.hover_background orelse return error.TestUnexpectedResult;
    switch (hover_bg) {
        .theme => |role| try std.testing.expectEqual(dvui.Options.ColorAsk.fill_hover, role.ask),
        else => return error.TestUnexpectedResult,
    }

    applyHover(&spec, true);
    const bg = spec.background orelse return error.TestUnexpectedResult;
    switch (bg) {
        .theme => |role| try std.testing.expectEqual(dvui.Options.ColorAsk.fill_hover, role.ask),
        else => return error.TestUnexpectedResult,
    }
}
