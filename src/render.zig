const dvui = @import("dvui.zig");

const Backend = dvui.Backend;
const Font = dvui.Font;
const Color = dvui.Color;
const Point = dvui.Point;
const Rect = dvui.Rect;
const RectScale = dvui.RectScale;
const Triangles = dvui.Triangles;
const Texture = dvui.Texture;
const ImageSource = dvui.ImageSource;
const IconRenderOptions = dvui.IconRenderOptions;
const StbImageError = dvui.StbImageError;

/// Legacy placeholder for the old render target API.  The structure still
/// exists so higher level code can save/restore state, but the fields no
/// longer drive any backend behaviour now that rendering is handled by the
/// webview.
pub const Target = struct {
    texture: ?Texture.Target = null,
    offset: Point.Physical = .{},
    rendering: bool = true,

    pub fn setAsCurrent(target: Target) Target {
        _ = target;
        return .{};
    }
};

/// Structure describing text draw requests.  Kept for compatibility with the
/// previous immediate-mode renderer even though the values are now unused.
pub const TextOptions = struct {
    font: Font,
    text: []const u8,
    rs: RectScale,
    color: Color,
    background_color: ?Color = null,
    sel_start: ?usize = null,
    sel_end: ?usize = null,
    sel_color: ?Color = null,
    debug: bool = false,
    kerning: ?bool = null,
    kern_in: ?[]u32 = null,
};

pub const TextureOptions = struct {
    rotation: f32 = 0,
    colormod: Color = .{},
    corner_radius: Rect = .{},
    uv: Rect = .{ .w = 1, .h = 1 },
    background_color: ?Color = null,
    debug: bool = false,
    fade: f32 = 0.0,
};

pub fn renderTriangles(triangles: Triangles, tex: ?Texture) Backend.GenericError!void {
    _ = triangles;
    _ = tex;
}

pub fn renderText(opts: TextOptions) Backend.GenericError!void {
    _ = opts;
}

pub fn renderTexture(tex: Texture, rs: RectScale, opts: TextureOptions) Backend.GenericError!void {
    _ = tex;
    _ = rs;
    _ = opts;
}

pub fn renderIcon(name: []const u8, tvg_bytes: []const u8, rs: RectScale, opts: TextureOptions, icon_opts: IconRenderOptions) Backend.GenericError!void {
    _ = name;
    _ = tvg_bytes;
    _ = rs;
    _ = opts;
    _ = icon_opts;
}

pub fn renderImage(source: ImageSource, rs: RectScale, opts: TextureOptions) (Backend.TextureError || StbImageError)!void {
    _ = source;
    _ = rs;
    _ = opts;
    return;
}

test {
    @import("std").testing.refAllDecls(@This());
}
