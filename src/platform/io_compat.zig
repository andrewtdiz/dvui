const std = @import("std");
const mem = std.mem;
const math = std.math;

/// Provides a small compatibility layer mimicking the old `std.io.fixedBufferStream`
/// reader API while delegating to the modern `std.Io.Reader`.
pub const FixedSliceReader = struct {
    interface: std.Io.Reader,

    pub const Error = std.Io.Reader.Error;

    pub fn init(buffer: []const u8) FixedSliceReader {
        return .{ .interface = std.Io.Reader.fixed(buffer) };
    }

    fn iface(self: *const FixedSliceReader) *std.Io.Reader {
        return @constCast(&self.interface);
    }

    pub fn readAll(self: *const FixedSliceReader, dest: []u8) Error!usize {
        return std.Io.Reader.readSliceShort(self.iface(), dest);
    }

    pub fn readNoEof(self: *const FixedSliceReader, dest: []u8) Error!void {
        try std.Io.Reader.readSliceAll(self.iface(), dest);
    }

    pub fn readByte(self: *const FixedSliceReader) Error!u8 {
        return std.Io.Reader.takeByte(self.iface());
    }

    pub fn readInt(self: *const FixedSliceReader, comptime T: type, endian: std.builtin.Endian) Error!T {
        return std.Io.Reader.takeInt(self.iface(), T, endian);
    }

    pub fn readSliceShort(self: *const FixedSliceReader, dest: []u8) Error!usize {
        return std.Io.Reader.readSliceShort(self.iface(), dest);
    }

    pub fn readSliceAll(self: *const FixedSliceReader, dest: []u8) Error!void {
        try std.Io.Reader.readSliceAll(self.iface(), dest);
    }

    pub fn takeByte(self: *const FixedSliceReader) Error!u8 {
        return std.Io.Reader.takeByte(self.iface());
    }

    pub fn takeInt(self: *const FixedSliceReader, comptime T: type, endian: std.builtin.Endian) Error!T {
        return std.Io.Reader.takeInt(self.iface(), T, endian);
    }
};

pub const SkipOptions = struct {
    allow_end_of_stream: bool = false,
};

