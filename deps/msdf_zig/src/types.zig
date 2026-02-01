const std = @import("std");

pub const HorizontalAlign = enum {
    left,
    center,
    right,
};

pub const VerticalAlign = enum {
    baseline,
    top,
    middle,
    bottom,
};

pub const TextAlignment = struct {
    horizontal: HorizontalAlign = .left,
    vertical: VerticalAlign = .baseline,
};

pub const MsdfTextFormattingOptions = struct {
    scale: f32 = 1.0,
    letter_spacing: f32 = 0.0,
    line_spacing: ?f32 = null,
    alignment: TextAlignment = .{},
};

pub const MsdfTextMeasurements = struct {
    width: f32,
    height: f32,
    line_count: u32,
    ascender: f32,
    descender: f32,
    printed_char_count: u32,
};

pub const Font = struct {
    pages: []const []const u8,
    chars: []const Char,
    info: Info,
    common: Common,
    distanceField: DistanceField,
    kernings: []const Kerning,
};

pub const Char = struct {
    id: i32,
    index: i32,
    char: []const u8,
    width: i32,
    height: i32,
    xoffset: i32,
    yoffset: i32,
    xadvance: i32,
    chnl: i32,
    x: i32,
    y: i32,
    page: i32,
};

pub const Info = struct {
    face: []const u8,
    size: i32,
    bold: i32,
    italic: i32,
    charset: []const []const u8,
    unicode: i32,
    stretchH: i32,
    smooth: i32,
    aa: i32,
    padding: [4]i32,
    spacing: [2]i32,
};

pub const Common = struct {
    lineHeight: i32,
    base: i32,
    scaleW: i32,
    scaleH: i32,
    pages: i32,
    @"packed": i32,
    alphaChnl: i32,
    redChnl: i32,
    greenChnl: i32,
    blueChnl: i32,
};

pub const DistanceField = struct {
    fieldType: []const u8,
    distanceRange: i32,
};

pub const Kerning = struct {
    first: i32,
    second: i32,
    amount: i32,
};

pub const MsdfChar = struct {
    codepoint: u21,
    advance: f32,
    size: [2]f32,
    offset: [2]f32,
    tex_offset: [2]f32,
    tex_extent: [2]f32,
};

pub const KerningKey = struct {
    first: u21,
    second: u21,
};

pub const KerningMap = std.AutoHashMap(KerningKey, f32);

pub const GpuChar = extern struct {
    tex_offset: [2]f32,
    tex_extent: [2]f32,
    size: [2]f32,
    offset: [2]f32,
};

pub const GpuTextHeader = extern struct {
    transform: [4][4]f32,
    fill_color: [4]f32,
    outline_color: [4]f32,
    scale: f32,
    px_range: f32,
    outline_width_px: f32,
    _padding: f32,
};

pub const GpuTextInstance = extern struct {
    position: [2]f32,
    glyph_index: f32,
    _padding: f32 = 0.0,
};

pub const MsdfFontMetrics = struct {
    line_height: f32,
    ascender: f32,
    descender: f32,
};

pub const AtlasPixels = struct {
    data: []const u8,
    width: u32,
    height: u32,
    bytes_per_pixel: u32 = 4,
};
