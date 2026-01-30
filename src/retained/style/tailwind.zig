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
const FontStyle = dvui.Options.FontStyle;

const msdf_placeholder_font_id: ?dvui.Font.FontId = if (@hasDecl(dvui.Font, "msdf_placeholder_font_id"))
    @field(dvui.Font, "msdf_placeholder_font_id")
else
    null;
const msdf_enabled = msdf_placeholder_font_id != null;

const color_data = @import("colors.zig");
const design_tokens = dvui.Theme.Tokens;

pub const TextAlign = enum {
    left,
    center,
    right,
};

pub const FontRenderMode = enum {
    auto,
    msdf,
    raster,
};

pub const FontFamily = enum {
    ui,
    mono,
    game,
    dyslexic,
};

pub const FontWeight = enum {
    light,
    normal,
    medium,
    semibold,
    bold,
};

pub const FontSlant = enum {
    normal,
    italic,
};

pub const Spec = struct {
    background: ?dvui.Color = null,
    text: ?dvui.Color = null,
    width: ?Width = null,
    height: ?Height = null,
    scale: ?f32 = null,
    is_flex: bool = false,
    position: ?Position = null,
    top: ?f32 = null,
    right: ?f32 = null,
    bottom: ?f32 = null,
    left: ?f32 = null,
    direction: ?dvui.enums.Direction = null,
    justify: ?dvui.FlexBoxWidget.ContentPosition = null,
    align_items: ?dvui.FlexBoxWidget.AlignItems = null,
    align_content: ?dvui.FlexBoxWidget.AlignContent = null,
    margin: SideValues = .{},
    padding: SideValues = .{},
    border: SideValues = .{},
    border_color: ?dvui.Color = null,
    font_style: ?FontStyle = null,
    font_family: ?FontFamily = null,
    font_weight: ?FontWeight = null,
    font_slant: ?FontSlant = null,
    font_render_mode: FontRenderMode = .auto,
    gap_row: ?f32 = null,
    gap_col: ?f32 = null,
    corner_radius: ?f32 = null,
    // Z-ordering (z-index). Default 0 preserves document order.
    z_index: i16 = design_tokens.z_index_default,
    // Clip descendants to this node's bounds (overflow-hidden).
    clip_children: ?bool = null,
    // New easy wins
    hidden: bool = false,
    opacity: ?f32 = null,
    text_align: ?TextAlign = null,
    text_wrap: bool = true,
    break_words: bool = false,
    cursor: ?dvui.enums.Cursor = null,
    hover_background: ?dvui.Color = null,
    hover_text: ?dvui.Color = null,
    hover_border: SideValues = .{},
    hover_border_color: ?dvui.Color = null,
    hover_opacity: ?f32 = null,
    transition: TransitionConfig = .{},
};

// Compatibility alias for callers expecting ClassSpec.
pub const ClassSpec = Spec;

pub const EasingStyle = enum {
    linear,
    sine,
    quad,
    cubic,
    quart,
    quint,
    expo,
    circ,
    back,
    elastic,
    bounce,
};

pub const EasingDirection = enum {
    @"in",
    out,
    in_out,
};

pub const TransitionProps = packed struct(u8) {
    layout: bool = false,
    transform: bool = false,
    colors: bool = false,
    opacity: bool = false,
    _pad: u4 = 0,
};

pub const TransitionConfig = struct {
    enabled: bool = false,
    props: TransitionProps = .{},
    duration_us: i32 = 150_000,
    easing_style: EasingStyle = .quad,
    easing_dir: EasingDirection = .in_out,

    pub fn easingFn(self: *const TransitionConfig) *const dvui.easing.EasingFn {
        if (!self.enabled) return dvui.easing.linear;
        if (self.easing_style == .linear) return dvui.easing.linear;

        return switch (self.easing_style) {
            .sine => switch (self.easing_dir) {
                .@"in" => dvui.easing.inSine,
                .out => dvui.easing.outSine,
                .in_out => dvui.easing.inOutSine,
            },
            .quad => switch (self.easing_dir) {
                .@"in" => dvui.easing.inQuad,
                .out => dvui.easing.outQuad,
                .in_out => dvui.easing.inOutQuad,
            },
            .cubic => switch (self.easing_dir) {
                .@"in" => dvui.easing.inCubic,
                .out => dvui.easing.outCubic,
                .in_out => dvui.easing.inOutCubic,
            },
            .quart => switch (self.easing_dir) {
                .@"in" => dvui.easing.inQuart,
                .out => dvui.easing.outQuart,
                .in_out => dvui.easing.inOutQuart,
            },
            .quint => switch (self.easing_dir) {
                .@"in" => dvui.easing.inQuint,
                .out => dvui.easing.outQuint,
                .in_out => dvui.easing.inOutQuint,
            },
            .expo => switch (self.easing_dir) {
                .@"in" => dvui.easing.inExpo,
                .out => dvui.easing.outExpo,
                .in_out => dvui.easing.inOutExpo,
            },
            .circ => switch (self.easing_dir) {
                .@"in" => dvui.easing.inCirc,
                .out => dvui.easing.outCirc,
                .in_out => dvui.easing.inOutCirc,
            },
            .back => switch (self.easing_dir) {
                .@"in" => dvui.easing.inBack,
                .out => dvui.easing.outBack,
                .in_out => dvui.easing.inOutBack,
            },
            .elastic => switch (self.easing_dir) {
                .@"in" => dvui.easing.inElastic,
                .out => dvui.easing.outElastic,
                .in_out => dvui.easing.inOutElastic,
            },
            .bounce => switch (self.easing_dir) {
                .@"in" => dvui.easing.inBounce,
                .out => dvui.easing.outBounce,
                .in_out => dvui.easing.inOutBounce,
            },
            .linear => dvui.easing.linear,
        };
    }
};