pub fn FixedBufferStream(comptime Buffer: type) type {
    const info = @typeInfo(Buffer);
    const pointer_info = switch (info) {
        .pointer => |ptr| ptr,
        else => @compileError("FixedBufferStream expects a slice type"),
    };
    comptime {
        if (pointer_info.size != .slice)
            @compileError("FixedBufferStream expects a slice type");
        if (pointer_info.child != u8)
            @compileError("FixedBufferStream currently only supports slices of u8");
    }

    const is_const_buffer = pointer_info.is_const;

    return struct {
        buffer: Buffer,
        pos: usize = 0,

        pub const ReadError = error{EndOfStream};
        pub const WriteError = error{NoSpaceLeft};
        pub const SeekError = error{};
        pub const GetSeekPosError = error{};

        pub const Reader = struct {
            stream: *Self,

            pub const Error = ReadError;

            pub fn readNoEof(self: *Reader, dest: []u8) ReadError!void {
                const slice = try self.stream.readSlice(dest.len);
                @memcpy(dest, slice);
            }

            pub fn readInt(self: *Reader, comptime T: type, endian: std.builtin.Endian) ReadError!T {
                const bytes = try self.stream.readSlice(@sizeOf(T));
                return mem.readInt(T, bytes, endian);
            }

            pub fn readByte(self: *Reader) ReadError!u8 {
                const slice = try self.stream.readSlice(1);
                return slice[0];
            }

            pub fn readByteSigned(self: *Reader) ReadError!i8 {
                const slice = try self.stream.readSlice(1);
                return mem.readInt(i8, slice, .big);
            }

            pub fn skipBytes(self: *Reader, len: usize, options: SkipOptions) ReadError!void {
                try self.stream.skip(len, options);
            }

            pub fn readSliceAll(self: *Reader, dest: []u8) ReadError!void {
                try self.readNoEof(dest);
            }

            pub fn readSliceShort(self: *Reader, dest: []u8) ReadError!usize {
                return self.stream.read(dest);
            }

            pub fn takeByte(self: *Reader) ReadError!u8 {
                return self.readByte();
            }

            pub fn takeInt(self: *Reader, comptime T: type, endian: std.builtin.Endian) ReadError!T {
                return self.readInt(T, endian);
            }
        };

        pub const Writer = struct {
            stream: *Self,

            pub const Error = WriteError;

            pub fn write(self: *Writer, bytes: []const u8) WriteError!usize {
                return self.stream.write(bytes);
            }

            pub fn writeAll(self: *Writer, bytes: []const u8) WriteError!void {
                var index: usize = 0;
                while (index < bytes.len) {
                    const written = try self.stream.write(bytes[index..]);
                    index += written;
                }
            }
        };

        const Self = @This();

        pub fn reader(self: *Self) Reader {
            return .{ .stream = self };
        }

        pub fn writer(self: *Self) Writer {
            if (comptime is_const_buffer) {
                @compileError("Cannot create writer for const FixedBufferStream");
            }
            return .{ .stream = self };
        }

        pub fn read(self: *Self, dest: []u8) ReadError!usize {
            const avail = self.available();
            const size = @min(dest.len, avail.len);
            const slice = try self.readSlice(size);
            @memcpy(dest[0..size], slice);
            return size;
        }

        fn readSlice(self: *Self, len: usize) ReadError![]const u8 {
            const remaining = self.buffer[self.pos..];
            if (len > remaining.len) return error.EndOfStream;
            const slice = remaining[0..len];
            self.pos += len;
            return slice;
        }

        fn skip(self: *Self, len: usize, options: SkipOptions) ReadError!void {
            const remaining = self.buffer.len - self.pos;
            if (len > remaining) {
                if (options.allow_end_of_stream) {
                    self.pos = self.buffer.len;
                    return;
                }
                return error.EndOfStream;
            }
            self.pos += len;
        }

        pub fn write(self: *Self, bytes: []const u8) WriteError!usize {
            if (bytes.len == 0) return 0;
            if (comptime is_const_buffer)
                @compileError("Cannot write to const FixedBufferStream");
            if (self.pos >= self.buffer.len) return error.NoSpaceLeft;

            const remaining = self.buffer.len - self.pos;
            const n = @min(remaining, bytes.len);
            @memcpy(self.buffer[self.pos .. self.pos + n], bytes[0..n]);
            self.pos += n;
            if (n == 0) return error.NoSpaceLeft;
            return n;
        }

        pub fn reset(self: *Self) void {
            self.pos = 0;
        }

        pub fn getWritten(self: Self) Buffer {
            return self.buffer[0..self.pos];
        }

        pub fn getPos(self: *Self) GetSeekPosError!u64 {
            return self.pos;
        }

        pub fn getEndPos(self: *Self) GetSeekPosError!u64 {
            return self.buffer.len;
        }

        pub fn seekTo(self: *Self, pos: u64) SeekError!void {
            const new_pos = math.cast(usize, pos) orelse math.maxInt(usize);
            self.pos = @min(self.buffer.len, new_pos);
        }

        pub fn seekBy(self: *Self, amt: i64) SeekError!void {
            if (amt < 0) {
                const abs_amt = math.cast(usize, @abs(amt)) orelse math.maxInt(usize);
                if (abs_amt > self.pos) {
                    self.pos = 0;
                } else {
                    self.pos -= abs_amt;
                }
            } else {
                const amt_usize = math.cast(usize, amt) orelse math.maxInt(usize);
                const new_pos = math.add(usize, self.pos, amt_usize) catch math.maxInt(usize);
                self.pos = @min(self.buffer.len, new_pos);
            }
        }

        fn available(self: *Self) []const u8 {
            return self.buffer[self.pos..];
        }
    };
}

pub fn fixedBufferStream(buffer: anytype) FixedBufferStream(Slice(@TypeOf(buffer))) {
    return .{ .buffer = sliceFrom(buffer), .pos = 0 };
}

fn Slice(comptime T: type) type {
    return switch (@typeInfo(T)) {
        .pointer => |ptr_info| blk: {
            var new_ptr_info = ptr_info;
            switch (ptr_info.size) {
                .slice => break :blk T,
                .one => switch (@typeInfo(ptr_info.child)) {
                    .array => |array_info| new_ptr_info.child = array_info.child,
                    else => @compileError("invalid type given to fixedBufferStream"),
                },
                else => @compileError("invalid type given to fixedBufferStream"),
            }
            new_ptr_info.size = .slice;
            break :blk @Type(.{ .pointer = new_ptr_info });
        },
        else => @compileError("invalid type given to fixedBufferStream"),
    };
}

fn sliceFrom(buffer: anytype) Slice(@TypeOf(buffer)) {
    return switch (@typeInfo(@TypeOf(buffer))) {
        .pointer => |ptr_info| switch (ptr_info.size) {
            .slice => buffer,
            .one => switch (@typeInfo(ptr_info.child)) {
                .array => |arr| buffer[0..arr.len],
                else => @compileError("invalid type given to fixedBufferStream"),
            },
            else => @compileError("invalid type given to fixedBufferStream"),
        },
        else => @compileError("invalid type given to fixedBufferStream"),
    };
}
