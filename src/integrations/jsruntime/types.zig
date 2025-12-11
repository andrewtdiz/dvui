pub const FrameData = struct {
    position: f32,
    dt: f32,
};

pub const SelectionColor = u32;

pub const FrameResult = struct {
    new_position: f32,
};

pub const FrameCommand = union(enum) {
    set_animated_position: f32,
};

pub const MouseSnapshot = struct {
    x: i32,
    y: i32,
};

pub const MouseButton = enum { left, right };

pub const MouseEventKind = enum { down, up, click };

pub const MouseEvent = struct {
    kind: MouseEventKind,
    button: MouseButton,
    x: i32,
    y: i32,
};

pub const KeyCode = enum { g, r, s };

pub const KeyEventKind = enum { down, up, press };

pub const KeyEvent = struct {
    kind: KeyEventKind,
    code: KeyCode,
    repeat: bool,
};