pub const Width = union(enum) {
    full,
    pixels: f32,
};

pub const Height = union(enum) {
    full,
    pixels: f32,
};

pub const Position = enum {
    absolute,
};

const SideTarget = enum {
    all,
    horizontal,
    vertical,
    top,
    right,
    bottom,
    left,
};

const SideValues = struct {
    left: ?f32 = null,
    right: ?f32 = null,
    top: ?f32 = null,
    bottom: ?f32 = null,

    fn any(self: *const SideValues) bool {
        return self.left != null or self.right != null or self.top != null or self.bottom != null;
    }

    fn set(self: *SideValues, target: SideTarget, value: f32) void {
        switch (target) {
            .all => {
                self.left = value;
                self.right = value;
                self.top = value;
                self.bottom = value;
            },
            .horizontal => {
                self.left = value;
                self.right = value;
            },
            .vertical => {
                self.top = value;
                self.bottom = value;
            },
            .top => self.top = value,
            .right => self.right = value,
            .bottom => self.bottom = value,
            .left => self.left = value,
        }
    }
};

const LiteralKind = enum {
    flex_display,
    flex_row,
    flex_col,
    absolute,
    justify_start,
    justify_center,
    justify_end,
    justify_between,
    justify_around,
    align_items_start,
    align_items_center,
    align_items_end,
    align_content_start,
    align_content_center,
    align_content_end,
    // Visibility
    hidden,
    overflow_hidden,
    // Text alignment
    text_left,
    text_center,
    text_right,
    text_nowrap,
    break_words,
};

const LiteralRule = struct {
    token: []const u8,
    kind: LiteralKind,
};

const literal_rules = [_]LiteralRule{
    .{ .token = "flex", .kind = .flex_display },
    .{ .token = "flex-row", .kind = .flex_row },
    .{ .token = "flex-col", .kind = .flex_col },
    .{ .token = "absolute", .kind = .absolute },
    .{ .token = "justify-start", .kind = .justify_start },
    .{ .token = "justify-center", .kind = .justify_center },
    .{ .token = "justify-end", .kind = .justify_end },
    .{ .token = "justify-between", .kind = .justify_between },
    .{ .token = "justify-around", .kind = .justify_around },
    .{ .token = "items-start", .kind = .align_items_start },
    .{ .token = "items-center", .kind = .align_items_center },
    .{ .token = "items-end", .kind = .align_items_end },
    .{ .token = "content-start", .kind = .align_content_start },
    .{ .token = "content-center", .kind = .align_content_center },
    .{ .token = "content-end", .kind = .align_content_end },
    // Visibility
    .{ .token = "hidden", .kind = .hidden },
    .{ .token = "overflow-hidden", .kind = .overflow_hidden },
    // Text alignment
    .{ .token = "text-left", .kind = .text_left },
    .{ .token = "text-center", .kind = .text_center },
    .{ .token = "text-right", .kind = .text_right },
    .{ .token = "text-nowrap", .kind = .text_nowrap },
    .{ .token = "break-words", .kind = .break_words },
};

const rounded_rules = design_tokens.radius_tokens;

const PrefixRule = struct {
    prefix: []const u8,
    handler: fn (*Spec, []const u8) void,
};

const prefix_rules: [4]PrefixRule = .{
    .{ .prefix = "bg-", .handler = handleBackground },
    .{ .prefix = "text-", .handler = handleText },
    .{ .prefix = "w-", .handler = handleWidth },
    .{ .prefix = "h-", .handler = handleHeight },
};

const ColorMap = std.StaticStringMap(u32).initComptime(color_data.entries);

const spacing_scale: f32 = design_tokens.spacing_unit;
const border_default_width: f32 = design_tokens.border_width_default;
const z_layer_tokens = design_tokens.z_layers;
const theme_color_roles = design_tokens.color_roles;

const font_rules = design_tokens.typography_tokens;

pub fn parse(classes: []const u8) Spec {
    var spec: Spec = .{};

    var tokens = std.mem.tokenizeAny(u8, classes, " \t\n\r");
    while (tokens.next()) |token| {
        if (token.len == 0) continue;
        if (handleHover(&spec, token)) continue;
        if (handleLiteral(&spec, token)) continue;
        if (handleSpacing(&spec, token)) continue;
        if (handleInset(&spec, token)) continue;
        if (handleGap(&spec, token)) continue;
        if (handleScale(&spec, token)) continue;
        if (handleBorder(&spec, token)) continue;
        if (handleRounded(&spec, token)) continue;
        if (handleTypography(&spec, token)) continue;
        if (handleFontToken(&spec, token)) continue;
        if (handleFontRenderMode(&spec, token)) continue;
        if (handleOpacity(&spec, token)) continue;
        if (handleZIndex(&spec, token)) continue;
        if (handleCursor(&spec, token)) continue;
        if (handleTransition(&spec, token)) continue;
        if (handleDuration(&spec, token)) continue;
        if (handleEase(&spec, token)) continue;
        _ = handlePrefixed(&spec, token);
    }

    return spec;
}

pub fn applyHover(spec: *Spec, hovered: bool) void {
    if (!hovered) return;
    if (spec.hover_background) |bg| spec.background = bg;
    if (spec.hover_text) |tc| spec.text = tc;
    if (spec.hover_opacity) |value| spec.opacity = value;
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
        spec.hover_opacity != null or
        spec.hover_border_color != null or
        spec.hover_border.any();
}

