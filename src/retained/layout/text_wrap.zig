const std = @import("std");
const dvui = @import("dvui");

pub const LineRange = struct {
    start: usize,
    len: usize,
    width: f32,
};

pub const LineLayout = struct {
    lines: std.ArrayList(LineRange) = .empty,
    text_hash: u64 = 0,
    font_id: u64 = 0,
    font_size_key: u64 = 0,
    width_key: u64 = 0,
    scale_key: u64 = 0,
    wrap: bool = true,
    break_words: bool = false,
    line_height: f32 = 0,
    height: f32 = 0,
    max_line_width: f32 = 0,

    pub fn deinit(self: *LineLayout, allocator: std.mem.Allocator) void {
        self.lines.deinit(allocator);
    }
};

pub fn computeLineBreaks(
    allocator: std.mem.Allocator,
    layout: *LineLayout,
    text: []const u8,
    font: dvui.Font,
    max_width: f32,
    scale: f32,
    wrap: bool,
    break_words: bool,
) void {
    const text_hash = hashText(text);
    const font_id = @intFromEnum(font.id);
    const font_size_key: u64 = @intFromFloat(font.size * 100.0);
    const width_key: u64 = if (max_width > 0) @intFromFloat(max_width * 100.0) else 0;
    const scale_key: u64 = if (scale > 0) @intFromFloat(scale * 100.0) else 0;

    if (layout.text_hash == text_hash and layout.font_id == font_id and layout.font_size_key == font_size_key and layout.width_key == width_key and layout.scale_key == scale_key and layout.wrap == wrap and layout.break_words == break_words) return;

    layout.lines.items.len = 0;
    layout.text_hash = text_hash;
    layout.font_id = font_id;
    layout.font_size_key = font_size_key;
    layout.width_key = width_key;
    layout.scale_key = scale_key;
    layout.wrap = wrap;
    layout.break_words = break_words;
    layout.line_height = font.lineHeight() * scale;
    layout.height = 0;
    layout.max_line_width = 0;

    if (text.len == 0) return;

    if (!wrap or max_width <= 0) {
        splitLinesNoWrap(allocator, layout, text, font, scale);
        updateHeights(layout, font, scale);
        return;
    }

    const max_width_logical = if (scale != 0) max_width / scale else max_width;
    splitLinesWrap(allocator, layout, text, font, max_width_logical, scale, break_words);
    updateHeights(layout, font, scale);
}

fn splitLinesNoWrap(
    allocator: std.mem.Allocator,
    layout: *LineLayout,
    text: []const u8,
    font: dvui.Font,
    scale: f32,
) void {
    var pos: usize = 0;
    while (pos < text.len) {
        if (isLineBreakByte(text[pos])) {
            appendLine(allocator, layout, text, pos, 0, font, scale);
            pos = consumeLineBreak(text, pos);
            continue;
        }

        var start = pos;
        while (start < text.len and isSpaceByte(text[start])) {
            start += 1;
        }
        if (start >= text.len) break;
        if (isLineBreakByte(text[start])) {
            pos = start;
            continue;
        }

        var end = start;
        while (end < text.len and !isLineBreakByte(text[end])) {
            end += 1;
        }
        var line_end = end;
        while (line_end > start and isSpaceByte(text[line_end - 1])) {
            line_end -= 1;
        }

        appendLine(allocator, layout, text, start, line_end - start, font, scale);
        pos = if (end < text.len) consumeLineBreak(text, end) else end;
    }
}

