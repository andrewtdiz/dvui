const math = @import("../../../math/main.zig");

pub const Vec4 = @Vector(4, f32);

// Particle payload used by GPU compute + render stages. Keep fields 16-byte aligned
// to match WGSL std140 rules for uniform/storage buffers.
pub const GpuParticle = extern struct {
    position_size: Vec4, // xyz position, w = current size
    velocity_age: Vec4, // xyz velocity, w = age
    color: Vec4, // current color with premultiplied alpha
    lifetime_flags: Vec4, // x = lifetime, y = active (1.0/0.0), z = rotation, w = rot_speed
    start_color_alpha: Vec4, // rgb + alpha start
    end_color_alpha: Vec4, // rgb + alpha end
    size_params: Vec4, // x = start_size, y = end_size, z/w unused
    uv_min_size: Vec4, // xy = min, zw = size
};

pub const Counters = extern struct {
    alive_count: u32,
    free_top: u32,
    _pad0: u32 = 0,
    _pad1: u32 = 0,
};

pub const DrawArgs = extern struct {
    vertex_count: u32,
    instance_count: u32,
    first_vertex: u32 = 0,
    first_instance: u32 = 0,
};

// Debug payload written by compute to help diagnose draw issues without CPU buffer mapping.
pub const DebugData = extern struct {
    alive_index: u32,
    _pad0: u32 = 0,
    _pad1: u32 = 0,
    _pad2: u32 = 0,
    sample: GpuParticle,
};

pub const SimParams = extern struct {
    // dt, spawn_count, elapsed_time, seed
    dt_spawn_seed: Vec4,
    // gravity.xyz, drag
    gravity_drag: Vec4,
    // spawn_position.xyz, life_min
    spawn_life: Vec4,
    // life_min, life_max, unused, unused
    life_params: Vec4,
    // min_speed, max_speed, spread_x_rad, spread_y_rad
    speed_angle: Vec4,
    // direction.xyz, spread_mode (0=single,1=double)
    direction_spread_mode: Vec4,
    // start color + alpha
    start_color_alpha: Vec4,
    // end color + alpha
    end_color_alpha: Vec4,
    // start_size, end_size, flip_cols, flip_rows
    size_cols_rows: Vec4,
    // flip_fps, flip_mode, flip_start_random, orientation_mode
    flip_params: Vec4,
    // limits.x = max_particles, limits.y = max_draw_distance, z = enabled flag, w = shape_type
    limits: Vec4,
    // emit_info.x = base_particle_index, emit_info.y = emitter_capacity, emit_info.z = texture_id, emit_info.w = emitter_id
    emit_info: Vec4,
    // rotation_min, rotation_max, rot_speed_min, rot_speed_max
    rotation_params: Vec4,
    // box_extents.xyz, sphere_radius
    shape_params: Vec4,
};

pub const ViewUniforms = extern struct {
    projection: [4][4]f32,
    view: [4][4]f32,
    camera_right: Vec4,
    camera_up: Vec4,
};

pub fn defaultView() ViewUniforms {
    const proj = math.Mat4x4.ident;
    const view = math.Mat4x4.ident;
    return .{
        .projection = math.Mat4x4.toArray(&proj),
        .view = math.Mat4x4.toArray(&view),
        .camera_right = @Vector(4, f32){ 1.0, 0.0, 0.0, 0.0 },
        .camera_up = @Vector(4, f32){ 0.0, 1.0, 0.0, 0.0 },
    };
}
