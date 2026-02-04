const std = @import("std");
const retained = @import("retained");

pub const FrameProfiler = struct {
    frame_log_last_ns: i128 = 0,
    frame_log_accum_ns: i128 = 0,
    frame_log_frames: u32 = 0,
    phase_log_accum_ns: i128 = 0,
    phase_log_frames: u32 = 0,
    phase_frame_ns: i128 = 0,
    phase_input_ns: i128 = 0,
    phase_lua_events_ns: i128 = 0,
    phase_lua_update_ns: i128 = 0,
    phase_retained_ns: i128 = 0,
    phase_commands_ns: i128 = 0,
    phase_present_ns: i128 = 0,
    phase_retained_layout_ns: i128 = 0,
    phase_retained_hover_ns: i128 = 0,
    phase_retained_hit_test_ns: i128 = 0,
    phase_retained_render_ns: i128 = 0,
    phase_retained_focus_ns: i128 = 0,
    phase_retained_draw_bg_ns: i128 = 0,
    phase_retained_draw_text_ns: i128 = 0,
    phase_retained_draw_image_ns: i128 = 0,
    phase_retained_draw_icon_ns: i128 = 0,
};

pub fn mark() i128 {
    return std.time.nanoTimestamp();
}

pub fn addInput(profiler: *FrameProfiler, start_ns: i128) void {
    profiler.phase_input_ns += std.time.nanoTimestamp() - start_ns;
}

pub fn addLuaEvents(profiler: *FrameProfiler, start_ns: i128) void {
    profiler.phase_lua_events_ns += std.time.nanoTimestamp() - start_ns;
}

pub fn addLuaUpdate(profiler: *FrameProfiler, start_ns: i128) void {
    profiler.phase_lua_update_ns += std.time.nanoTimestamp() - start_ns;
}

pub fn addCommands(profiler: *FrameProfiler, start_ns: i128) void {
    profiler.phase_commands_ns += std.time.nanoTimestamp() - start_ns;
}

pub fn addPresent(profiler: *FrameProfiler, start_ns: i128) void {
    profiler.phase_present_ns += std.time.nanoTimestamp() - start_ns;
}

pub fn addRetained(profiler: *FrameProfiler, start_ns: i128, timings: retained.FrameTimings) void {
    const end_ns = std.time.nanoTimestamp();
    profiler.phase_retained_ns += end_ns - start_ns;
    profiler.phase_retained_layout_ns += timings.layout_ns;
    profiler.phase_retained_hover_ns += timings.hover_ns;
    profiler.phase_retained_hit_test_ns += timings.hit_test_ns;
    profiler.phase_retained_render_ns += timings.render_ns;
    profiler.phase_retained_focus_ns += timings.focus_ns;
    profiler.phase_retained_draw_bg_ns += timings.draw_bg_ns;
    profiler.phase_retained_draw_text_ns += timings.draw_text_ns;
    profiler.phase_retained_draw_image_ns += timings.draw_image_ns;
    profiler.phase_retained_draw_icon_ns += timings.draw_icon_ns;
}

fn resetPhase(profiler: *FrameProfiler) void {
    profiler.phase_log_accum_ns = 0;
    profiler.phase_log_frames = 0;
    profiler.phase_frame_ns = 0;
    profiler.phase_input_ns = 0;
    profiler.phase_lua_events_ns = 0;
    profiler.phase_lua_update_ns = 0;
    profiler.phase_retained_ns = 0;
    profiler.phase_commands_ns = 0;
    profiler.phase_present_ns = 0;
    profiler.phase_retained_layout_ns = 0;
    profiler.phase_retained_hover_ns = 0;
    profiler.phase_retained_hit_test_ns = 0;
    profiler.phase_retained_render_ns = 0;
    profiler.phase_retained_focus_ns = 0;
    profiler.phase_retained_draw_bg_ns = 0;
    profiler.phase_retained_draw_text_ns = 0;
    profiler.phase_retained_draw_image_ns = 0;
    profiler.phase_retained_draw_icon_ns = 0;
}

