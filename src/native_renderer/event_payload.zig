const std = @import("std");

const luaz = @import("luaz");
const retained = @import("retained");

pub fn pointerPayloadTable(lua: *luaz.Lua, detail: []const u8) !luaz.Lua.Table {
    const payload = pointerPayload(detail);

    const modifiers_table = lua.createTable(.{ .rec = 4 });
    defer modifiers_table.deinit();

    try modifiers_table.set("shift", (payload.modifiers & 1) != 0);
    try modifiers_table.set("ctrl", (payload.modifiers & 2) != 0);
    try modifiers_table.set("alt", (payload.modifiers & 4) != 0);
    try modifiers_table.set("cmd", (payload.modifiers & 8) != 0);

    const payload_table = lua.createTable(.{ .rec = 4 });

    try payload_table.set("x", payload.x);
    try payload_table.set("y", payload.y);
    try payload_table.set("button", payload.button);
    try payload_table.set("modifiers", modifiers_table);

    return payload_table;
}

fn pointerPayload(detail: []const u8) retained.events.PointerPayload {
    const expected_len: usize = @sizeOf(retained.events.PointerPayload);
    if (detail.len < expected_len) {
        return .{
            .x = 0,
            .y = 0,
            .button = 255,
            .modifiers = 0,
        };
    }

    const bytes_ptr: *const [expected_len]u8 = @ptrCast(detail.ptr);
    return std.mem.bytesToValue(retained.events.PointerPayload, bytes_ptr);
}