fn splitLinesWrap(
    allocator: std.mem.Allocator,
    layout: *LineLayout,
    text: []const u8,
    font: dvui.Font,
    max_width: f32,
    scale: f32,
    break_words: bool,
) void {
    var pos: usize = 0;
    while (pos < text.len) {
        while (pos < text.len and isSpaceByte(text[pos])) {
            pos += 1;
        }
        if (pos >= text.len) break;
        if (isLineBreakByte(text[pos])) {
            appendLine(allocator, layout, text, pos, 0, font, scale);
            pos = consumeLineBreak(text, pos);
            continue;
        }

        var end_idx: usize = 0;
        _ = font.textSizeEx(text[pos..], .{ .max_width = max_width, .end_idx = &end_idx });
        if (end_idx == 0) {
            end_idx = nextCodepointLen(text[pos..]);
        }
        if (end_idx == 0) break;

        const slice = text[pos .. pos + end_idx];
        if (findLineBreak(slice)) |line_break| {
            var line_end = line_break;
            while (line_end > 0 and isSpaceByte(slice[line_end - 1])) {
                line_end -= 1;
            }
            appendLine(allocator, layout, text, pos, line_end, font, scale);
            pos = consumeLineBreak(text, pos + line_break);
            continue;
        }
        if (pos + end_idx >= text.len) {
            var line_len = end_idx;
            while (line_len > 0 and isSpaceByte(slice[line_len - 1])) {
                line_len -= 1;
            }
            appendLine(allocator, layout, text, pos, line_len, font, scale);
            pos = pos + end_idx;
            continue;
        }

        var last_space: ?usize = null;
        var scan_idx: usize = 0;
        while (scan_idx < slice.len) : (scan_idx += 1) {
            if (isSpaceByte(slice[scan_idx])) {
                last_space = scan_idx;
            }
        }

        var next_pos: usize = 0;
        var line_len: usize = 0;
        if (last_space) |space_idx| {
            line_len = space_idx;
            next_pos = pos + space_idx + 1;
        } else if (break_words) {
            line_len = end_idx;
            next_pos = pos + end_idx;
        } else {
            var extended = pos + end_idx;
            while (extended < text.len and !isSpaceByte(text[extended]) and !isLineBreakByte(text[extended])) {
                extended += 1;
            }
            if (extended == pos) {
                extended = pos + nextCodepointLen(text[pos..]);
            }
            line_len = extended - pos;
            next_pos = extended;
        }

        while (line_len > 0 and isSpaceByte(text[pos + line_len - 1])) {
            line_len -= 1;
        }

        appendLine(allocator, layout, text, pos, line_len, font, scale);
        if (next_pos <= pos) {
            next_pos = pos + nextCodepointLen(text[pos..]);
        }
        if (next_pos < text.len and isLineBreakByte(text[next_pos])) {
            next_pos = consumeLineBreak(text, next_pos);
        }
        pos = next_pos;
    }
}

fn updateHeights(layout: *LineLayout, font: dvui.Font, scale: f32) void {
    const line_count = layout.lines.items.len;
    if (line_count == 0) return;
    const base_height = @max(font.textHeight(), font.lineHeight()) * scale;
    layout.height = base_height + @as(f32, @floatFromInt(line_count - 1)) * layout.line_height;
}

fn appendLine(
    allocator: std.mem.Allocator,
    layout: *LineLayout,
    text: []const u8,
    start: usize,
    len: usize,
    font: dvui.Font,
    scale: f32,
) void {
    const slice = if (len > 0) text[start .. start + len] else text[0..0];
    const size = font.textSize(slice);
    const width = size.w * scale;
    layout.lines.append(allocator, .{
        .start = start,
        .len = len,
        .width = width,
    }) catch {};
    if (width > layout.max_line_width) layout.max_line_width = width;
}

fn findLineBreak(text: []const u8) ?usize {
    var idx: usize = 0;
    while (idx < text.len) : (idx += 1) {
        if (isLineBreakByte(text[idx])) return idx;
    }
    return null;
}

fn consumeLineBreak(text: []const u8, pos: usize) usize {
    if (pos >= text.len) return pos;
    var next = pos + 1;
    if (text[pos] == '\r' and next < text.len and text[next] == '\n') {
        next += 1;
    }
    return next;
}

fn isSpaceByte(byte: u8) bool {
    return byte == ' ' or byte == '\t';
}

fn isLineBreakByte(byte: u8) bool {
    return byte == '\n' or byte == '\r';
}

fn nextCodepointLen(text: []const u8) usize {
    if (text.len == 0) return 0;
    const len = std.unicode.utf8ByteSequenceLength(text[0]) catch return 1;
    return if (len <= text.len) len else text.len;
}

fn hashText(text: []const u8) u64 {
    var hasher = std.hash.Wyhash.init(0);
    hasher.update(text);
    return hasher.final();
}
