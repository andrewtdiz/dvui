pub const PackedColor = struct {
    value: u32 = 0,
};

pub const Gradient = struct {
    colors: []PackedColor = &.{},
    stops: []f32 = &.{},
    angle_radians: f32 = 0,
};

pub const VisualProps = struct {
    background: ?PackedColor = null,
    text_color: ?PackedColor = null,
    text_outline_color: ?PackedColor = null,
    text_outline_thickness: ?f32 = null,
    opacity: f32 = 1.0,
    corner_radius: f32 = 0,
    clip_children: bool = false,
    gradient: ?Gradient = null,
    z_index: i16 = 0,
};
