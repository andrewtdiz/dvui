const std = @import("std");
const dvui = @import("dvui");
const types = @import("../core/types.zig");
const image_loader = @import("image_loader.zig");

const icon_allocator = std.heap.c_allocator;

pub const IconError = error{
    MissingIconSource,
    IconNotFound,
    IconTooLarge,
    InvalidIconSource,
};

pub const ResolvedIcon = union(enum) {
    vector: []const u8,
    raster: *const image_loader.ImageResource,
    glyph: []const u8,
};

const VectorEntry = struct {
    svg_bytes: []u8 = &.{},
    tvg_bytes: []u8 = &.{},
};

const IconEntry = struct {
    kind: types.IconKind = .auto,
    vector: ?VectorEntry = null,
    raster_path: []u8 = &.{},
    glyph: []u8 = &.{},
};

const IconCache = std.StringHashMap(IconEntry);
var icon_cache = IconCache.init(icon_allocator);

const max_icon_bytes: usize = 16 * 1024 * 1024;
const icon_search_roots = [_][]const u8{
    "examples/resources/assets",
    "examples/resources/js/assets",
    "examples/resources/js",
    "examples",
    "src",
    "",
};

pub fn init() void {
    icon_cache = IconCache.init(icon_allocator);
}

pub fn deinit() void {
    clearCache();
    icon_cache.deinit();
    icon_cache = IconCache.init(icon_allocator);
}

pub fn registerVectorBytes(name: []const u8, bytes: []const u8, format: types.IconKind) !void {
    if (format != .svg and format != .tvg) return error.InvalidIconSource;
    const copy = try icon_allocator.dupe(u8, bytes);
    var vector = VectorEntry{};
    if (format == .svg) {
        vector.svg_bytes = copy;
    } else {
        vector.tvg_bytes = copy;
    }
    try upsertEntry(name, .{ .kind = format, .vector = vector });
}

pub fn registerVectorPath(name: []const u8, path: []const u8, format: types.IconKind) !void {
    if (format != .svg and format != .tvg and format != .auto) return error.InvalidIconSource;
    const canonical = try resolveIconPath(path);
    defer icon_allocator.free(canonical);
    const bytes = try readIconFile(canonical);
    const resolved_kind = if (format == .auto) detectVectorKind(canonical) else format;
    var vector = VectorEntry{};
    if (resolved_kind == .svg) {
        vector.svg_bytes = bytes;
    } else {
        vector.tvg_bytes = bytes;
    }
    try upsertEntry(name, .{ .kind = resolved_kind, .vector = vector });
}

pub fn registerRasterPath(name: []const u8, path: []const u8) !void {
    const copy = try icon_allocator.dupe(u8, path);
    try upsertEntry(name, .{ .kind = .image, .raster_path = copy });
}

pub fn registerGlyph(name: []const u8, glyph: []const u8) !void {
    const copy = try icon_allocator.dupe(u8, glyph);
    try upsertEntry(name, .{ .kind = .glyph, .glyph = copy });
}

pub fn hasEntry(name: []const u8) bool {
    return icon_cache.getPtr(name) != null;
}

pub fn resolve(kind: types.IconKind, src: []const u8, glyph: []const u8) !ResolvedIcon {
    if (kind == .glyph or glyph.len > 0) {
        const resolved_glyph = try resolveGlyph(src, glyph);
        return .{ .glyph = resolved_glyph };
    }

    if (kind == .auto and src.len > 0) {
        if (icon_cache.getPtr(src)) |entry| {
            return resolveFromEntry(entry);
        }
    }

    const resolved_kind = if (kind == .auto) detectIconKind(src) else kind;
    switch (resolved_kind) {
        .svg, .tvg => {
            const bytes = try resolveVector(resolved_kind, src);
            return .{ .vector = bytes };
        },
        .image => {
            const resource = try resolveRaster(src);
            return .{ .raster = resource };
        },
        .glyph => {
            const resolved_glyph = try resolveGlyph(src, glyph);
            return .{ .glyph = resolved_glyph };
        },
        else => return error.InvalidIconSource,
    }
}

pub fn resolveWithPath(kind: types.IconKind, src: []const u8, glyph: []const u8, resolved_path: []const u8) !ResolvedIcon {
    if (kind == .glyph or glyph.len > 0) {
        const resolved_glyph = try resolveGlyph(src, glyph);
        return .{ .glyph = resolved_glyph };
    }

    if (kind == .auto and src.len > 0) {
        if (icon_cache.getPtr(src)) |entry| {
            return resolveFromEntry(entry);
        }
    }

    const kind_source = if (resolved_path.len > 0) resolved_path else src;
    const resolved_kind = if (kind == .auto) detectIconKind(kind_source) else kind;
    switch (resolved_kind) {
        .svg, .tvg => {
            const bytes = try resolveVectorWithPath(resolved_kind, src, resolved_path);
            return .{ .vector = bytes };
        },
        .image => {
            const resource = try resolveRasterWithPath(src, resolved_path);
            return .{ .raster = resource };
        },
        .glyph => {
            const resolved_glyph = try resolveGlyph(src, glyph);
            return .{ .glyph = resolved_glyph };
        },
        else => return error.InvalidIconSource,
    }
}

