const std = @import("std");
const dvui = @import("dvui");

const image_allocator = std.heap.c_allocator;

pub const ImageResource = struct {
    path: []const u8,
    bytes: []u8,
};

const ImageCache = std.StringHashMap(ImageResource);
var image_cache = ImageCache.init(image_allocator);

pub fn init() void {
    image_cache = ImageCache.init(image_allocator);
}

pub fn deinit() void {
    clearCache();
    image_cache.deinit();
    image_cache = ImageCache.init(image_allocator);
}

fn clearCache() void {
    var iter = image_cache.iterator();
    while (iter.next()) |entry| {
        image_allocator.free(entry.key_ptr.*);
        image_allocator.free(entry.value_ptr.bytes);
    }
}

pub const ImageError = error{
    MissingImageSource,
    ImageNotFound,
    ImageTooLarge,
};

const max_image_bytes: usize = 16 * 1024 * 1024;
const image_search_roots = [_][]const u8{
    "examples/resources/assets",
    "examples/resources/js/assets",
    "examples/resources/js",
    "examples",
    "src",
    "",
};

pub fn load(src: []const u8) !*const ImageResource {
    const canonical = try resolveImagePathAlloc(image_allocator, src);
    defer image_allocator.free(canonical);
    return loadResolved(canonical);
}

pub fn loadResolved(path: []const u8) !*const ImageResource {
    if (path.len == 0) {
        return error.MissingImageSource;
    }
    if (image_cache.getPtr(path)) |existing| {
        return existing;
    }

    const bytes = try readImageFile(path);
    errdefer image_allocator.free(bytes);

    const key = try image_allocator.dupe(u8, path);
    errdefer image_allocator.free(key);

    const gop = try image_cache.getOrPut(key);
    if (gop.found_existing) {
        image_allocator.free(key);
        image_allocator.free(bytes);
        return gop.value_ptr;
    }

    gop.key_ptr.* = key;
    gop.value_ptr.* = .{
        .path = key,
        .bytes = bytes,
    };
    return gop.value_ptr;
}

pub fn imageSource(resource: *const ImageResource) dvui.ImageSource {
    return dvui.ImageSource{
        .imageFile = .{
            .bytes = resource.bytes,
            .name = resource.path,
        },
    };
}

pub fn resolveImagePathAlloc(allocator: std.mem.Allocator, source: []const u8) ![]u8 {
    if (source.len == 0) {
        return error.MissingImageSource;
    }
    if (std.fs.path.isAbsolute(source)) {
        return std.fs.realpathAlloc(allocator, source) catch {
            return error.ImageNotFound;
        };
    }

    for (image_search_roots) |root| {
        const candidate = try buildCandidatePathAlloc(allocator, root, source);
        defer allocator.free(candidate);

        const resolved = std.fs.cwd().realpathAlloc(allocator, candidate) catch {
            continue;
        };
        return resolved;
    }

    return error.ImageNotFound;
}

fn resolveImagePath(source: []const u8) ![]u8 {
    return resolveImagePathAlloc(image_allocator, source);
}

fn buildCandidatePathAlloc(allocator: std.mem.Allocator, base: []const u8, rel: []const u8) ![]u8 {
    if (base.len == 0) {
        return allocator.dupe(u8, rel);
    }
    return std.fs.path.join(allocator, &.{ base, rel });
}

fn readImageFile(path: []const u8) ![]u8 {
    const file = try std.fs.openFileAbsolute(path, .{ .mode = .read_only });
    defer file.close();

    var reader_buffer: [4096]u8 = undefined;
    var reader = file.reader(reader_buffer[0..]);
    return reader.interface.allocRemaining(image_allocator, std.Io.Limit.limited(max_image_bytes)) catch |err| switch (err) {
        error.StreamTooLong => return error.ImageTooLarge,
        else => return err,
    };
}
