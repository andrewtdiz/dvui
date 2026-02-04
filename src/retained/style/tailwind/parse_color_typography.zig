const std = @import("std");
const dvui = @import("dvui");
const types = @import("types.zig");
const color_data = @import("../colors.zig");

const msdf_placeholder_font_id: ?dvui.Font.FontId = if (@hasDecl(dvui.Font, "msdf_placeholder_font_id"))
    @field(dvui.Font, "msdf_placeholder_font_id")
else
    null;
const msdf_enabled = msdf_placeholder_font_id != null;

const design_tokens = dvui.Theme.Tokens;
const theme_color_roles = design_tokens.color_roles;
const font_rules = design_tokens.typography_tokens;

const ColorMap = std.StaticStringMap(u32).initComptime(color_data.entries);

pub fn handleBackground(spec: *types.Spec, suffix: []const u8) void {
    if (lookupColorToken(.fill, suffix)) |color_value| {
        spec.background = color_value;
    }
}

pub fn handleText(spec: *types.Spec, suffix: []const u8) void {
    const outline_prefix = "outline-";
    if (std.mem.startsWith(u8, suffix, outline_prefix)) {
        const rest = suffix[outline_prefix.len..];
        if (rest.len == 0) return;
        if (parseOutlineThickness(rest)) |v| {
            spec.text_outline_thickness = v;
            return;
        }
        if (lookupColorToken(.text, rest)) |color_value| {
            spec.text_outline_color = color_value;
        }
        return;
    }
    if (lookupColorToken(.text, suffix)) |color_value| {
        spec.text = color_value;
    }
}

pub fn handleTypography(spec: *types.Spec, token: []const u8) bool {
    for (font_rules) |rule| {
        if (std.mem.eql(u8, token, rule.token)) {
            spec.font_style = rule.style;
            return true;
        }
    }
    return false;
}