fn resolveFromEntry(entry: *IconEntry) !ResolvedIcon {
    switch (entry.kind) {
        .svg, .tvg => {
            const bytes = try ensureVectorBytes(entry);
            return .{ .vector = bytes };
        },
        .image => {
            if (entry.raster_path.len == 0) return error.MissingIconSource;
            const resource = try image_loader.load(entry.raster_path);
            return .{ .raster = resource };
        },
        .glyph => {
            if (entry.glyph.len == 0) return error.MissingIconSource;
            return .{ .glyph = entry.glyph };
        },
        else => return error.InvalidIconSource,
    }
}

fn resolveVector(kind: types.IconKind, src: []const u8) ![]const u8 {
    if (src.len == 0) return error.MissingIconSource;

    if (icon_cache.getPtr(src)) |entry| {
        if (entry.kind != .svg and entry.kind != .tvg) return error.InvalidIconSource;
        return ensureVectorBytes(entry);
    }

    const canonical = try resolveIconPath(src);
    var keep_path = false;
    defer if (!keep_path) icon_allocator.free(canonical);

    if (icon_cache.getPtr(canonical)) |entry| {
        if (entry.kind != .svg and entry.kind != .tvg) return error.InvalidIconSource;
        return ensureVectorBytes(entry);
    }

    const bytes = try readIconFile(canonical);
    const resolved_kind = if (kind == .auto) detectVectorKind(canonical) else kind;
    if (resolved_kind != .svg and resolved_kind != .tvg) {
        icon_allocator.free(bytes);
        return error.InvalidIconSource;
    }

    var vector = VectorEntry{};
    if (resolved_kind == .svg) {
        vector.svg_bytes = bytes;
    } else {
        vector.tvg_bytes = bytes;
    }

    const gop = try icon_cache.getOrPut(canonical);
    if (gop.found_existing) {
        icon_allocator.free(bytes);
        return ensureVectorBytes(gop.value_ptr);
    }

    keep_path = true;
    gop.key_ptr.* = canonical;
    gop.value_ptr.* = .{ .kind = resolved_kind, .vector = vector };
    return ensureVectorBytes(gop.value_ptr);
}

fn resolveVectorWithPath(kind: types.IconKind, src: []const u8, resolved_path: []const u8) ![]const u8 {
    if (resolved_path.len > 0) {
        return resolveVectorFromPath(kind, resolved_path);
    }
    return resolveVector(kind, src);
}

fn resolveVectorFromPath(kind: types.IconKind, path: []const u8) ![]const u8 {
    if (path.len == 0) return error.MissingIconSource;

    if (icon_cache.getPtr(path)) |entry| {
        if (entry.kind != .svg and entry.kind != .tvg) return error.InvalidIconSource;
        return ensureVectorBytes(entry);
    }

    const bytes = try readIconFile(path);
    const resolved_kind = if (kind == .auto) detectVectorKind(path) else kind;
    if (resolved_kind != .svg and resolved_kind != .tvg) {
        icon_allocator.free(bytes);
        return error.InvalidIconSource;
    }

    var vector = VectorEntry{};
    if (resolved_kind == .svg) {
        vector.svg_bytes = bytes;
    } else {
        vector.tvg_bytes = bytes;
    }

    const key = try icon_allocator.dupe(u8, path);
    errdefer icon_allocator.free(key);

    const gop = try icon_cache.getOrPut(key);
    if (gop.found_existing) {
        icon_allocator.free(key);
        icon_allocator.free(bytes);
        return ensureVectorBytes(gop.value_ptr);
    }

    gop.key_ptr.* = key;
    gop.value_ptr.* = .{ .kind = resolved_kind, .vector = vector };
    return ensureVectorBytes(gop.value_ptr);
}

fn resolveRasterWithPath(src: []const u8, resolved_path: []const u8) !*const image_loader.ImageResource {
    if (resolved_path.len > 0) {
        return resolveRasterFromPath(resolved_path);
    }
    return resolveRaster(src);
}

fn resolveRasterFromPath(path: []const u8) !*const image_loader.ImageResource {
    if (path.len == 0) return error.MissingIconSource;
    return image_loader.loadResolved(path);
}

