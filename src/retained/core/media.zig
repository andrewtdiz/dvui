const image_loader = @import("../render/image_loader.zig");

pub const IconKind = enum {
    auto,
    svg,
    tvg,
    image,
    glyph,
};

pub const CachedImage = union(enum) {
    none,
    failed,
    resource: *const image_loader.ImageResource,
};

pub const CachedIcon = union(enum) {
    none,
    failed,
    vector: []const u8,
    raster: *const image_loader.ImageResource,
    glyph: []const u8,
};