pub fn handleFontToken(spec: *types.Spec, token: []const u8) bool {
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

pub fn handleFontRenderMode(spec: *types.Spec, token: []const u8) bool {
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

pub fn handleOpacity(spec: *types.Spec, token: []const u8) bool {
    const prefix = "opacity-";
    if (!std.mem.startsWith(u8, token, prefix)) return false;
    const suffix = token[prefix.len..];
    if (suffix.len == 0) return false;

    const int_value = std.fmt.parseInt(u8, suffix, 10) catch return false;
    if (int_value > 100) return false;

    spec.opacity = @as(f32, @floatFromInt(int_value)) / 100.0;
    return true;
}

pub fn handleHoverBackground(spec: *types.Spec, suffix: []const u8) void {
    if (lookupColorToken(.fill_hover, suffix)) |color_value| {
        spec.hover_background = color_value;
    }
}

pub fn handleHoverText(spec: *types.Spec, suffix: []const u8) void {
    const outline_prefix = "outline-";
    if (std.mem.startsWith(u8, suffix, outline_prefix)) {
        const rest = suffix[outline_prefix.len..];
        if (rest.len == 0) return;
        if (parseOutlineThickness(rest)) |v| {
            spec.hover_text_outline_thickness = v;
            return;
        }
        if (lookupColorToken(.text_hover, rest)) |color_value| {
            spec.hover_text_outline_color = color_value;
        }
        return;
    }
    if (lookupColorToken(.text_hover, suffix)) |color_value| {
        spec.hover_text = color_value;
    }
}

pub fn handleHoverOpacity(spec: *types.Spec, token: []const u8) bool {
    const prefix = "opacity-";
    if (!std.mem.startsWith(u8, token, prefix)) return false;
    const suffix = token[prefix.len..];
    if (suffix.len == 0) return false;
    const int_value = std.fmt.parseInt(u8, suffix, 10) catch return false;
    if (int_value > 100) return false;
    spec.hover_opacity = @as(f32, @floatFromInt(int_value)) / 100.0;
    return true;
}

pub fn resolveFont(spec: *const types.Spec, options: *dvui.Options) void {
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

pub fn lookupColorToken(ask: dvui.Options.ColorAsk, name: []const u8) ?types.ColorRef {
    return lookupThemeColor(ask, name) orelse lookupPaletteColor(name);
}

fn parseOutlineThickness(token: []const u8) ?f32 {
    if (token.len == 0) return null;
    if (token[0] == '[' and token[token.len - 1] == ']') {
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
    var num_slice = token;
    if (std.mem.endsWith(u8, num_slice, "px")) {
        num_slice = num_slice[0 .. num_slice.len - 2];
    }
    const value = std.fmt.parseFloat(f32, num_slice) catch return null;
    if (!std.math.isFinite(value) or value < 0) return null;
    return value;
}

fn lookupThemeColor(ask: dvui.Options.ColorAsk, name: []const u8) ?types.ColorRef {
    for (theme_color_roles) |role| {
        if (std.mem.eql(u8, name, role.token)) {
            return .{ .theme = .{ .style = role.style, .ask = ask } };
        }
    }
    return null;
}

fn lookupPaletteColor(name: []const u8) ?types.ColorRef {
    if (ColorMap.get(name)) |packed_value| {
        return .{ .palette_packed = packed_value };
    }
    return null;
}

fn colorFromPacked(value: u32) dvui.Color {
    const r: u8 = @intCast((value >> 24) & 0xff);
    const g: u8 = @intCast((value >> 16) & 0xff);
    const b: u8 = @intCast((value >> 8) & 0xff);
    const a: u8 = @intCast(value & 0xff);
    return dvui.Color{ .r = r, .g = g, .b = b, .a = a };
}

const FontTraits = struct {
    family: types.FontFamily,
    weight: types.FontWeight,
    slant: types.FontSlant,
};

fn resolveFontId(spec: *const types.Spec, base_id: dvui.Font.FontId) ?dvui.Font.FontId {
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
        .PixelOperator => .{ .family = .game, .weight = .normal, .slant = .normal },
        .PixelOperatorBd => .{ .family = .game, .weight = .bold, .slant = .normal },
        .OpenDyslexic => .{ .family = .dyslexic, .weight = .normal, .slant = .normal },
        .OpenDyslexicBd => .{ .family = .dyslexic, .weight = .bold, .slant = .normal },
        .OpenDyslexicIt => .{ .family = .dyslexic, .weight = .normal, .slant = .italic },
        .OpenDyslexicBdIt => .{ .family = .dyslexic, .weight = .bold, .slant = .italic },
        else => null,
    };
}

fn fontIdForFamily(family: types.FontFamily, weight: types.FontWeight, slant: types.FontSlant) dvui.Font.FontId {
    return switch (family) {
        .ui => fontIdForUi(weight, slant),
        .mono => fontIdForMono(weight, slant),
        .game => fontIdForGame(weight, slant),
        .dyslexic => fontIdForDyslexic(weight, slant),
    };
}

fn fontIdForUi(weight: types.FontWeight, slant: types.FontSlant) dvui.Font.FontId {
    return switch (weight) {
        .bold, .semibold => dvui.Font.FontId.SegoeUIBd,
        .light => if (slant == .italic) dvui.Font.FontId.SegoeUIIl else dvui.Font.FontId.SegoeUILt,
        .medium, .normal => if (slant == .italic) dvui.Font.FontId.SegoeUIIl else dvui.Font.FontId.SegoeUI,
    };
}

fn fontIdForMono(weight: types.FontWeight, slant: types.FontSlant) dvui.Font.FontId {
    return switch (weight) {
        .bold, .semibold => if (slant == .italic) dvui.Font.FontId.HackBdIt else dvui.Font.FontId.HackBd,
        .light, .medium, .normal => if (slant == .italic) dvui.Font.FontId.HackIt else dvui.Font.FontId.Hack,
    };
}

fn fontIdForGame(weight: types.FontWeight, slant: types.FontSlant) dvui.Font.FontId {
    _ = slant;
    return switch (weight) {
        .bold, .semibold => dvui.Font.FontId.PixelOperatorBd,
        .light, .medium, .normal => dvui.Font.FontId.PixelOperator,
    };
}

fn fontIdForDyslexic(weight: types.FontWeight, slant: types.FontSlant) dvui.Font.FontId {
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
