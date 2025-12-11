//! You can find below a list of available widgets.
//!
//! Note that most of the time, you will **not** instanciate them directly but instead rely on higher level functions available in `dvui` top module.
//!
//! The corresponding function is usually indicated in the doc of each Widget.

// Note : this "intermediate" file is mostly there for nice reference in the docs.

pub const AnimateWidget = @import("widgets/AnimateWidget.zig");
pub const BoxWidget = @import("widgets/BoxWidget.zig");
pub const ButtonWidget = @import("widgets/ButtonWidget.zig");
pub const FlexBoxWidget = @import("widgets/FlexBoxWidget.zig");
pub const IconWidget = @import("widgets/IconWidget.zig");
pub const LabelWidget = @import("widgets/LabelWidget.zig");
pub const ScrollBarWidget = @import("widgets/ScrollBarWidget.zig");
pub const ColorPickerWidget = @import("widgets/ColorPickerWidget.zig");
pub const GizmoWidget = @import("widgets/GizmoWidget.zig");
pub const MenuWidget = @import("widgets/MenuWidget.zig");
pub const MenuItemWidget = @import("widgets/MenuItemWidget.zig");
pub const PanedWidget = @import("widgets/PanedWidget.zig");
pub const PlotWidget = @import("widgets/PlotWidget.zig");
pub const ReorderWidget = @import("widgets/ReorderWidget.zig");
pub const ScaleWidget = @import("widgets/ScaleWidget.zig");
pub const TreeWidget = @import("widgets/TreeWidget.zig");
// Needed for autodocs "backlink" to work
const dvui = @import("dvui");

test {
    @import("std").testing.refAllDecls(@This());
}
