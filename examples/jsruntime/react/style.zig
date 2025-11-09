const dvui = @import("dvui");
const types = @import("types.zig");

const Options = dvui.Options;

pub fn applyCommandStyle(style: types.ReactCommandStyle, options: *Options) void {
    if (style.background) |color| {
        options.color_fill = color;
        options.background = true;
    }
    if (style.text) |color| {
        options.color_text = color;
    }
    applyWidthStyle(style.width, options);
}

fn applyWidthStyle(width: ?types.ReactWidth, options: *Options) void {
    const spec = width orelse return;
    switch (spec) {
        .full => applyFullWidth(options),
        .pixels => |px| {
            var min_size = options.min_size_content orelse dvui.Size{};
            min_size.w = px;
            options.min_size_content = min_size;

            var max_size = options.max_size_content orelse Options.MaxSize{
                .w = dvui.max_float_safe,
                .h = dvui.max_float_safe,
            };
            max_size.w = px;
            options.max_size_content = max_size;
        },
    }
}

fn applyFullWidth(options: *Options) void {
    if (options.expand) |exp| {
        options.expand = switch (exp) {
            .none => .horizontal,
            .vertical => .both,
            .horizontal => .horizontal,
            .both => .both,
            .ratio => .ratio,
        };
        return;
    }
    options.expand = .horizontal;
}

pub fn colorFromPacked(value: u32) dvui.Color {
    const r: u8 = @intCast((value >> 24) & 0xff);
    const g: u8 = @intCast((value >> 16) & 0xff);
    const b: u8 = @intCast((value >> 8) & 0xff);
    const a: u8 = @intCast(value & 0xff);
    return dvui.Color{ .r = r, .g = g, .b = b, .a = a };
}
