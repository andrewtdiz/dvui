const std = @import("std");

const ui_json = @import("ui_json.zig");
const types = @import("../core/types.zig");
const events = @import("../events/mod.zig");

fn tokenHasValue(class_name: []const u8, prefix: []const u8, value: []const u8) bool {
    var it = std.mem.tokenizeAny(u8, class_name, " \t\r\n");
    while (it.next()) |token| {
        if (token.len != prefix.len + value.len) continue;
        if (!std.mem.startsWith(u8, token, prefix)) continue;
        if (std.mem.eql(u8, token[prefix.len..], value)) return true;
    }
    return false;
}

fn hasToken(class_name: []const u8, token: []const u8) bool {
    var it = std.mem.tokenizeAny(u8, class_name, " \t\r\n");
    while (it.next()) |t| {
        if (std.mem.eql(u8, t, token)) return true;
    }
    return false;
}

fn extractBracketNumber(class_name: []const u8, prefix: []const u8) ?f32 {
    var it = std.mem.tokenizeAny(u8, class_name, " \t\r\n");
    while (it.next()) |token| {
        if (!std.mem.startsWith(u8, token, prefix)) continue;
        if (token.len <= prefix.len + 1) continue;
        if (token[token.len - 1] != ']') continue;
        var inner = token[prefix.len .. token.len - 1];
        if (std.mem.endsWith(u8, inner, "px")) {
            if (inner.len <= 2) return null;
            inner = inner[0 .. inner.len - 2];
        }
        const value = std.fmt.parseFloat(f32, inner) catch return null;
        return value;
    }
    return null;
}

fn findNodeByPath(store: *types.NodeStore, path: []const u8) u32 {
    var it = store.nodes.iterator();
    while (it.next()) |entry| {
        const node = entry.value_ptr;
        if (tokenHasValue(node.className(), "ui-path-", path)) {
            return entry.key_ptr.*;
        }
    }
    return 0;
}

test "ui_json loader builds retained store from Clay ui.json" {
    const bytes = @embedFile("../../../../../game/scene-debug/ui.json");

    var parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, bytes, .{
        .ignore_unknown_fields = true,
        .allocate = .alloc_always,
    });
    defer parsed.deinit();

    var store: types.NodeStore = undefined;
    try store.init(std.testing.allocator);
    defer store.deinit();

    var ring = try events.EventRing.init(std.testing.allocator);
    defer ring.deinit();

    try std.testing.expect(ring.pushClick(123));
    try std.testing.expectEqual(@as(u32, 1), ring.pendingCount());

    const ok = ui_json.setSnapshotFromUiJsonValue(&store, &ring, parsed.value, 800, 600);
    try std.testing.expect(ok);
    try std.testing.expectEqual(@as(u32, 0), ring.pendingCount());

    try std.testing.expectEqual(@as(usize, 6), store.nodes.count());

    const hud_id = findNodeByPath(&store, "Hud");
    const title_id = findNodeByPath(&store, "Hud.Title");
    const logo_id = findNodeByPath(&store, "Hud.Logo");
    const input_id = findNodeByPath(&store, "Hud.NameInput");

    try std.testing.expect(hud_id != 0);
    try std.testing.expect(title_id != 0);
    try std.testing.expect(logo_id != 0);
    try std.testing.expect(input_id != 0);

    const hud = store.node(hud_id).?;
    const title = store.node(title_id).?;
    const logo = store.node(logo_id).?;
    const input = store.node(input_id).?;

    try std.testing.expectEqual(@as(?u32, 0), hud.parent);
    try std.testing.expectEqual(@as(?u32, hud_id), title.parent);
    try std.testing.expectEqual(@as(?u32, hud_id), logo.parent);
    try std.testing.expectEqual(@as(?u32, hud_id), input.parent);

    try std.testing.expect(tokenHasValue(title.className(), "ui-key-", "Title"));
    try std.testing.expect(tokenHasValue(title.className(), "ui-path-", "Hud.Title"));
    try std.testing.expect(hasToken(title.className(), "absolute"));
    try std.testing.expect(hasToken(title.className(), "text-xl"));

    const title_left = extractBracketNumber(title.className(), "left-[") orelse return error.TestUnexpectedResult;
    const title_top = extractBracketNumber(title.className(), "top-[") orelse return error.TestUnexpectedResult;
    const title_w = extractBracketNumber(title.className(), "w-[") orelse return error.TestUnexpectedResult;
    const title_h = extractBracketNumber(title.className(), "h-[") orelse return error.TestUnexpectedResult;
    try std.testing.expectApproxEqAbs(@as(f32, 35), title_left, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 26), title_top, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 288), title_w, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 31), title_h, 0.001);

    const text_id: u32 = 0x80000000 | title_id;
    const text_node = store.node(text_id) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(types.NodeKind.text, text_node.kind);
    try std.testing.expectEqual(@as(?u32, title_id), text_node.parent);
    try std.testing.expectEqualStrings("This is a test", text_node.text);
}

