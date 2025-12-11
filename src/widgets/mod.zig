//! You can find below a list of available widgets.
//!
//! Note that most of the time, you will **not** instanciate them directly but instead rely on higher level functions available in `dvui` top module.
//!
//! The corresponding function is usually indicated in the doc of each Widget.

// Note : this "intermediate" file is mostly there for nice reference in the docs.

pub const AnimateWidget = @import("AnimateWidget.zig");
pub const BoxWidget = @import("BoxWidget.zig");
pub const ButtonWidget = @import("ButtonWidget.zig");
pub const FlexBoxWidget = @import("FlexBoxWidget.zig");
pub const IconWidget = @import("IconWidget.zig");
pub const LabelWidget = @import("LabelWidget.zig");
pub const ScrollBarWidget = @import("ScrollBarWidget.zig");
pub const ColorPickerWidget = @import("ColorPickerWidget.zig");
pub const GizmoWidget = @import("GizmoWidget.zig");
pub const MenuWidget = @import("MenuWidget.zig");
pub const MenuItemWidget = @import("MenuItemWidget.zig");
pub const PanedWidget = @import("PanedWidget.zig");
pub const PlotWidget = @import("PlotWidget.zig");
pub const ReorderWidget = @import("ReorderWidget.zig");
pub const ScaleWidget = @import("ScaleWidget.zig");
pub const TreeWidget = @import("TreeWidget.zig");
// Needed for autodocs "backlink" to work
const dvui = @import("../dvui.zig");

test {
    @import("std").testing.refAllDecls(@This());
}
