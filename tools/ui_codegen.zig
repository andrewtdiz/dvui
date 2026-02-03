const std = @import("std");

const Allocator = std.mem.Allocator;

const CodegenError = Allocator.Error || error{
    InvalidArgs,
    InvalidSchema,
    MissingTag,
    MissingRoot,
    InvalidKey,
    DuplicateKey,
    KeyMismatch,
    UnknownField,
};

const Child = union(enum) {
    primitive: std.json.Value,
    node: *Node,
};

const Node = struct {
    tag: []const u8,
    key: ?[]const u8,
    class: ?[]const u8,
    props: ?std.json.Value,
    scale: ?std.json.Value,
    children: []Child,
};

const Link = struct {
    parent_key: []const u8,
    child_key: []const u8,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const gpa_allocator = gpa.allocator();

    var arena = std.heap.ArenaAllocator.init(gpa_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const args = try std.process.argsAlloc(gpa_allocator);
    defer std.process.argsFree(gpa_allocator, args);

    if (args.len != 3) {
        std.debug.print("usage: {s} <input_json_path> <output_luau_path>\n", .{args[0]});
        return error.InvalidArgs;
    }

    const input_path = args[1];
    const output_path = args[2];

    const input_bytes = try std.fs.cwd().readFileAlloc(gpa_allocator, input_path, 1024 * 1024 * 8);
    defer gpa_allocator.free(input_bytes);

    const parsed = try std.json.parseFromSlice(std.json.Value, gpa_allocator, input_bytes, .{ .allocate = .alloc_always });
    defer parsed.deinit();

    var key_set: std.StringHashMapUnmanaged(void) = .empty;
    defer key_set.deinit(allocator);

    var keys: std.ArrayList([]const u8) = .empty;
    defer keys.deinit(allocator);

    var links: std.ArrayList(Link) = .empty;
    defer links.deinit(allocator);

    const root = try parseRoot(parsed.value, allocator, &key_set, &keys, &links);

    if (keys.items.len > 1) {
        std.sort.pdq([]const u8, keys.items, {}, lessThanString);
    }
    if (links.items.len > 1) {
        std.sort.pdq(Link, links.items, {}, lessThanLink);
    }

    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(gpa_allocator);

    try emitModule(allocator, out.writer(gpa_allocator), root, keys.items, links.items);

    if (std.fs.path.dirname(output_path)) |dir| {
        try std.fs.cwd().makePath(dir);
    }

    var out_file = try std.fs.cwd().createFile(output_path, .{ .truncate = true });
    defer out_file.close();
    try out_file.writeAll(out.items);
}

fn lessThanString(_: void, a: []const u8, b: []const u8) bool {
    return std.mem.lessThan(u8, a, b);
}

fn lessThanLink(_: void, a: Link, b: Link) bool {
    if (std.mem.eql(u8, a.parent_key, b.parent_key)) {
        return std.mem.lessThan(u8, a.child_key, b.child_key);
    }
    return std.mem.lessThan(u8, a.parent_key, b.parent_key);
}

fn isLuauIdent(name: []const u8) bool {
    if (name.len == 0) return false;
    if (!isIdentStart(name[0])) return false;
    for (name[1..]) |c| {
        if (!isIdentContinue(c)) return false;
    }
    return !isKeyword(name);
}

fn isIdentStart(c: u8) bool {
    return (c >= 'A' and c <= 'Z') or (c >= 'a' and c <= 'z') or c == '_';
}

fn isIdentContinue(c: u8) bool {
    return isIdentStart(c) or (c >= '0' and c <= '9');
}

fn isKeyword(name: []const u8) bool {
    const keywords = [_][]const u8{
        "and",
        "break",
        "do",
        "else",
        "elseif",
        "end",
        "false",
        "for",
        "function",
        "if",
        "in",
        "local",
        "nil",
        "not",
        "or",
        "repeat",
        "return",
        "then",
        "true",
        "until",
        "while",
    };

    for (keywords) |kw| {
        if (std.mem.eql(u8, name, kw)) return true;
    }
    return false;
}

fn isReservedKey(name: []const u8) bool {
    const reserved = [_][]const u8{
        "__kind",
        "children",
        "class",
        "key",
        "props",
        "scale",
        "tag",
        "onBlur",
        "onClick",
        "onEnter",
        "onFocus",
        "onInput",
        "onMouseDown",
        "onMouseEnter",
        "onMouseLeave",
        "onMouseUp",
    };

    for (reserved) |r| {
        if (std.mem.eql(u8, name, r)) return true;
    }
    return false;
}

fn validateKey(name: []const u8) CodegenError!void {
    if (!isLuauIdent(name)) return error.InvalidKey;
    if (isReservedKey(name)) return error.InvalidKey;
}

fn parseRoot(
    value: std.json.Value,
    allocator: Allocator,
    key_set: *std.StringHashMapUnmanaged(void),
    keys: *std.ArrayList([]const u8),
    links: *std.ArrayList(Link),
) CodegenError!*Node {
    if (value != .object) return error.InvalidSchema;
    const obj = value.object;

    if (obj.get("tag") != null) {
        const node = try parseNodeSpec(value, allocator, key_set, keys, links, "root");
        if (node.key == null) return error.MissingRoot;
        return node;
    }

    if (obj.count() != 1) return error.InvalidSchema;
    var it = obj.iterator();
    const entry = it.next() orelse return error.InvalidSchema;
    const root_key = entry.key_ptr.*;
    try validateKey(root_key);
    return parseNodeSpec(entry.value_ptr.*, allocator, key_set, keys, links, root_key);
}

fn parseChild(
    value: std.json.Value,
    allocator: Allocator,
    key_set: *std.StringHashMapUnmanaged(void),
    keys: *std.ArrayList([]const u8),
    links: *std.ArrayList(Link),
    parent_key: ?[]const u8,
) CodegenError!?Child {
    switch (value) {
        .null => return null,
        .string, .integer, .float, .number_string, .bool => return Child{ .primitive = value },
        .object => |obj| {
            if (obj.get("tag") != null) {
                const node = try parseNodeSpec(value, allocator, key_set, keys, links, null);
                return Child{ .node = node };
            }

            if (obj.count() != 1) return error.InvalidSchema;
            var it = obj.iterator();
            const entry = it.next() orelse return error.InvalidSchema;
            const child_key = entry.key_ptr.*;
            try validateKey(child_key);

            const node = try parseNodeSpec(entry.value_ptr.*, allocator, key_set, keys, links, child_key);
            if (parent_key) |pk| {
                try links.append(allocator, .{ .parent_key = pk, .child_key = child_key });
            }
            return Child{ .node = node };
        },
        else => return error.InvalidSchema,
    }
}

fn parseNodeSpec(
    value: std.json.Value,
    allocator: Allocator,
    key_set: *std.StringHashMapUnmanaged(void),
    keys: *std.ArrayList([]const u8),
    links: *std.ArrayList(Link),
    forced_key: ?[]const u8,
) CodegenError!*Node {
    if (value != .object) return error.InvalidSchema;
    const obj = value.object;

    const tag_value = obj.get("tag") orelse return error.MissingTag;
    if (tag_value != .string) return error.InvalidSchema;

    var node_key: ?[]const u8 = forced_key;
    if (obj.get("key")) |key_value| {
        if (key_value != .string) return error.InvalidSchema;
        const k = key_value.string;
        if (forced_key) |fk| {
            if (!std.mem.eql(u8, k, fk)) return error.KeyMismatch;
        }
        node_key = k;
    }

    if (node_key) |k| {
        try validateKey(k);
        if (key_set.contains(k)) return error.DuplicateKey;
        try key_set.putNoClobber(allocator, k, {});
        try keys.append(allocator, k);
    }

    var class_value: ?[]const u8 = null;
    if (obj.get("class")) |v| {
        if (v != .string) return error.InvalidSchema;
        class_value = v.string;
    }

    var props_value: ?std.json.Value = null;
    if (obj.get("props")) |v| {
        if (v != .object) return error.InvalidSchema;
        props_value = v;
    }

    var scale_value: ?std.json.Value = null;
    if (obj.get("scale")) |v| {
        switch (v) {
            .integer, .float, .number_string => {},
            else => return error.InvalidSchema,
        }
        scale_value = v;
    }

    var children_list: std.ArrayList(Child) = .empty;
    defer children_list.deinit(allocator);

    if (obj.get("children")) |children_value| {
        if (children_value != .array) return error.InvalidSchema;
        const pk = node_key;
        for (children_value.array.items) |child_value| {
            if (try parseChild(child_value, allocator, key_set, keys, links, pk)) |child| {
                try children_list.append(allocator, child);
            }
        }
    }

    var it = obj.iterator();
    while (it.next()) |entry| {
        const k = entry.key_ptr.*;
        if (std.mem.eql(u8, k, "tag")) continue;
        if (std.mem.eql(u8, k, "key")) continue;
        if (std.mem.eql(u8, k, "class")) continue;
        if (std.mem.eql(u8, k, "props")) continue;
        if (std.mem.eql(u8, k, "scale")) continue;
        if (std.mem.eql(u8, k, "children")) continue;
        return error.UnknownField;
    }

    const node_ptr = try allocator.create(Node);
    node_ptr.* = .{
        .tag = tag_value.string,
        .key = node_key,
        .class = class_value,
        .props = props_value,
        .scale = scale_value,
        .children = try children_list.toOwnedSlice(allocator),
    };
    return node_ptr;
}

fn emitModule(
    allocator: Allocator,
    writer: anytype,
    root: *Node,
    keys: []const []const u8,
    links: []const Link,
) CodegenError!void {
    try writer.writeAll("local Types = require(\"luau/ui/types\")\n\n");
    try emitKeyType(writer, keys);
    try writer.writeAll("\n");
    try writer.writeAll("export type Patches = { [Key]: Types.NodePatch }\n\n");

    try writer.writeAll("local function create(): Types.UINode\n");

    var emitted: std.StringHashMapUnmanaged(void) = .empty;
    defer emitted.deinit(allocator);

    try emitNodeDecls(allocator, writer, root, &emitted, 1);

    for (links) |link| {
        try emitIndent(writer, 1);
        try emitNodeVar(writer, link.parent_key);
        try writer.writeAll(".");
        try writer.writeAll(link.child_key);
        try writer.writeAll(" = ");
        try emitNodeVar(writer, link.child_key);
        try writer.writeAll("\n");
    }

    try emitIndent(writer, 1);
    try writer.writeAll("return ");
    const root_key = root.key orelse return error.MissingRoot;
    try emitNodeVar(writer, root_key);
    try writer.writeAll("\nend\n\n");

    try writer.writeAll("return {\n");
    try writer.writeAll("  create = create,\n");
    try writer.writeAll("}\n");
}

fn emitNodeDecls(
    allocator: Allocator,
    writer: anytype,
    node: *Node,
    emitted: *std.StringHashMapUnmanaged(void),
    indent: usize,
) CodegenError!void {
    for (node.children) |child| {
        switch (child) {
            .node => |child_node| try emitNodeDecls(allocator, writer, child_node, emitted, indent),
            else => {},
        }
    }

    const key = node.key orelse return;
    if (emitted.contains(key)) return;
    try emitted.putNoClobber(allocator, key, {});

    try emitIndent(writer, indent);
    try writer.writeAll("local ");
    try emitNodeVar(writer, key);
    try writer.writeAll(" = ");
    try emitNodeLua(allocator, writer, node, indent + 1);
    try writer.writeAll("\n\n");
}

fn emitKeyType(writer: anytype, keys: []const []const u8) CodegenError!void {
    if (keys.len == 0) {
        try writer.writeAll("export type Key = string\n");
        return;
    }

    try writer.writeAll("export type Key = ");
    var first = true;
    for (keys) |k| {
        if (!first) {
            try writer.writeAll(" | ");
        }
        first = false;
        try emitLuaString(writer, k);
    }
    try writer.writeAll("\n");
}

fn emitNodeVar(writer: anytype, key: []const u8) CodegenError!void {
    try writer.writeAll("node_");
    try writer.writeAll(key);
}

fn emitNodeLua(allocator: Allocator, writer: anytype, node: *Node, indent: usize) CodegenError!void {
    try writer.writeAll("{\n");

    try emitIndent(writer, indent);
    try writer.writeAll("tag = ");
    try emitLuaString(writer, node.tag);
    try writer.writeAll(",\n");

    if (node.key) |k| {
        try emitIndent(writer, indent);
        try writer.writeAll("key = ");
        try emitLuaString(writer, k);
        try writer.writeAll(",\n");
    }

    if (node.class) |c| {
        try emitIndent(writer, indent);
        try writer.writeAll("class = ");
        try emitLuaString(writer, c);
        try writer.writeAll(",\n");
    }

    if (node.props) |p| {
        try emitIndent(writer, indent);
        try writer.writeAll("props = ");
        try emitJsonToLua(allocator, writer, p, indent);
        try writer.writeAll(",\n");
    }

    if (node.scale) |s| {
        try emitIndent(writer, indent);
        try writer.writeAll("scale = ");
        try emitJsonToLua(allocator, writer, s, indent);
        try writer.writeAll(",\n");
    }

    if (node.children.len > 0) {
        try emitIndent(writer, indent);
        try writer.writeAll("children = ");
        try emitChildrenLua(allocator, writer, node.children, indent);
        try writer.writeAll(",\n");
    }

    try emitIndent(writer, indent - 1);
    try writer.writeAll("}");
}

fn emitChildrenLua(allocator: Allocator, writer: anytype, children: []const Child, indent: usize) CodegenError!void {
    try writer.writeAll("{\n");
    for (children) |child| {
        try emitIndent(writer, indent + 1);
        switch (child) {
            .primitive => |v| try emitJsonToLua(allocator, writer, v, indent + 2),
            .node => |n| {
                if (n.key) |k| {
                    try emitNodeVar(writer, k);
                } else {
                    try emitNodeLua(allocator, writer, n, indent + 2);
                }
            },
        }
        try writer.writeAll(",\n");
    }
    try emitIndent(writer, indent);
    try writer.writeAll("}");
}

fn emitJsonToLua(allocator: Allocator, writer: anytype, value: std.json.Value, indent: usize) CodegenError!void {
    switch (value) {
        .null => try writer.writeAll("nil"),
        .bool => |b| try writer.writeAll(if (b) "true" else "false"),
        .integer => |i| try writer.print("{d}", .{i}),
        .float => |f| try writer.print("{d}", .{f}),
        .number_string => |s| try writer.writeAll(s),
        .string => |s| try emitLuaString(writer, s),
        .array => |arr| try emitArrayLua(allocator, writer, arr.items, indent),
        .object => |obj| try emitObjectLua(allocator, writer, obj, indent),
    }
}

fn emitArrayLua(allocator: Allocator, writer: anytype, items: []const std.json.Value, indent: usize) CodegenError!void {
    if (items.len == 0) {
        try writer.writeAll("{}");
        return;
    }

    try writer.writeAll("{\n");
    for (items) |item| {
        try emitIndent(writer, indent + 1);
        try emitJsonToLua(allocator, writer, item, indent + 1);
        try writer.writeAll(",\n");
    }
    try emitIndent(writer, indent);
    try writer.writeAll("}");
}

fn emitObjectLua(allocator: Allocator, writer: anytype, obj: std.json.ObjectMap, indent: usize) CodegenError!void {
    if (obj.count() == 0) {
        try writer.writeAll("{}");
        return;
    }

    const key_list = try allocator.alloc([]const u8, obj.count());
    defer allocator.free(key_list);

    var i: usize = 0;
    var it = obj.iterator();
    while (it.next()) |entry| {
        key_list[i] = entry.key_ptr.*;
        i += 1;
    }
    if (key_list.len > 1) {
        std.sort.pdq([]const u8, key_list, {}, lessThanString);
    }

    try writer.writeAll("{\n");
    for (key_list) |k| {
        try emitIndent(writer, indent + 1);
        if (isLuauIdent(k)) {
            try writer.writeAll(k);
        } else {
            try writer.writeAll("[");
            try emitLuaString(writer, k);
            try writer.writeAll("]");
        }
        try writer.writeAll(" = ");
        const v = obj.get(k) orelse return error.InvalidSchema;
        try emitJsonToLua(allocator, writer, v, indent + 1);
        try writer.writeAll(",\n");
    }
    try emitIndent(writer, indent);
    try writer.writeAll("}");
}

fn emitIndent(writer: anytype, n: usize) CodegenError!void {
    for (0..n) |_| {
        try writer.writeAll("  ");
    }
}

fn emitLuaString(writer: anytype, s: []const u8) CodegenError!void {
    try writer.writeByte('"');
    for (s) |c| {
        switch (c) {
            '\\' => try writer.writeAll("\\\\"),
            '"' => try writer.writeAll("\\\""),
            '\n' => try writer.writeAll("\\n"),
            '\r' => try writer.writeAll("\\r"),
            '\t' => try writer.writeAll("\\t"),
            else => {
                if (c < 0x20) {
                    try writer.print("\\{d:0>3}", .{c});
                } else {
                    try writer.writeByte(c);
                }
            },
        }
    }
    try writer.writeByte('"');
}
