const std = @import("std");

/// Event types that can be dispatched from Zig to JS
pub const EventKind = enum(u8) {
    click = 0,
    input = 1,
    focus = 2,
    blur = 3,
    mouseenter = 4,
    mouseleave = 5,
    keydown = 6,
    keyup = 7,
    change = 8,
    submit = 9,
};

/// Packed event entry for efficient memory layout
pub const EventEntry = extern struct {
    kind: EventKind,
    _pad: u8 = 0,
    node_id: u32,
    detail_offset: u32,
    detail_len: u16,
    _pad2: u16 = 0,
};

/// Ring buffer for events that JS will poll after each frame
pub const EventRing = struct {
    allocator: std.mem.Allocator,
    buffer: []EventEntry,
    detail_buffer: []u8,
    read_head: u32 = 0,
    write_head: u32 = 0,
    detail_write: u32 = 0,
    capacity: u32,
    detail_capacity: u32,
    header_cache: Header = .{ .read_head = 0, .write_head = 0, .capacity = 0, .detail_capacity = 0 },

    const DEFAULT_CAPACITY: u32 = 256;
    const DEFAULT_DETAIL_CAPACITY: u32 = 4096;

    pub fn init(allocator: std.mem.Allocator) !EventRing {
        return initWithCapacity(allocator, DEFAULT_CAPACITY, DEFAULT_DETAIL_CAPACITY);
    }

    pub fn initWithCapacity(
        allocator: std.mem.Allocator,
        event_capacity: u32,
        detail_capacity: u32,
    ) !EventRing {
        const buffer = try allocator.alloc(EventEntry, event_capacity);
        errdefer allocator.free(buffer);
        const detail_buffer = try allocator.alloc(u8, detail_capacity);
        return .{
            .allocator = allocator,
            .buffer = buffer,
            .detail_buffer = detail_buffer,
            .capacity = event_capacity,
            .detail_capacity = detail_capacity,
        };
    }

    pub fn deinit(self: *EventRing) void {
        self.allocator.free(self.buffer);
        self.allocator.free(self.detail_buffer);
    }

    /// Push an event to the ring buffer. Returns false if buffer is full.
    pub fn push(self: *EventRing, kind: EventKind, node_id: u32, detail: ?[]const u8) bool {
        // Check if buffer is full
        if (self.write_head - self.read_head >= self.capacity) {
            return false;
        }

        const idx = self.write_head % self.capacity;

        var entry = EventEntry{
            .kind = kind,
            .node_id = node_id,
            .detail_offset = 0,
            .detail_len = 0,
        };

        // Write detail string if provided and there's space
        if (detail) |d| {
            if (self.detail_write + d.len <= self.detail_capacity) {
                @memcpy(self.detail_buffer[self.detail_write..][0..d.len], d);
                entry.detail_offset = self.detail_write;
                entry.detail_len = @intCast(d.len);
                self.detail_write += @intCast(d.len);
            }
        }

        self.buffer[idx] = entry;
        self.write_head += 1;
        return true;
    }

    /// Push a click event
    pub fn pushClick(self: *EventRing, node_id: u32) bool {
        return self.push(.click, node_id, null);
    }

    /// Push an input event with the current input value
    pub fn pushInput(self: *EventRing, node_id: u32, value: []const u8) bool {
        return self.push(.input, node_id, value);
    }

    /// Push a focus event
    pub fn pushFocus(self: *EventRing, node_id: u32) bool {
        return self.push(.focus, node_id, null);
    }

    /// Push a blur event
    pub fn pushBlur(self: *EventRing, node_id: u32) bool {
        return self.push(.blur, node_id, null);
    }

    /// Get number of pending events
    pub fn pendingCount(self: *const EventRing) u32 {
        return self.write_head - self.read_head;
    }

    /// Check if there are pending events
    pub fn hasPending(self: *const EventRing) bool {
        return self.write_head != self.read_head;
    }

    /// Reset after JS has consumed all events
    pub fn reset(self: *EventRing) void {
        self.read_head = self.write_head;
        self.detail_write = 0;
    }

    /// Get raw pointers for FFI access
    pub fn getBufferPtr(self: *EventRing) [*]EventEntry {
        return self.buffer.ptr;
    }

    pub fn getDetailPtr(self: *EventRing) [*]u8 {
        return self.detail_buffer.ptr;
    }

    /// Get header info for JS to read
    pub const Header = extern struct {
        read_head: u32,
        write_head: u32,
        capacity: u32,
        detail_capacity: u32,
    };

    pub fn getHeader(self: *const EventRing) Header {
        return .{
            .read_head = self.read_head,
            .write_head = self.write_head,
            .capacity = self.capacity,
            .detail_capacity = self.detail_capacity,
        };
    }

    pub fn snapshotHeader(self: *EventRing) *Header {
        self.header_cache = self.getHeader();
        return &self.header_cache;
    }

    /// Update read head after JS has consumed events
    pub fn setReadHead(self: *EventRing, new_read_head: u32) void {
        self.read_head = new_read_head;
        // Reset detail buffer when all events consumed
        if (self.read_head == self.write_head) {
            self.detail_write = 0;
        }
    }
};

/// Map event name string to EventKind
pub fn eventKindFromName(name: []const u8) ?EventKind {
    const map = std.StaticStringMap(EventKind).initComptime(.{
        .{ "click", .click },
        .{ "input", .input },
        .{ "focus", .focus },
        .{ "blur", .blur },
        .{ "mouseenter", .mouseenter },
        .{ "mouseleave", .mouseleave },
        .{ "keydown", .keydown },
        .{ "keyup", .keyup },
        .{ "change", .change },
        .{ "submit", .submit },
    });
    return map.get(name);
}

test "EventRing basic operations" {
    var ring = try EventRing.init(std.testing.allocator);
    defer ring.deinit();

    try std.testing.expect(!ring.hasPending());
    try std.testing.expect(ring.pushClick(42));
    try std.testing.expect(ring.hasPending());
    try std.testing.expectEqual(@as(u32, 1), ring.pendingCount());

    ring.reset();
    try std.testing.expect(!ring.hasPending());
}

test "EventRing with detail" {
    var ring = try EventRing.init(std.testing.allocator);
    defer ring.deinit();

    const detail = "hello world";
    try std.testing.expect(ring.pushInput(123, detail));

    const entry = ring.buffer[0];
    try std.testing.expectEqual(EventKind.input, entry.kind);
    try std.testing.expectEqual(@as(u32, 123), entry.node_id);
    try std.testing.expectEqual(@as(u16, detail.len), entry.detail_len);

    const stored = ring.detail_buffer[entry.detail_offset..][0..entry.detail_len];
    try std.testing.expectEqualStrings(detail, stored);
}