pub fn applyToOptions(spec: *const Spec, options: *dvui.Options) void {
    if (spec.background) |color_value| {
        options.color_fill = color_value;
        options.background = true;
    }
    if (spec.text) |color_value| {
        options.color_text = color_value;
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
    if (spec.border_color) |color_value| {
        options.color_border = color_value;
    }
    if (spec.font_style) |style| {
        options.font_style = style;
    }
    if (spec.corner_radius) |radius| {
        options.corner_radius = dvui.Rect.all(radius);
    }
    // Text alignment via gravity_x
    if (spec.text_align) |text_alignment| {
        options.gravity_x = switch (text_alignment) {
            .left => 0.0,
            .center => 0.5,
            .right => 1.0,
        };
    }
}

pub fn resolveFont(spec: *const Spec, options: *dvui.Options) void {
    const base_font = options.fontGet();
    var resolved_font = base_font;
    if (resolveFontId(spec, base_font.id)) |resolved_id| {
        if (resolved_id != resolved_font.id) {
            resolved_font = resolved_font.switchFont(resolved_id);
        }
    }
    if (spec.font_render_mode != .raster and msdf_enabled) {
        if (msdfFontIdFor(resolved_font.id)) |msdf_id| {
            if (msdf_id != resolved_font.id) {
                resolved_font = resolved_font.switchFont(msdf_id);
            }
        }
    }
    if (resolved_font.id != base_font.id) {
        options.font = resolved_font;
    }
}

pub fn buildFlexOptions(spec: *const Spec) dvui.FlexBoxWidget.InitOptions {
    var init: dvui.FlexBoxWidget.InitOptions = .{
        .direction = .horizontal,
        .justify_content = .start,
        .align_items = .start,
        .align_content = .start,
    };

    if (spec.direction) |dir| init.direction = dir;
    if (spec.justify) |value| init.justify_content = value;
    if (spec.align_items) |value| init.align_items = value;
    if (spec.align_content) |value| init.align_content = value;

    return init;
}

fn handleLiteral(spec: *Spec, token: []const u8) bool {
    for (literal_rules) |rule| {
        if (std.mem.eql(u8, token, rule.token)) {
            applyLiteral(spec, rule.kind);
            return true;
        }
    }
    return false;
}

fn handlePrefixed(spec: *Spec, token: []const u8) bool {
    inline for (prefix_rules) |rule| {
        if (token.len > rule.prefix.len and std.mem.startsWith(u8, token, rule.prefix)) {
            rule.handler(spec, token[rule.prefix.len..]);
            return true;
        }
    }
    return false;
}

fn handleTypography(spec: *Spec, token: []const u8) bool {
    for (font_rules) |rule| {
        if (std.mem.eql(u8, token, rule.token)) {
            spec.font_style = rule.style;
            return true;
        }
    }
    return false;
}

fn handleHover(spec: *Spec, token: []const u8) bool {
    const prefix = "hover:";
    if (!std.mem.startsWith(u8, token, prefix)) return false;
    const inner = token[prefix.len..];
    if (inner.len == 0) return true;
    if (handleHoverOpacity(spec, inner)) return true;
    if (handleHoverBorder(spec, inner)) return true;
    if (handleHoverPrefixed(spec, inner)) return true;
    return true;
}

fn handleHoverPrefixed(spec: *Spec, token: []const u8) bool {
    if (std.mem.startsWith(u8, token, "bg-")) {
        handleHoverBackground(spec, token[3..]);
        return true;
    }
    if (std.mem.startsWith(u8, token, "text-")) {
        handleHoverText(spec, token[5..]);
        return true;
    }
    return false;
}

fn handleHoverBackground(spec: *Spec, suffix: []const u8) void {
    if (lookupColorToken(.fill_hover, suffix)) |color_value| {
        spec.hover_background = color_value;
    }
}

fn handleHoverText(spec: *Spec, suffix: []const u8) void {
    if (lookupColorToken(.text_hover, suffix)) |color_value| {
        spec.hover_text = color_value;
    }
}

fn handleHoverOpacity(spec: *Spec, token: []const u8) bool {
    const prefix = "opacity-";
    if (!std.mem.startsWith(u8, token, prefix)) return false;
    const suffix = token[prefix.len..];
    if (suffix.len == 0) return false;
    const int_value = std.fmt.parseInt(u8, suffix, 10) catch return false;
    if (int_value > 100) return false;
    spec.hover_opacity = @as(f32, @floatFromInt(int_value)) / 100.0;
    return true;
}

fn handleHoverBorder(spec: *Spec, token: []const u8) bool {
    const prefix = "border";
    if (!std.mem.startsWith(u8, token, prefix)) return false;
    if (token.len == prefix.len) {
        spec.hover_border.set(.all, border_default_width);
        return true;
    }
    if (token.len <= prefix.len or token[prefix.len] != '-') return false;
    var suffix = token[(prefix.len + 1)..];
    if (suffix.len == 0) return false;

    if (suffix.len == 1) {
        const dir_target: ?SideTarget = switch (suffix[0]) {
            'x' => .horizontal,
            'y' => .vertical,
            't' => .top,
            'r' => .right,
            'b' => .bottom,
            'l' => .left,
            else => null,
        };
        if (dir_target) |target| {
            spec.hover_border.set(target, border_default_width);
            return true;
        }
    }

    if (parseDirectionPrefix(suffix)) |dir_info| {
        var rest = suffix[dir_info.consume_len..];
        if (rest.len == 0) {
            spec.hover_border.set(dir_info.target, border_default_width);
            return true;
        }
        if (rest[0] != '-') return false;
        rest = rest[1..];
        if (rest.len == 0) return false;
        if (parseBorderWidth(rest)) |value| {
            spec.hover_border.set(dir_info.target, value);
            return true;
        }
        if (lookupColorToken(.border, rest)) |color_value| {
            spec.hover_border_color = color_value;
            return true;
        }
        return false;
    }

    if (parseBorderWidth(suffix)) |width_value| {
        spec.hover_border.set(.all, width_value);
        return true;
    }

    if (lookupColorToken(.border, suffix)) |color_value| {
        spec.hover_border_color = color_value;
        return true;
    }

    return false;
}

fn handleFontToken(spec: *Spec, token: []const u8) bool {
    if (std.mem.eql(u8, token, "italic")) {
        spec.font_slant = .italic;
        return true;
    }
    if (std.mem.eql(u8, token, "not-italic")) {
        spec.font_slant = .normal;
        return true;
    }
    const prefix = "font-";
    if (token.len <= prefix.len or !std.mem.startsWith(u8, token, prefix)) return false;
    const suffix = token[prefix.len..];
    if (std.mem.eql(u8, suffix, "light")) {
        spec.font_weight = .light;
        return true;
    }
    if (std.mem.eql(u8, suffix, "normal")) {
        spec.font_weight = .normal;
        return true;
    }
    if (std.mem.eql(u8, suffix, "medium")) {
        spec.font_weight = .medium;
        return true;
    }
    if (std.mem.eql(u8, suffix, "semibold")) {
        spec.font_weight = .semibold;
        return true;
    }
    if (std.mem.eql(u8, suffix, "bold")) {
        spec.font_weight = .bold;
        return true;
    }
    if (std.mem.eql(u8, suffix, "ui")) {
        spec.font_family = .ui;
        return true;
    }
    if (std.mem.eql(u8, suffix, "mono")) {
        spec.font_family = .mono;
        return true;
    }
    if (std.mem.eql(u8, suffix, "game")) {
        spec.font_family = .game;
        return true;
    }
    if (std.mem.eql(u8, suffix, "dyslexic")) {
        spec.font_family = .dyslexic;
        return true;
    }
    return false;
}

fn handleFontRenderMode(spec: *Spec, token: []const u8) bool {
    const prefix = "font-render-";
    if (!std.mem.startsWith(u8, token, prefix)) return false;
    const suffix = token[prefix.len..];
    if (std.mem.eql(u8, suffix, "auto")) {
        spec.font_render_mode = .auto;
        return true;
    }
    if (std.mem.eql(u8, suffix, "msdf")) {
        spec.font_render_mode = .msdf;
        return true;
    }
    if (std.mem.eql(u8, suffix, "raster")) {
        spec.font_render_mode = .raster;
        return true;
    }
    return false;
}

const FontTraits = struct {
    family: FontFamily,
    weight: FontWeight,
    slant: FontSlant,
};

fn resolveFontId(spec: *const Spec, base_id: dvui.Font.FontId) ?dvui.Font.FontId {
    if (spec.font_family == null and spec.font_weight == null and spec.font_slant == null) return null;
    const inferred = fontTraitsFromId(base_id);
    const family = spec.font_family orelse if (inferred) |t| t.family else .ui;
    const weight = spec.font_weight orelse if (inferred) |t| t.weight else .normal;
    const slant = spec.font_slant orelse if (inferred) |t| t.slant else .normal;
    return fontIdForFamily(family, weight, slant);
}

fn fontTraitsFromId(font_id: dvui.Font.FontId) ?FontTraits {
    return switch (font_id) {
        .SegoeUI => .{ .family = .ui, .weight = .normal, .slant = .normal },
        .SegoeUIBd => .{ .family = .ui, .weight = .bold, .slant = .normal },
        .SegoeUILt => .{ .family = .ui, .weight = .light, .slant = .normal },
        .SegoeUIIl => .{ .family = .ui, .weight = .normal, .slant = .italic },
        .Hack => .{ .family = .mono, .weight = .normal, .slant = .normal },
        .HackBd => .{ .family = .mono, .weight = .bold, .slant = .normal },
        .HackIt => .{ .family = .mono, .weight = .normal, .slant = .italic },
        .HackBdIt => .{ .family = .mono, .weight = .bold, .slant = .italic },
        .Pixelify => .{ .family = .game, .weight = .normal, .slant = .normal },
        .PixelifyBd => .{ .family = .game, .weight = .bold, .slant = .normal },
        .PixelifyMe => .{ .family = .game, .weight = .medium, .slant = .normal },
        .PixelifySeBd => .{ .family = .game, .weight = .semibold, .slant = .normal },
        .OpenDyslexic => .{ .family = .dyslexic, .weight = .normal, .slant = .normal },
        .OpenDyslexicBd => .{ .family = .dyslexic, .weight = .bold, .slant = .normal },
        .OpenDyslexicIt => .{ .family = .dyslexic, .weight = .normal, .slant = .italic },
        .OpenDyslexicBdIt => .{ .family = .dyslexic, .weight = .bold, .slant = .italic },
        else => null,
    };
}

fn fontIdForFamily(family: FontFamily, weight: FontWeight, slant: FontSlant) dvui.Font.FontId {
    return switch (family) {
        .ui => fontIdForUi(weight, slant),
        .mono => fontIdForMono(weight, slant),
        .game => fontIdForGame(weight, slant),
        .dyslexic => fontIdForDyslexic(weight, slant),
    };
}

fn fontIdForUi(weight: FontWeight, slant: FontSlant) dvui.Font.FontId {
    return switch (weight) {
        .bold, .semibold => dvui.Font.FontId.SegoeUIBd,
        .light => if (slant == .italic) dvui.Font.FontId.SegoeUIIl else dvui.Font.FontId.SegoeUILt,
        .medium, .normal => if (slant == .italic) dvui.Font.FontId.SegoeUIIl else dvui.Font.FontId.SegoeUI,
    };
}

fn fontIdForMono(weight: FontWeight, slant: FontSlant) dvui.Font.FontId {
    return switch (weight) {
        .bold, .semibold => if (slant == .italic) dvui.Font.FontId.HackBdIt else dvui.Font.FontId.HackBd,
        .light, .medium, .normal => if (slant == .italic) dvui.Font.FontId.HackIt else dvui.Font.FontId.Hack,
    };
}

fn fontIdForGame(weight: FontWeight, slant: FontSlant) dvui.Font.FontId {
    _ = slant;
    return switch (weight) {
        .bold => dvui.Font.FontId.PixelifyBd,
        .semibold => dvui.Font.FontId.PixelifySeBd,
        .medium => dvui.Font.FontId.PixelifyMe,
        .light, .normal => dvui.Font.FontId.Pixelify,
    };
}

fn fontIdForDyslexic(weight: FontWeight, slant: FontSlant) dvui.Font.FontId {
    return switch (weight) {
        .bold, .semibold => if (slant == .italic) dvui.Font.FontId.OpenDyslexicBdIt else dvui.Font.FontId.OpenDyslexicBd,
        .light, .medium, .normal => if (slant == .italic) dvui.Font.FontId.OpenDyslexicIt else dvui.Font.FontId.OpenDyslexic,
    };
}

fn msdfFontIdFor(font_id: dvui.Font.FontId) ?dvui.Font.FontId {
    const placeholder = msdf_placeholder_font_id orelse return null;
    if (font_id == placeholder) return font_id;
    return switch (font_id) {
        .SegoeUI,
        .SegoeUIBd,
        .SegoeUIIl,
        .SegoeUILt,
        => placeholder,
        else => null,
    };
}

fn applyLiteral(spec: *Spec, kind: LiteralKind) void {
    switch (kind) {
        .flex_display => spec.is_flex = true,
        .flex_row => spec.direction = .horizontal,
        .flex_col => spec.direction = .vertical,
        .absolute => spec.position = .absolute,
        .justify_start => spec.justify = .start,
        .justify_center => spec.justify = .center,
        .justify_end => spec.justify = .end,
        .justify_between => spec.justify = .between,
        .justify_around => spec.justify = .around,
        .align_items_start => spec.align_items = .start,
        .align_items_center => spec.align_items = .center,
        .align_items_end => spec.align_items = .end,
        .align_content_start => spec.align_content = .start,
        .align_content_center => spec.align_content = .center,
        .align_content_end => spec.align_content = .end,
        // Visibility
        .hidden => spec.hidden = true,
        .overflow_hidden => spec.clip_children = true,
        // Text alignment
        .text_left => spec.text_align = .left,
        .text_center => spec.text_align = .center,
        .text_right => spec.text_align = .right,
        .text_nowrap => spec.text_wrap = false,
        .break_words => spec.break_words = true,
    }
}

fn handleOpacity(spec: *Spec, token: []const u8) bool {
    const prefix = "opacity-";
    if (!std.mem.startsWith(u8, token, prefix)) return false;
    const suffix = token[prefix.len..];
    if (suffix.len == 0) return false;

    // Handle common Tailwind opacity values: 0, 5, 10, 20, 25, 30, 40, 50, 60, 70, 75, 80, 90, 95, 100
    const int_value = std.fmt.parseInt(u8, suffix, 10) catch return false;
    if (int_value > 100) return false;

    spec.opacity = @as(f32, @floatFromInt(int_value)) / 100.0;
    return true;
}

fn handleZIndex(spec: *Spec, token: []const u8) bool {
    const neg_prefix = "-z-";
    const prefix = "z-";

    var negative = false;
    var suffix: []const u8 = undefined;

    if (std.mem.startsWith(u8, token, neg_prefix)) {
        negative = true;
        suffix = token[neg_prefix.len..];
    } else if (std.mem.startsWith(u8, token, prefix)) {
        suffix = token[prefix.len..];
    } else {
        return false;
    }

    if (suffix.len == 0) return false;
    if (std.mem.eql(u8, suffix, "auto")) {
        spec.z_index = design_tokens.z_index_default;
        return true;
    }

    if (lookupZLayer(suffix)) |layer_value| {
        const value = if (negative) -layer_value else layer_value;
        spec.z_index = value;
        return true;
    }

    if (suffix[0] == '[' and suffix[suffix.len - 1] == ']') {
        const inner = suffix[1 .. suffix.len - 1];
        if (inner.len == 0) return false;
        var value = std.fmt.parseInt(i16, inner, 10) catch return false;
        if (negative and value > 0) {
            value = -value;
        }
        spec.z_index = value;
        return true;
    }

    var value = std.fmt.parseInt(i16, suffix, 10) catch return false;
    if (negative) {
        value = -value;
    }
    spec.z_index = value;
    return true;
}

fn lookupZLayer(name: []const u8) ?i16 {
    for (z_layer_tokens) |layer| {
        if (std.mem.eql(u8, name, layer.token)) {
            return layer.value;
        }
    }
    return null;
}

fn handleCursor(spec: *Spec, token: []const u8) bool {
    const prefix = "cursor-";
    if (!std.mem.startsWith(u8, token, prefix)) return false;
    const name = token[prefix.len..];
    const cursor = if (std.mem.eql(u8, name, "auto") or std.mem.eql(u8, name, "default"))
        dvui.enums.Cursor.arrow
    else if (std.mem.eql(u8, name, "pointer"))
        dvui.enums.Cursor.hand
    else if (std.mem.eql(u8, name, "text"))
        dvui.enums.Cursor.ibeam
    else if (std.mem.eql(u8, name, "move"))
        dvui.enums.Cursor.arrow_all
    else if (std.mem.eql(u8, name, "wait"))
        dvui.enums.Cursor.wait
    else if (std.mem.eql(u8, name, "progress"))
        dvui.enums.Cursor.wait_arrow
    else if (std.mem.eql(u8, name, "crosshair"))
        dvui.enums.Cursor.crosshair
    else if (std.mem.eql(u8, name, "not-allowed"))
        dvui.enums.Cursor.bad
    else if (std.mem.eql(u8, name, "none"))
        dvui.enums.Cursor.hidden
    else if (std.mem.eql(u8, name, "grab") or std.mem.eql(u8, name, "grabbing"))
        dvui.enums.Cursor.hand
    else if (std.mem.eql(u8, name, "col-resize") or std.mem.eql(u8, name, "e-resize") or std.mem.eql(u8, name, "w-resize"))
        dvui.enums.Cursor.arrow_w_e
    else if (std.mem.eql(u8, name, "row-resize") or std.mem.eql(u8, name, "n-resize") or std.mem.eql(u8, name, "s-resize"))
        dvui.enums.Cursor.arrow_n_s
    else if (std.mem.eql(u8, name, "ne-resize") or std.mem.eql(u8, name, "sw-resize"))
        dvui.enums.Cursor.arrow_ne_sw
    else if (std.mem.eql(u8, name, "nw-resize") or std.mem.eql(u8, name, "se-resize"))
        dvui.enums.Cursor.arrow_nw_se
    else
        return false;
    spec.cursor = cursor;
    return true;
}

fn handleTransition(spec: *Spec, token: []const u8) bool {
    if (std.mem.eql(u8, token, "transition")) {
        spec.transition.enabled = true;
        spec.transition.props = .{ .layout = true, .transform = true, .colors = true, .opacity = true };
        return true;
    }
    if (std.mem.eql(u8, token, "transition-none")) {
        spec.transition = .{};
        return true;
    }
    if (std.mem.eql(u8, token, "transition-layout")) {
        spec.transition.enabled = true;
        spec.transition.props = .{ .layout = true };
        return true;
    }
    if (std.mem.eql(u8, token, "transition-transform")) {
        spec.transition.enabled = true;
        spec.transition.props = .{ .transform = true };
        return true;
    }
    if (std.mem.eql(u8, token, "transition-colors")) {
        spec.transition.enabled = true;
        spec.transition.props = .{ .colors = true };
        return true;
    }
    if (std.mem.eql(u8, token, "transition-opacity")) {
        spec.transition.enabled = true;
        spec.transition.props = .{ .opacity = true };
        return true;
    }
    return false;
}

fn handleDuration(spec: *Spec, token: []const u8) bool {
    const prefix = "duration-";
    if (!std.mem.startsWith(u8, token, prefix)) return false;
    const suffix = token[prefix.len..];
    if (suffix.len == 0) return false;

    const ms = std.fmt.parseInt(i32, suffix, 10) catch return false;
    const clamped_ms = std.math.clamp(ms, 0, 10_000);
    spec.transition.duration_us = clamped_ms * 1000;
    return true;
}

fn handleEase(spec: *Spec, token: []const u8) bool {
    if (std.mem.eql(u8, token, "ease-linear")) {
        spec.transition.easing_style = .linear;
        return true;
    }

    if (std.mem.eql(u8, token, "ease-in")) {
        spec.transition.easing_dir = .@"in";
        return true;
    }
    if (std.mem.eql(u8, token, "ease-out")) {
        spec.transition.easing_dir = .out;
        return true;
    }
    if (std.mem.eql(u8, token, "ease-in-out")) {
        spec.transition.easing_dir = .in_out;
        return true;
    }

    if (std.mem.eql(u8, token, "ease-sine")) {
        spec.transition.easing_style = .sine;
        return true;
    }
    if (std.mem.eql(u8, token, "ease-quad")) {
        spec.transition.easing_style = .quad;
        return true;
    }
    if (std.mem.eql(u8, token, "ease-cubic")) {
        spec.transition.easing_style = .cubic;
        return true;
    }
    if (std.mem.eql(u8, token, "ease-quart")) {
        spec.transition.easing_style = .quart;
        return true;
    }
    if (std.mem.eql(u8, token, "ease-quint")) {
        spec.transition.easing_style = .quint;
        return true;
    }
    if (std.mem.eql(u8, token, "ease-expo")) {
        spec.transition.easing_style = .expo;
        return true;
    }
    if (std.mem.eql(u8, token, "ease-circ")) {
        spec.transition.easing_style = .circ;
        return true;
    }
    if (std.mem.eql(u8, token, "ease-back")) {
        spec.transition.easing_style = .back;
        return true;
    }
    if (std.mem.eql(u8, token, "ease-elastic")) {
        spec.transition.easing_style = .elastic;
        return true;
    }
    if (std.mem.eql(u8, token, "ease-bounce")) {
        spec.transition.easing_style = .bounce;
        return true;
    }

    return false;
}

fn handleInset(spec: *Spec, token: []const u8) bool {
    const top_prefix = "top-";
    const right_prefix = "right-";
    const bottom_prefix = "bottom-";
    const left_prefix = "left-";

    if (std.mem.startsWith(u8, token, top_prefix)) {
        const value = parseInsetValue(token[top_prefix.len..]) orelse return false;
        spec.top = value;
        return true;
    }
    if (std.mem.startsWith(u8, token, right_prefix)) {
        const value = parseInsetValue(token[right_prefix.len..]) orelse return false;
        spec.right = value;
        return true;
    }
    if (std.mem.startsWith(u8, token, bottom_prefix)) {
        const value = parseInsetValue(token[bottom_prefix.len..]) orelse return false;
        spec.bottom = value;
        return true;
    }
    if (std.mem.startsWith(u8, token, left_prefix)) {
        const value = parseInsetValue(token[left_prefix.len..]) orelse return false;
        spec.left = value;
        return true;
    }

    return false;
}

fn parseInsetValue(token: []const u8) ?f32 {
    if (token.len == 0) return null;
    if (token[0] == '[' and token[token.len - 1] == ']') {
        const inner = token[1 .. token.len - 1];
        if (inner.len == 0) return null;

        var num_slice = inner;
        if (std.mem.endsWith(u8, inner, "px")) {
            num_slice = inner[0 .. inner.len - 2];
        }
        const value = std.fmt.parseFloat(f32, num_slice) catch return null;
        if (!std.math.isFinite(value)) return null;
        return value;
    }
    return parseSpacingValue(token);
}

fn parseBracketValue(token: []const u8) ?f32 {
    if (token.len < 2 or token[0] != '[' or token[token.len - 1] != ']') return null;
    const inner = token[1 .. token.len - 1];
    if (inner.len == 0) return null;

    var num_slice = inner;
    if (std.mem.endsWith(u8, inner, "px")) {
        num_slice = inner[0 .. inner.len - 2];
    }
    const value = std.fmt.parseFloat(f32, num_slice) catch return null;
    if (!std.math.isFinite(value) or value < 0) return null;
    return value;
}

fn handleBackground(spec: *Spec, suffix: []const u8) void {
    if (lookupColorToken(.fill, suffix)) |color_value| {
        spec.background = color_value;
    }
}

fn handleText(spec: *Spec, suffix: []const u8) void {
    if (lookupColorToken(.text, suffix)) |color_value| {
        spec.text = color_value;
    }
}

const width_full = "full";
const width_px = "px";
const height_full = "full";
const height_px = "px";
const dimension_scale: f32 = design_tokens.dimension_unit;

fn handleWidth(spec: *Spec, suffix: []const u8) void {
    if (std.mem.eql(u8, suffix, width_full)) {
        spec.width = .full;
        return;
    }
    if (std.mem.eql(u8, suffix, "screen")) {
        spec.width = .full; // screen = full viewport width
        return;
    }
    if (std.mem.eql(u8, suffix, width_px)) {
        spec.width = .{ .pixels = 1.0 };
        return;
    }
    if (parseBracketValue(suffix)) |value| {
        spec.width = .{ .pixels = value };
        return;
    }
    const value = std.fmt.parseFloat(f32, suffix) catch return;
    if (!std.math.isFinite(value) or value < 0) return;
    spec.width = .{ .pixels = value * dimension_scale };
}

fn handleHeight(spec: *Spec, suffix: []const u8) void {
    if (std.mem.eql(u8, suffix, height_full)) {
        spec.height = .full;
        return;
    }
    if (std.mem.eql(u8, suffix, "screen")) {
        spec.height = .full; // screen = full viewport height
        return;
    }
    if (std.mem.eql(u8, suffix, height_px)) {
        spec.height = .{ .pixels = 1.0 };
        return;
    }
    if (parseBracketValue(suffix)) |value| {
        spec.height = .{ .pixels = value };
        return;
    }
    const value = std.fmt.parseFloat(f32, suffix) catch return;
    if (!std.math.isFinite(value) or value < 0) return;
    spec.height = .{ .pixels = value * dimension_scale };
}

fn handleGap(spec: *Spec, token: []const u8) bool {
    const base = "gap-";
    if (!std.mem.startsWith(u8, token, base)) return false;
    var suffix = token[base.len..];
    if (suffix.len == 0) return false;

    if (suffix[0] == 'x' and suffix.len >= 2 and suffix[1] == '-') {
        suffix = suffix[2..];
        const value = parseSpacingValue(suffix) orelse return false;
        spec.gap_col = value;
        return true;
    }

    if (suffix[0] == 'y' and suffix.len >= 2 and suffix[1] == '-') {
        suffix = suffix[2..];
        const value = parseSpacingValue(suffix) orelse return false;
        spec.gap_row = value;
        return true;
    }

    const value = parseSpacingValue(suffix) orelse return false;
    spec.gap_col = value;
    spec.gap_row = value;
    return true;
}

fn handleScale(spec: *Spec, token: []const u8) bool {
    const base = "scale-";
    if (!std.mem.startsWith(u8, token, base)) return false;
    var suffix = token[base.len..];
    if (suffix.len == 0) return false;

    if (suffix[0] == '[' and suffix[suffix.len - 1] == ']') {
        suffix = suffix[1 .. suffix.len - 1];
        if (suffix.len == 0) return false;
        const value = std.fmt.parseFloat(f32, suffix) catch return false;
        if (!std.math.isFinite(value) or value <= 0) return false;
        spec.scale = value;
        return true;
    }

    const value = std.fmt.parseFloat(f32, suffix) catch return false;
    if (!std.math.isFinite(value) or value <= 0) return false;
    const scaled = if (value >= 10.0) value / 100.0 else value;
    spec.scale = scaled;
    return true;
}

fn handleSpacing(spec: *Spec, token: []const u8) bool {
    if (token.len < 3) return false;
    const kind = token[0];
    const is_margin = kind == 'm';
    const is_padding = kind == 'p';
    if (!is_margin and !is_padding) return false;

    var idx: usize = 1;
    var target: SideTarget = .all;
    if (idx < token.len and token[idx] != '-') {
        target = switch (token[idx]) {
            'x' => .horizontal,
            'y' => .vertical,
            't' => .top,
            'r' => .right,
            'b' => .bottom,
            'l' => .left,
            else => return false,
        };
        idx += 1;
    }
    if (idx >= token.len or token[idx] != '-') return false;
    idx += 1;
    if (idx >= token.len) return false;
    const value = parseSpacingValue(token[idx..]) orelse return false;
    if (is_margin) {
        spec.margin.set(target, value);
    } else {
        spec.padding.set(target, value);
    }
    return true;
}

fn handleBorder(spec: *Spec, token: []const u8) bool {
    const prefix = "border";
    if (!std.mem.startsWith(u8, token, prefix)) return false;
    if (token.len == prefix.len) {
        spec.border.set(.all, border_default_width);
        return true;
    }
    if (token.len <= prefix.len or token[prefix.len] != '-') return false;
    var suffix = token[(prefix.len + 1)..];
    if (suffix.len == 0) return false;

    if (suffix.len == 1) {
        const dir_target: ?SideTarget = switch (suffix[0]) {
            'x' => .horizontal,
            'y' => .vertical,
            't' => .top,
            'r' => .right,
            'b' => .bottom,
            'l' => .left,
            else => null,
        };
        if (dir_target) |target| {
            spec.border.set(target, border_default_width);
            return true;
        }
    }

    if (parseDirectionPrefix(suffix)) |dir_info| {
        var rest = suffix[dir_info.consume_len..];
        if (rest.len == 0) {
            spec.border.set(dir_info.target, border_default_width);
            return true;
        }
        if (rest[0] != '-') return false;
        rest = rest[1..];
        if (rest.len == 0) return false;
        if (parseBorderWidth(rest)) |value| {
            spec.border.set(dir_info.target, value);
            return true;
        }
        if (lookupColorToken(.border, rest)) |color_value| {
            spec.border_color = color_value;
            return true;
        }
        return false;
    }

    if (parseBorderWidth(suffix)) |width_value| {
        spec.border.set(.all, width_value);
        return true;
    }

    if (lookupColorToken(.border, suffix)) |color_value| {
        spec.border_color = color_value;
        return true;
    }

    return false;
}

fn handleRounded(spec: *Spec, token: []const u8) bool {
    inline for (rounded_rules) |rule| {
        if (std.mem.eql(u8, token, rule.token)) {
            spec.corner_radius = rule.radius;
            return true;
        }
    }
    return false;
}

fn parseDirectionPrefix(suffix: []const u8) ?struct { target: SideTarget, consume_len: usize } {
    if (suffix.len < 2 or suffix[1] != '-') return null;
    return switch (suffix[0]) {
        'x' => .{ .target = .horizontal, .consume_len = 1 },
        'y' => .{ .target = .vertical, .consume_len = 1 },
        't' => .{ .target = .top, .consume_len = 1 },
        'r' => .{ .target = .right, .consume_len = 1 },
        'b' => .{ .target = .bottom, .consume_len = 1 },
        'l' => .{ .target = .left, .consume_len = 1 },
        else => null,
    };
}

fn parseSpacingValue(token: []const u8) ?f32 {
    if (token.len == 0) return null;
    if (std.mem.eql(u8, token, "px")) return 1.0;
    const value = std.fmt.parseFloat(f32, token) catch return null;
    if (!std.math.isFinite(value) or value < 0) return null;
    return value * spacing_scale;
}

fn parseBorderWidth(token: []const u8) ?f32 {
    if (token.len == 0) return null;
    if (std.mem.eql(u8, token, "px")) return 1.0;
    const value = std.fmt.parseFloat(f32, token) catch return null;
    if (!std.math.isFinite(value) or value < 0) return null;
    return value;
}

fn applySideValues(values: *const SideValues, current: ?dvui.Rect) ?dvui.Rect {
    if (!values.any()) return current;
    var rect = current orelse dvui.Rect{};
    if (values.left) |v| rect.x = v;
    if (values.top) |v| rect.y = v;
    if (values.right) |v| rect.w = v;
    if (values.bottom) |v| rect.h = v;
    return rect;
}

fn lookupColorToken(ask: dvui.Options.ColorAsk, name: []const u8) ?dvui.Color {
    return lookupThemeColor(ask, name) orelse lookupPaletteColor(name);
}

fn lookupThemeColor(ask: dvui.Options.ColorAsk, name: []const u8) ?dvui.Color {
    const win = dvui.current_window orelse return null;
    for (theme_color_roles) |role| {
        if (std.mem.eql(u8, name, role.token)) {
            return win.theme.color(role.style, ask);
        }
    }
    return null;
}

fn lookupPaletteColor(name: []const u8) ?dvui.Color {
    if (ColorMap.get(name)) |_packed| {
        return colorFromPacked(_packed);
    }
    return null;
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

fn colorFromPacked(value: u32) dvui.Color {
    const r: u8 = @intCast((value >> 24) & 0xff);
    const g: u8 = @intCast((value >> 16) & 0xff);
    const b: u8 = @intCast((value >> 8) & 0xff);
    const a: u8 = @intCast(value & 0xff);
    return dvui.Color{ .r = r, .g = g, .b = b, .a = a };
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