fn resolveRaster(src: []const u8) !*const image_loader.ImageResource {
    if (src.len == 0) return error.MissingIconSource;
    if (icon_cache.getPtr(src)) |entry| {
        if (entry.kind == .image and entry.raster_path.len > 0) {
            return try image_loader.load(entry.raster_path);
        }
    }
    return image_loader.load(src);
}

fn resolveGlyph(src: []const u8, glyph: []const u8) ![]const u8 {
    if (glyph.len > 0) return glyph;
    if (src.len == 0) return error.MissingIconSource;
    if (icon_cache.getPtr(src)) |entry| {
        if (entry.kind == .glyph and entry.glyph.len > 0) {
            return entry.glyph;
        }
    }
    return src;
}

fn detectIconKind(src: []const u8) types.IconKind {
    if (src.len == 0) return .image;
    if (isSvgPath(src)) return .svg;
    if (isTvgPath(src)) return .tvg;
    return .image;
}

fn detectVectorKind(path: []const u8) types.IconKind {
    if (isSvgPath(path)) return .svg;
    return .tvg;
}

fn isSvgPath(path: []const u8) bool {
    return std.mem.eql(u8, std.fs.path.extension(path), ".svg");
}

fn isTvgPath(path: []const u8) bool {
    return std.mem.eql(u8, std.fs.path.extension(path), ".tvg");
}

fn ensureVectorBytes(entry: *IconEntry) ![]const u8 {
    const vector_ptr = if (entry.vector) |*vector| vector else return error.MissingIconSource;
    if (vector_ptr.tvg_bytes.len > 0) return vector_ptr.tvg_bytes;
    if (vector_ptr.svg_bytes.len == 0) return error.MissingIconSource;
    const tvg_bytes = try dvui.svgToTvg(icon_allocator, vector_ptr.svg_bytes);
    icon_allocator.free(vector_ptr.svg_bytes);
    vector_ptr.svg_bytes = &.{};
    vector_ptr.tvg_bytes = @constCast(tvg_bytes);
    return vector_ptr.tvg_bytes;
}

fn upsertEntry(name: []const u8, entry: IconEntry) !void {
    const owned_name = try icon_allocator.dupe(u8, name);
    errdefer icon_allocator.free(owned_name);

    const gop = try icon_cache.getOrPut(owned_name);
    if (gop.found_existing) {
        icon_allocator.free(owned_name);
        freeEntry(gop.value_ptr.*);
    } else {
        gop.key_ptr.* = owned_name;
    }
    gop.value_ptr.* = entry;
}

fn clearCache() void {
    var iter = icon_cache.iterator();
    while (iter.next()) |entry| {
        icon_allocator.free(entry.key_ptr.*);
        freeEntry(entry.value_ptr.*);
    }
}

fn freeEntry(entry: IconEntry) void {
    if (entry.vector) |vector| {
        if (vector.svg_bytes.len > 0) icon_allocator.free(vector.svg_bytes);
        if (vector.tvg_bytes.len > 0) icon_allocator.free(vector.tvg_bytes);
    }
    if (entry.raster_path.len > 0) icon_allocator.free(entry.raster_path);
    if (entry.glyph.len > 0) icon_allocator.free(entry.glyph);
}

pub fn resolveIconPathAlloc(allocator: std.mem.Allocator, source: []const u8) ![]u8 {
    if (source.len == 0) return error.MissingIconSource;
    if (std.fs.path.isAbsolute(source)) {
        return std.fs.realpathAlloc(allocator, source) catch {
            return error.IconNotFound;
        };
    }

    for (icon_search_roots) |root| {
        const candidate = try buildCandidatePathAlloc(allocator, root, source);
        defer allocator.free(candidate);

        const resolved = std.fs.cwd().realpathAlloc(allocator, candidate) catch {
            continue;
        };
        return resolved;
    }

    return error.IconNotFound;
}

fn resolveIconPath(source: []const u8) ![]u8 {
    return resolveIconPathAlloc(icon_allocator, source);
}

fn buildCandidatePathAlloc(allocator: std.mem.Allocator, base: []const u8, rel: []const u8) ![]u8 {
    if (base.len == 0) {
        return allocator.dupe(u8, rel);
    }
    return std.fs.path.join(allocator, &.{ base, rel });
}

fn readIconFile(path: []const u8) ![]u8 {
    const file = try std.fs.openFileAbsolute(path, .{ .mode = .read_only });
    defer file.close();

    var reader_buffer: [4096]u8 = undefined;
    var reader = file.reader(reader_buffer[0..]);
    return reader.interface.allocRemaining(icon_allocator, std.Io.Limit.limited(max_icon_bytes)) catch |err| switch (err) {
        error.StreamTooLong => return error.IconTooLarge,
        else => return err,
    };
}
