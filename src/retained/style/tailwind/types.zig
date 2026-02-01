const dvui = @import("dvui");
const FontStyle = dvui.Options.FontStyle;
const design_tokens = dvui.Theme.Tokens;

pub const TextAlign = enum {
    left,
    center,
    right,
};

pub const FontRenderMode = enum {
    auto,
    msdf,
    raster,
};

pub const FontFamily = enum {
    ui,
    mono,
    game,
    dyslexic,
};

pub const FontWeight = enum {
    light,
    normal,
    medium,
    semibold,
    bold,
};

pub const FontSlant = enum {
    normal,
    italic,
};

pub const Width = union(enum) {
    full,
    pixels: f32,
};

pub const Height = union(enum) {
    full,
    pixels: f32,
};

pub const Position = enum {
    absolute,
};

pub const EasingStyle = enum {
    linear,
    sine,
    quad,
    cubic,
    quart,
    quint,
    expo,
    circ,
    back,
    elastic,
    bounce,
};

pub const EasingDirection = enum {
    @"in",
    out,
    in_out,
};

pub const TransitionProps = packed struct(u8) {
    layout: bool = false,
    transform: bool = false,
    colors: bool = false,
    opacity: bool = false,
    _pad: u4 = 0,
};

pub const TransitionConfig = struct {
    enabled: bool = false,
    props: TransitionProps = .{},
    duration_us: i32 = 150_000,
    easing_style: EasingStyle = .quad,
    easing_dir: EasingDirection = .in_out,

    pub fn easingFn(self: *const TransitionConfig) *const dvui.easing.EasingFn {
        if (!self.enabled) return dvui.easing.linear;
        if (self.easing_style == .linear) return dvui.easing.linear;

        return switch (self.easing_style) {
            .sine => switch (self.easing_dir) {
                .@"in" => dvui.easing.inSine,
                .out => dvui.easing.outSine,
                .in_out => dvui.easing.inOutSine,
            },
            .quad => switch (self.easing_dir) {
                .@"in" => dvui.easing.inQuad,
                .out => dvui.easing.outQuad,
                .in_out => dvui.easing.inOutQuad,
            },
            .cubic => switch (self.easing_dir) {
                .@"in" => dvui.easing.inCubic,
                .out => dvui.easing.outCubic,
                .in_out => dvui.easing.inOutCubic,
            },
            .quart => switch (self.easing_dir) {
                .@"in" => dvui.easing.inQuart,
                .out => dvui.easing.outQuart,
                .in_out => dvui.easing.inOutQuart,
            },
            .quint => switch (self.easing_dir) {
                .@"in" => dvui.easing.inQuint,
                .out => dvui.easing.outQuint,
                .in_out => dvui.easing.inOutQuint,
            },
            .expo => switch (self.easing_dir) {
                .@"in" => dvui.easing.inExpo,
                .out => dvui.easing.outExpo,
                .in_out => dvui.easing.inOutExpo,
            },
            .circ => switch (self.easing_dir) {
                .@"in" => dvui.easing.inCirc,
                .out => dvui.easing.outCirc,
                .in_out => dvui.easing.inOutCirc,
            },
            .back => switch (self.easing_dir) {
                .@"in" => dvui.easing.inBack,
                .out => dvui.easing.outBack,
                .in_out => dvui.easing.inOutBack,
            },
            .elastic => switch (self.easing_dir) {
                .@"in" => dvui.easing.inElastic,
                .out => dvui.easing.outElastic,
                .in_out => dvui.easing.inOutElastic,
            },
            .bounce => switch (self.easing_dir) {
                .@"in" => dvui.easing.inBounce,
                .out => dvui.easing.outBounce,
                .in_out => dvui.easing.inOutBounce,
            },
            .linear => dvui.easing.linear,
        };
    }
};

pub const SideTarget = enum {
    all,
    horizontal,
    vertical,
    top,
    right,
    bottom,
    left,
};

pub const SideValues = struct {
    left: ?f32 = null,
    right: ?f32 = null,
    top: ?f32 = null,
    bottom: ?f32 = null,

    pub fn any(self: *const SideValues) bool {
        return self.left != null or self.right != null or self.top != null or self.bottom != null;
    }

    pub fn set(self: *SideValues, target: SideTarget, value: f32) void {
        switch (target) {
            .all => {
                self.left = value;
                self.right = value;
                self.top = value;
                self.bottom = value;
            },
            .horizontal => {
                self.left = value;
                self.right = value;
            },
            .vertical => {
                self.top = value;
                self.bottom = value;
            },
            .top => self.top = value,
            .right => self.right = value,
            .bottom => self.bottom = value,
            .left => self.left = value,
        }
    }
};

pub const Spec = struct {
    background: ?dvui.Color = null,
    text: ?dvui.Color = null,
    text_outline_color: ?dvui.Color = null,
    text_outline_thickness: ?f32 = null,
    width: ?Width = null,
    height: ?Height = null,
    scale: ?f32 = null,
    is_flex: bool = false,
    position: ?Position = null,
    layout_anchor: ?[2]f32 = null,
    top: ?f32 = null,
    right: ?f32 = null,
    bottom: ?f32 = null,
    left: ?f32 = null,
    direction: ?dvui.enums.Direction = null,
    justify: ?dvui.FlexBoxWidget.ContentPosition = null,
    align_items: ?dvui.FlexBoxWidget.AlignItems = null,
    align_content: ?dvui.FlexBoxWidget.AlignContent = null,
    margin: SideValues = .{},
    padding: SideValues = .{},
    border: SideValues = .{},
    border_color: ?dvui.Color = null,
    font_style: ?FontStyle = null,
    font_family: ?FontFamily = null,
    font_weight: ?FontWeight = null,
    font_slant: ?FontSlant = null,
    font_render_mode: FontRenderMode = .auto,
    gap_row: ?f32 = null,
    gap_col: ?f32 = null,
    corner_radius: ?f32 = null,
    z_index: i16 = design_tokens.z_index_default,
    clip_children: ?bool = null,
    scroll_x: bool = false,
    scroll_y: bool = false,
    hidden: bool = false,
    opacity: ?f32 = null,
    text_align: ?TextAlign = null,
    text_wrap: bool = true,
    break_words: bool = false,
    cursor: ?dvui.enums.Cursor = null,
    hover_background: ?dvui.Color = null,
    hover_text: ?dvui.Color = null,
    hover_text_outline_color: ?dvui.Color = null,
    hover_text_outline_thickness: ?f32 = null,
    hover_border: SideValues = .{},
    hover_border_color: ?dvui.Color = null,
    hover_margin: SideValues = .{},
    hover_padding: SideValues = .{},
    hover_opacity: ?f32 = null,
    transition: TransitionConfig = .{},
};

pub const ClassSpec = Spec;
