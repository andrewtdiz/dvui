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
    const canonical = try resolveImagePath(src);
    var keep_path = false;
    defer if (!keep_path) image_allocator.free(canonical);

    if (image_cache.getPtr(canonical)) |existing| {
        return existing;
    }

    const bytes = try readImageFile(canonical);
    errdefer image_allocator.free(bytes);

    const gop = try image_cache.getOrPut(canonical);
    if (gop.found_existing) {
        image_allocator.free(bytes);
        return gop.value_ptr;
    }

    keep_path = true;
    gop.key_ptr.* = canonical;
    gop.value_ptr.* = .{
        .path = canonical,
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

fn resolveImagePath(source: []const u8) ![]u8 {
    if (source.len == 0) {
        return error.MissingImageSource;
    }
    if (std.fs.path.isAbsolute(source)) {
        return std.fs.realpathAlloc(image_allocator, source) catch {
            return error.ImageNotFound;
        };
    }

    for (image_search_roots) |root| {
        const candidate = try buildCandidatePath(root, source);
        defer image_allocator.free(candidate);

        const resolved = std.fs.cwd().realpathAlloc(image_allocator, candidate) catch {
            continue;
        };
        return resolved;
    }

    return error.ImageNotFound;
}

fn buildCandidatePath(base: []const u8, rel: []const u8) ![]u8 {
    if (base.len == 0) {
        return image_allocator.dupe(u8, rel);
    }
    return std.fs.path.join(image_allocator, &.{ base, rel });
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