pub fn endFrame(profiler: *FrameProfiler, log_fn: anytype, log_ctx: anytype, frame_start_ns: i128) void {
    const frame_end_ns = std.time.nanoTimestamp();
    const frame_delta_ns = frame_end_ns - frame_start_ns;
    profiler.phase_frame_ns += frame_delta_ns;
    profiler.phase_log_accum_ns += frame_delta_ns;
    profiler.phase_log_frames += 1;

    if (profiler.phase_log_accum_ns >= std.time.ns_per_s) {
        _ = log_ctx;
        // const frames_f: f64 = @floatFromInt(profiler.phase_log_frames);
        // const frame_ms: f64 = @as(f64, @floatFromInt(profiler.phase_frame_ns)) / frames_f / 1_000_000.0;
        // const input_ms: f64 = @as(f64, @floatFromInt(profiler.phase_input_ns)) / frames_f / 1_000_000.0;
        // const lua_events_ms: f64 = @as(f64, @floatFromInt(profiler.phase_lua_events_ns)) / frames_f / 1_000_000.0;
        // const lua_update_ms: f64 = @as(f64, @floatFromInt(profiler.phase_lua_update_ns)) / frames_f / 1_000_000.0;
        // const retained_ms: f64 = @as(f64, @floatFromInt(profiler.phase_retained_ns)) / frames_f / 1_000_000.0;
        // const retained_layout_ms: f64 = @as(f64, @floatFromInt(profiler.phase_retained_layout_ns)) / frames_f / 1_000_000.0;
        // const retained_hover_ms: f64 = @as(f64, @floatFromInt(profiler.phase_retained_hover_ns)) / frames_f / 1_000_000.0;
        // const retained_hit_ms: f64 = @as(f64, @floatFromInt(profiler.phase_retained_hit_test_ns)) / frames_f / 1_000_000.0;
        // const retained_render_ms: f64 = @as(f64, @floatFromInt(profiler.phase_retained_render_ns)) / frames_f / 1_000_000.0;
        // const retained_focus_ms: f64 = @as(f64, @floatFromInt(profiler.phase_retained_focus_ns)) / frames_f / 1_000_000.0;
        // const retained_bg_ms: f64 = @as(f64, @floatFromInt(profiler.phase_retained_draw_bg_ns)) / frames_f / 1_000_000.0;
        // const retained_text_ms: f64 = @as(f64, @floatFromInt(profiler.phase_retained_draw_text_ns)) / frames_f / 1_000_000.0;
        // const retained_image_ms: f64 = @as(f64, @floatFromInt(profiler.phase_retained_draw_image_ns)) / frames_f / 1_000_000.0;
        // const retained_icon_ms: f64 = @as(f64, @floatFromInt(profiler.phase_retained_draw_icon_ns)) / frames_f / 1_000_000.0;
        // const commands_ms: f64 = @as(f64, @floatFromInt(profiler.phase_commands_ns)) / frames_f / 1_000_000.0;
        // const present_ms: f64 = @as(f64, @floatFromInt(profiler.phase_present_ns)) / frames_f / 1_000_000.0;
        _ = log_fn;
        // log_fn(log_ctx, 1, "frame {d:.2}ms input {d:.2}ms lua_events {d:.2}ms lua_update {d:.2}ms retained {d:.2}ms layout {d:.2}ms hover {d:.2}ms hit {d:.2}ms render {d:.2}ms focus {d:.2}ms bg {d:.2}ms text {d:.2}ms image {d:.2}ms icon {d:.2}ms commands {d:.2}ms present {d:.2}ms", .{
        //     frame_ms,
        //     input_ms,
        //     lua_events_ms,
        //     lua_update_ms,
        //     retained_ms,
        //     retained_layout_ms,
        //     retained_hover_ms,
        //     retained_hit_ms,
        //     retained_render_ms,
        //     retained_focus_ms,
        //     retained_bg_ms,
        //     retained_text_ms,
        //     retained_image_ms,
        //     retained_icon_ms,
        //     commands_ms,
        //     present_ms,
        // });
        resetPhase(profiler);
    }

    if (profiler.frame_log_last_ns == 0) {
        profiler.frame_log_last_ns = frame_end_ns;
    } else {
        const delta_ns = frame_end_ns - profiler.frame_log_last_ns;
        profiler.frame_log_last_ns = frame_end_ns;
        profiler.frame_log_accum_ns += delta_ns;
        profiler.frame_log_frames += 1;
        if (profiler.frame_log_accum_ns >= std.time.ns_per_s) {
            // const elapsed_s: f64 = @floatFromInt(profiler.frame_log_accum_ns);
            // const fps: f64 = @as(f64, @floatFromInt(profiler.frame_log_frames)) / (elapsed_s / 1_000_000_000.0);
            // log_fn(log_ctx, 1, "fps {d:.2}", .{fps});
            profiler.frame_log_accum_ns = 0;
            profiler.frame_log_frames = 0;
        }
    }
}
