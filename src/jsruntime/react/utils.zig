const std = @import("std");
const dvui = @import("dvui");

const types = @import("types.zig");
const style = @import("style.zig");

const Options = dvui.Options;

pub fn initContainerOptions(entry: types.ReactCommand) Options {
    var opts = Options{
        .name = entry.command_type,
        .background = false,
        .padding = .{ .x = 8, .y = 8, .w = 8, .h = 8 },
    };
    style.applyCommandStyle(entry.style, &opts);
    return opts;
}

pub fn resolveCommandText(nodes: anytype, child_ids: []const []const u8) []const u8 {
    for (child_ids) |child_id| {
        const child = nodes.get(child_id) orelse continue;
        if (!std.mem.eql(u8, child.command_type, "text-content")) continue;
        if (child.text) |text| {
            return text;
        }
    }
    return "";
}

pub fn nodeIdExtra(node_id: []const u8) usize {
    const hash: u64 = std.hash.Wyhash.hash(0, node_id);
    return @intCast(hash & std.math.maxInt(usize));
}

pub fn buildFlexInitOptions(entry: types.ReactCommand) dvui.FlexBoxWidget.InitOptions {
    var init_opts = dvui.FlexBoxWidget.InitOptions{
        .justify_content = .start,
    };

    if (entry.flex) |flex| {
        if (flex.direction) |dir| {
            init_opts.direction = stringToDirection(dir);
        }
        if (flex.justify_content) |value| {
            init_opts.justify_content = stringToContentPosition(value);
        }
        if (flex.align_items) |value| {
            init_opts.align_items = stringToAlignItems(value);
        }
        if (flex.align_content) |value| {
            init_opts.align_content = stringToAlignContent(value);
        }
    }

    return init_opts;
}

pub fn colorFromPacked(value: u32) dvui.Color {
    const r: u8 = @intCast((value >> 24) & 0xff);
    const g: u8 = @intCast((value >> 16) & 0xff);
    const b: u8 = @intCast((value >> 8) & 0xff);
    const a: u8 = @intCast(value & 0xff);
    return dvui.Color{ .r = r, .g = g, .b = b, .a = a };
}

fn stringToDirection(value: []const u8) dvui.enums.Direction {
    if (std.mem.eql(u8, value, "column")) return .vertical;
    return .horizontal;
}

fn stringToContentPosition(value: []const u8) dvui.FlexBoxWidget.ContentPosition {
    if (std.mem.eql(u8, value, "center")) return .center;
    if (std.mem.eql(u8, value, "end") or std.mem.eql(u8, value, "flex-end")) return .end;
    if (std.mem.eql(u8, value, "space-between") or std.mem.eql(u8, value, "between")) return .between;
    if (std.mem.eql(u8, value, "space-around") or std.mem.eql(u8, value, "around")) return .around;
    return .start;
}

fn stringToAlignItems(value: []const u8) dvui.FlexBoxWidget.AlignItems {
    if (std.mem.eql(u8, value, "center")) return .center;
    if (std.mem.eql(u8, value, "end") or std.mem.eql(u8, value, "flex-end")) return .end;
    return .start;
}

fn stringToAlignContent(value: []const u8) dvui.FlexBoxWidget.AlignContent {
    if (std.mem.eql(u8, value, "center")) return .center;
    if (std.mem.eql(u8, value, "end") or std.mem.eql(u8, value, "flex-end")) return .end;
    return .start;
}
