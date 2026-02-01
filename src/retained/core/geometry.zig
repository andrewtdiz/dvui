pub const Rect = struct {
    x: f32 = 0,
    y: f32 = 0,
    w: f32 = 0,
    h: f32 = 0,
};

pub const Size = struct {
    w: f32 = 0,
    h: f32 = 0,
};

pub const SideOffsets = struct {
    left: f32 = 0,
    right: f32 = 0,
    top: f32 = 0,
    bottom: f32 = 0,
};

pub const GizmoRect = struct {
    x: f32,
    y: f32,
    w: f32,
    h: f32,
    serial: u64 = 0,
};

pub const Transform = struct {
    anchor: [2]f32 = .{ 0.5, 0.5 },
    scale: [2]f32 = .{ 1, 1 },
    rotation: f32 = 0,
    translation: [2]f32 = .{ 0, 0 },
};
