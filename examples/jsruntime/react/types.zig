const std = @import("std");
const dvui = @import("dvui");

pub const ReactWidth = union(enum) {
    full,
    pixels: f32,
};

pub const ReactCommandStyle = struct {
    background: ?dvui.Color = null,
    text: ?dvui.Color = null,
    width: ?ReactWidth = null,
};

pub const ReactFlexProps = struct {
    direction: ?[]const u8 = null,
    justify_content: ?[]const u8 = null,
    align_items: ?[]const u8 = null,
    align_content: ?[]const u8 = null,
};

pub const ReactCommand = struct {
    command_type: []const u8,
    text: ?[]const u8 = null,
    text_content: ?[]const u8 = null,
    children: []const []const u8 = &.{},
    on_click_id: ?[]const u8 = null,
    style: ReactCommandStyle = .{},
    flex: ?ReactFlexProps = null,
    image_src: ?[]const u8 = null,
};

pub const ReactCommandMap = std.StringHashMap(ReactCommand);

pub const CommandType = enum {
    box,
    div,
    FlexBox,
    p,
    h1,
    h2,
    h3,
    button,
    image,
    @"text-content",
};
