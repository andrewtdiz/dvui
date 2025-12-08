const std = @import("std");

const dvui = @import("dvui");
const FontId = dvui.Font.FontId;
var layout_flex_content_justify = dvui.FlexBoxWidget.ContentPosition.start;
var layout_flex_align_items = dvui.FlexBoxWidget.AlignItems.start;
const RaylibBackend = @import("raylib-backend");
comptime {
    std.debug.assert(@hasDecl(RaylibBackend, "RaylibBackend"));
}
const ray = RaylibBackend.raylib;
const raygui = RaylibBackend.raygui;

var last_mouse: dvui.Point.Natural = .{ .x = 0, .y = 0 };
var has_mouse = false;
var mouse_down = false;

pub fn main() !void {
    if (@import("builtin").os.tag == .windows) { // optional
        dvui.Backend.Common.windowsAttachConsole() catch {};
    }
    RaylibBackend.enableRaylibLogging();
    var gpa_instance = std.heap.GeneralPurposeAllocator(.{}){};
    const gpa = gpa_instance.allocator();

    defer _ = gpa_instance.deinit();

    // create OS window directly with raylib
    ray.setConfigFlags(ray.ConfigFlags{
        .window_resizable = true,
        .vsync_hint = true,
    });
    ray.initWindow(1400, 900, "DVUI Raylib Ontop Example");
    defer ray.closeWindow();

    var backend = RaylibBackend.init(gpa);
    defer backend.deinit();
    backend.log_events = true;

    var win = try dvui.Window.init(@src(), gpa, backend.backend(), .{});
    win.theme = dvui.Theme.builtin.shadcn;
    defer win.deinit();

    while (!ray.windowShouldClose()) {
        ray.beginDrawing();

        try win.begin(std.time.nanoTimestamp());

        try backend.addAllEvents(&win);
        trackMousePosition();

        if (backend.shouldBlockRaylibInput()) {
            raygui.lock();
        } else {
            raygui.unlock();
        }
        ray.clearBackground(RaylibBackend.dvuiColorToRaylib(dvui.Color.black));

        // Absolute positioned demo box centered in the window.
        {
            const anchor = blk: {
                if (mouse_down and has_mouse) {
                    break :blk last_mouse;
                }
                const wr = dvui.windowRect();
                break :blk dvui.Point.Natural{
                    .x = wr.x + wr.w * 0.5,
                    .y = wr.y + wr.h * 0.5,
                };
            };
            const box_size = dvui.Size{ .w = 260, .h = 140 };
            const box_rect = dvui.Rect{
                .x = anchor.x - box_size.w * 0.5,
                .y = anchor.y - box_size.h * 0.5,
                .w = box_size.w,
                .h = box_size.h,
            };

            var center_box = dvui.box(@src(), .{ .dir = .vertical }, .{
                .rect = box_rect,
                .padding = dvui.Rect.all(12),
                .min_size_content = box_size,
                .background = true,
                .border = dvui.Rect.all(1),
                .corner_radius = dvui.Rect.all(8),
            });
            defer center_box.deinit();

            dvui.label(@src(), "Centered Box", .{}, .{ .gravity_x = 0.5 });
            _ = dvui.spacer(@src(), .{ .min_size_content = dvui.Size{ .w = 0, .h = 12 } });
            dvui.label(@src(), "Anchored in the middle of the window.", .{}, .{ .gravity_x = 0.5 });
            _ = dvui.spacer(@src(), .{ .min_size_content = dvui.Size{ .w = 0, .h = 8 } });
            _ = dvui.button(@src(), "Action", .{}, .{ .gravity_x = 0.5 });
        }

        _ = try win.end(.{});

        if (win.cursorRequestedFloating()) |cursor| {
            backend.setCursor(cursor);
        } else {
            backend.setCursor(win.cursorRequested());
        }

        ray.endDrawing();
    }
}

fn trackMousePosition() void {
    for (dvui.events()) |*evt| {
        switch (evt.evt) {
            .mouse => |mouse| switch (mouse.action) {
                .press => {
                    mouse_down = true;
                    last_mouse = mouse.p.toNatural();
                    has_mouse = true;
                },
                .release => {
                    mouse_down = false;
                },
                .position, .motion => {
                    last_mouse = mouse.p.toNatural();
                    has_mouse = true;
                },
                else => {},
            },
            else => {},
        }
    }
}
