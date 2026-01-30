pub const cdef = @cImport({
    @cInclude("yoga/Yoga.h");
});

pub const enums = @import("./enums.zig");

pub const Value = struct {
    value: f32,
    unit: enums.Unit,
};

pub const Layout = struct {
    left: f32,
    right: f32,
    top: f32,
    bottom: f32,
    width: f32,
    height: f32,
};

pub const Basis = union(enum) {
    number: f32,
    percent: f32,
    auto,
    fitContent,
    maxContent,
    stretch,
};

pub const Config = struct {
    handle: cdef.YGConfigRef,

    pub fn init() Config {
        return .{
            .handle = cdef.YGConfigNew(),
        };
    }

    pub fn free(self: Config) void {
        cdef.YGConfigFree(self.handle);
    }
    pub fn isExperimentalFeatureEnabled(self: Config, feature: enums.ExperimentalFeature) bool {
        return cdef.YGConfigIsExperimentalFeatureEnabled(self.handle, feature);
    }
    pub fn setExperimentalFeatureEnabled(self: Config, feature: enums.ExperimentalFeature, enabled: bool) void {
        cdef.YGConfigSetExperimentalFeatureEnabled(self.handle, feature, enabled);
    }
    pub fn setPointScaleFactor(self: Config, factor: f32) void {
        cdef.YGConfigSetPointScaleFactor(self.handle, factor);
    }
    pub fn getErrata(self: Config) enums.Errata {
        return cdef.YGConfigGetErrata(self.handle);
    }
    pub fn setErrata(self: Config, errata: enums.Errata) void {
        cdef.YGConfigSetErrata(self.handle, errata);
    }
    pub fn getUseWebDefaults(self: Config) bool {
        return cdef.YGConfigGetUseWebDefaults(self.handle);
    }
    pub fn setUseWebDefaults(self: Config, useWebDefaults: bool) void {
        cdef.YGConfigSetUseWebDefaults(self.handle, useWebDefaults);
    }
};

pub const Node = struct {
    handle: cdef.YGNodeRef,

    pub fn new() Node {
        return .{
            .handle = cdef.YGNodeNew(),
        };
    }

    pub fn newWithConfig(config: Config) Node {
        return .{
            .handle = cdef.YGNodeNewWithConfig(config.handle),
        };
    }

    pub fn free(self: Node) void {
        cdef.YGNodeFree(self.handle);
    }
    pub fn freeRecursive(self: Node) void {
        cdef.YGNodeFreeRecursive(self.handle);
    }

    pub fn copyStyle(self: Node) void {
        cdef.YGNodeCopyStyle(self.handle);
    }

    pub fn calculateLayout(self: Node, availableWidth: ?f32, availableHeight: ?f32, ownerDirection: ?enums.Direction) void {
        const ygDir = @as(c_uint, @intFromEnum(ownerDirection orelse enums.Direction.Inherit));
        cdef.YGNodeCalculateLayout(self.handle, availableWidth orelse 0.0, availableHeight orelse 0.0, ygDir);
    }

    pub fn getChildCount(self: Node) usize {
        return cdef.YGNodeGetChildCount(self.handle);
    }
    pub fn getChild(self: Node, index: usize) Node {
        const ygNode = cdef.YGNodeGetChild(self.handle, index);
        return .{ .handle = ygNode };
    }

    pub fn getFlexDirection(self: Node) enums.FlexDirection {
        const ygValue = cdef.YGNodeStyleGetFlexDirection(self.handle);
        return @enumFromInt(@as(i32, ygValue));
    }

    pub fn getWidth(self: Node) Value {
        const ygValue = cdef.YGNodeStyleGetWidth(self.handle);
        return .{
            .value = ygValue.value,
            .unit = @enumFromInt(@as(i32, ygValue.unit)),
        };
    }

    pub fn getHeight(self: Node) Value {
        const ygValue = cdef.YGNodeStyleGetHeight(self.handle);
        return .{
            .value = ygValue.value,
            .unit = @enumFromInt(@as(i32, ygValue.unit)),
        };
    }
    pub fn insertChild(self: Node, child: Node, index: usize) void {
        cdef.YGNodeInsertChild(self.handle, child.handle, index);
    }

    pub fn getComputedBorder(self: Node, edge: enums.Edge) f32 {
        const ygEdge = @as(c_uint, @intFromEnum(edge));
        return cdef.YGNodeLayoutGetBorder(self.handle, ygEdge);
    }
    pub fn getComputedLayout(self: Node) Layout {
        const left = cdef.YGNodeLayoutGetLeft(self.handle);
        const right = cdef.YGNodeLayoutGetRight(self.handle);
        const top = cdef.YGNodeLayoutGetTop(self.handle);
        const bottom = cdef.YGNodeLayoutGetBottom(self.handle);
        const width = cdef.YGNodeLayoutGetWidth(self.handle);
        const height = cdef.YGNodeLayoutGetHeight(self.handle);

        return .{
            .left = left,
            .right = right,
            .top = top,
            .bottom = bottom,
            .width = width,
            .height = height,
        };
    }
    pub fn getComputedMargin(self: Node, edge: enums.Edge) f32 {
        const ygEdge = @as(c_uint, @intFromEnum(edge));
        return cdef.YGNodeLayoutGetMargin(self.handle, ygEdge);
    }
    pub fn getComputedPadding(self: Node, edge: enums.Edge) f32 {
        const ygEdge = @as(c_uint, @intFromEnum(edge));
        return cdef.YGNodeLayoutGetPadding(self.handle, ygEdge);
    }
    pub fn getComputedWidth(self: Node) f32 {
        return cdef.YGNodeLayoutGetWidth(self.handle);
    }
    pub fn getComputedHeight(self: Node) f32 {
        return cdef.YGNodeLayoutGetHeight(self.handle);
    }
    pub fn getComputedLeft(self: Node) f32 {
        return cdef.YGNodeLayoutGetLeft(self.handle);
    }
    pub fn getComputedTop(self: Node) f32 {
        return cdef.YGNodeLayoutGetTop(self.handle);
    }
    pub fn getComputedRight(self: Node) f32 {
        return cdef.YGNodeLayoutGetRight(self.handle);
    }
    pub fn getComputedBottom(self: Node) f32 {
        return cdef.YGNodeLayoutGetBottom(self.handle);
    }

    pub fn getAlignContent(self: Node) enums.Align {
        const ygValue = cdef.YGNodeStyleGetAlignContent(self.handle);
        return @enumFromInt(@as(i32, ygValue));
    }
    pub fn getAlignItems(self: Node) enums.Align {
        const ygValue = cdef.YGNodeStyleGetAlignItems(self.handle);
        return @enumFromInt(@as(i32, ygValue));
    }
    pub fn getAlignSelf(self: Node) enums.Align {
        const ygValue = cdef.YGNodeStyleGetAlignSelf(self.handle);
        return @enumFromInt(@as(i32, ygValue));
    }
    pub fn getAspectRatio(self: Node) f32 {
        return cdef.YGNodeStyleGetAspectRatio(self.handle);
    }
    pub fn getBorder(self: Node, edge: enums.Edge) f32 {
        const ygEdge = @as(c_uint, @intFromEnum(edge));
        return cdef.YGNodeStyleGetBorder(self.handle, ygEdge);
    }

    pub fn getDirection(self: Node) enums.Direction {
        const ygValue = cdef.YGNodeStyleGetDirection(self.handle);
        return @enumFromInt(@as(i32, ygValue));
    }
    pub fn getDisplay(self: Node) enums.Display {
        const ygValue = cdef.YGNodeStyleGetDisplay(self.handle);
        return @enumFromInt(@as(i32, ygValue));
    }
    pub fn getFlexBasis(self: Node) Value {
        const ygValue = cdef.YGNodeStyleGetFlexBasis(self.handle);
        return .{
            .value = ygValue.value,
            .unit = @enumFromInt(@as(i32, ygValue.unit)),
        };
    }

    pub fn getFlexGrow(self: Node) f32 {
        return cdef.YGNodeStyleGetFlexGrow(self.handle);
    }
    pub fn getFlexShrink(self: Node) f32 {
        return cdef.YGNodeStyleGetFlexShrink(self.handle);
    }
    pub fn getFlexWrap(self: Node) enums.Wrap {
        const ygValue = cdef.YGNodeStyleGetFlexWrap(self.handle);
        return @enumFromInt(@as(i32, ygValue));
    }

    pub fn getJustifyContent(self: Node) enums.Justify {
        const ygValue = cdef.YGNodeStyleGetJustifyContent(self.handle);
        return @enumFromInt(@as(i32, ygValue));
    }

    pub fn getGap(self: Node, gutter: enums.Gutter) Value {
        const ygValue = cdef.YGNodeStyleGetGap(self.handle, @intFromEnum(gutter));
        return .{
            .value = ygValue.value,
            .unit = @enumFromInt(@as(i32, ygValue.unit)),
        };
    }
    pub fn getMargin(self: Node, edge: enums.Edge) Value {
        const ygValue = cdef.YGNodeStyleGetMargin(self.handle, @intFromEnum(edge));
        return .{
            .value = ygValue.value,
            .unit = @enumFromInt(@as(i32, ygValue.unit)),
        };
    }
    pub fn getMaxHeight(self: Node) Value {
        const ygValue = cdef.YGNodeStyleGetMaxHeight(self.handle);
        return .{
            .value = ygValue.value,
            .unit = @enumFromInt(@as(i32, ygValue.unit)),
        };
    }
    pub fn getMaxWidth(self: Node) Value {
        const ygValue = cdef.YGNodeStyleGetMaxWidth(self.handle);
        return .{
            .value = ygValue.value,
            .unit = @enumFromInt(@as(i32, ygValue.unit)),
        };
    }
    pub fn getMinHeight(self: Node) Value {
        const ygValue = cdef.YGNodeStyleGetMinHeight(self.handle);
        return .{
            .value = ygValue.value,
            .unit = @enumFromInt(@as(i32, ygValue.unit)),
        };
    }
    pub fn getMinWidth(self: Node) Value {
        const ygValue = cdef.YGNodeStyleGetMinWidth(self.handle);
        return .{
            .value = ygValue.value,
            .unit = @enumFromInt(@as(i32, ygValue.unit)),
        };
    }
    pub fn getOverflow(self: Node) enums.Overflow {
        const ygValue = cdef.YGNodeStyleGetOverflow(self.handle);
        return @enumFromInt(@as(i32, ygValue));
    }
    pub fn getPadding(self: Node, edge: enums.Edge) Value {
        const ygValue = cdef.YGNodeStyleGetPadding(self.handle, @intFromEnum(edge));
        return .{
            .value = ygValue.value,
            .unit = @enumFromInt(@as(i32, ygValue.unit)),
        };
    }
    pub fn getParent(self: Node) ?Node {
        const ygNode = cdef.YGNodeGetParent(self.handle);
        if (ygNode == null) {
            return null;
        }
        return .{ .handle = ygNode };
    }
    pub fn getPosition(self: Node, edge: enums.Edge) Value {
        const ygValue = cdef.YGNodeStyleGetPosition(self.handle, @intFromEnum(edge));
        return .{
            .value = ygValue.value,
            .unit = @enumFromInt(@as(i32, ygValue.unit)),
        };
    }
    pub fn getPositionType(self: Node) enums.PositionType {
        const ygValue = cdef.YGNodeStyleGetPositionType(self.handle);
        return @enumFromInt(@as(i32, ygValue));
    }
    pub fn getBoxSizing(self: Node) enums.BoxSizing {
        const ygValue = cdef.YGNodeStyleGetBoxSizing(self.handle);
        return @enumFromInt(@as(i32, ygValue));
    }
    pub fn isDirty(self: Node) bool {
        return cdef.YGNodeIsDirty(self.handle);
    }
    pub fn isReferenceBaseline(self: Node) bool {
        return cdef.YGNodeIsReferenceBaseline(self.handle);
    }
    pub fn markDirty(self: Node) void {
        cdef.YGNodeMarkDirty(self.handle);
    }
    pub fn hasNewLayout(self: Node) bool {
        return cdef.YGNodeHasNewLayout(self.handle);
    }
    pub fn markLayoutSeen(self: Node) void {
        cdef.YGNodeMarkLayoutSeen(self.handle);
    }
    pub fn removeChild(self: Node, child: Node) void {
        cdef.YGNodeRemoveChild(self.handle, child.handle);
    }
    pub fn reset(self: Node) void {
        cdef.YGNodeReset(self.handle);
    }
    pub fn setAlignContent(self: Node, alignContent: enums.Align) void {
        cdef.YGNodeStyleSetAlignContent(self.handle, @intFromEnum(alignContent));
    }
    pub fn setAlignItems(self: Node, alignItems: enums.Align) void {
        cdef.YGNodeStyleSetAlignItems(self.handle, @intFromEnum(alignItems));
    }
    pub fn setAlignSelf(self: Node, alignSelf: enums.Align) void {
        cdef.YGNodeStyleSetAlignSelf(self.handle, @intFromEnum(alignSelf));
    }
    pub fn setAspectRatio(self: Node, aspectRatio: ?f32) void {
        cdef.YGNodeStyleSetAspectRatio(self.handle, aspectRatio orelse 0.0);
    }
    pub fn setBorder(self: Node, edge: enums.Edge, borderWidth: ?f32) void {
        const ygEdge = @as(c_uint, @intFromEnum(edge));
        cdef.YGNodeStyleSetBorder(self.handle, ygEdge, borderWidth orelse 0.0);
    }
    pub fn setDirection(self: Node, direction: enums.Direction) void {
        cdef.YGNodeStyleSetDirection(self.handle, @intFromEnum(direction));
    }
    pub fn setDisplay(self: Node, display: enums.Display) void {
        cdef.YGNodeStyleSetDisplay(self.handle, @intFromEnum(display));
    }
    pub fn setFlex(self: Node, flex: ?f32) void {
        cdef.YGNodeStyleSetFlex(self.handle, flex orelse 0.0);
    }
    pub fn setFlexBasis(self: Node, flexBasis: ?Basis) void {
        if (flexBasis == null) {
            cdef.YGNodeStyleSetFlexBasis(self.handle, 0);
        } else {
            switch (flexBasis) {
                Basis.number => |value| cdef.YGNodeStyleSetFlexBasis(self.handle, value),
                Basis.percent => |value| cdef.YGNodeStyleSetFlexBasisPercent(self.handle, value),
                Basis.auto => cdef.YGNodeStyleSetFlexBasisAuto(self.handle),
                Basis.fitContent => cdef.YGNodeStyleSetFlexBasisFitContent(self.handle),
                Basis.maxContent => cdef.YGNodeStyleSetFlexBasisMaxContent(self.handle),
                Basis.stretch => cdef.YGNodeStyleSetFlexBasisAuto(self.handle),
            }
        }
    }

    pub fn setFlexBasisPercent(self: Node, percent: f32) void {
        cdef.YGNodeStyleSetFlexBasisPercent(self.handle, percent);
    }
    pub fn setFlexBasisAuto(self: Node) void {
        cdef.YGNodeStyleSetFlexBasisAuto(self.handle);
    }
    pub fn setFlexBasisMaxContent(self: Node) void {
        cdef.YGNodeStyleSetFlexBasisMaxContent(self.handle);
    }
    pub fn setFlexBasisFitContent(self: Node) void {
        cdef.YGNodeStyleSetFlexBasisFitContent(self.handle);
    }
    pub fn setFlexBasisStretch(self: Node) void {
        cdef.YGNodeStyleSetFlexBasisStretch(self.handle);
    }
    pub fn setFlexDirection(self: Node, flexDirection: enums.FlexDirection) void {
        cdef.YGNodeStyleSetFlexDirection(self.handle, @intFromEnum(flexDirection));
    }
    pub fn setFlexGrow(self: Node, flexGrow: f32) void {
        cdef.YGNodeStyleSetFlexGrow(self.handle, flexGrow);
    }
    pub fn setFlexShrink(self: Node, flexShrink: f32) void {
        cdef.YGNodeStyleSetFlexShrink(self.handle, flexShrink);
    }
    pub fn setFlexWrap(self: Node, flexWrap: enums.Wrap) void {
        cdef.YGNodeStyleSetFlexWrap(self.handle, @intFromEnum(flexWrap));
    }

    pub fn setHeight(self: Node, height: f32) void {
        cdef.YGNodeStyleSetHeight(self.handle, height);
    }
    pub fn setHeightAuto(self: Node) void {
        cdef.YGNodeStyleSetHeightAuto(self.handle);
    }
    pub fn setHeightPercent(self: Node, percent: f32) void {
        cdef.YGNodeStyleSetHeightPercent(self.handle, percent);
    }
    pub fn setHeightStretch(self: Node) void {
        cdef.YGNodeStyleSetHeightStretch(self.handle);
    }

    pub fn setJustifyContent(self: Node, justifyContent: enums.Justify) void {
        cdef.YGNodeStyleSetJustifyContent(self.handle, @intFromEnum(justifyContent));
    }

    pub fn setGap(self: Node, gutter: enums.Gutter, gapLength: f32) void {
        cdef.YGNodeStyleSetGap(self.handle, @intFromEnum(gutter), gapLength);
    }
    pub fn setGapPercent(self: Node, gutter: enums.Gutter, percentage: f32) void {
        cdef.YGNodeStyleSetGapPercent(self.handle, @intFromEnum(gutter), percentage);
    }

    pub fn setMargin(self: Node, edge: enums.Edge, margin: f32) void {
        const ygEdge = @as(c_uint, @intFromEnum(edge));
        cdef.YGNodeStyleSetMargin(self.handle, ygEdge, margin);
    }
    pub fn setMarginAuto(self: Node, edge: enums.Edge) void {
        const ygEdge = @as(c_uint, @intFromEnum(edge));
        cdef.YGNodeStyleSetMarginAuto(self.handle, ygEdge);
    }
    pub fn setMarginPercent(self: Node, edge: enums.Edge, percent: f32) void {
        const ygEdge = @as(c_uint, @intFromEnum(edge));
        cdef.YGNodeStyleSetMarginPercent(self.handle, ygEdge, percent);
    }

    pub fn setMaxHeight(self: Node, maxHeight: f32) void {
        cdef.YGNodeStyleSetMaxHeight(self.handle, maxHeight);
    }
    pub fn setMaxHeightFitContent(self: Node) void {
        cdef.YGNodeStyleSetMaxHeightFitContent(self.handle);
    }
    pub fn setMaxHeightMaxContent(self: Node) void {
        cdef.YGNodeStyleSetMaxHeightMaxContent(self.handle);
    }
    pub fn setMaxHeightPercent(self: Node, percent: f32) void {
        cdef.YGNodeStyleSetMaxHeightPercent(self.handle, percent);
    }
    pub fn setMaxHeightStretch(self: Node) void {
        cdef.YGNodeStyleSetMaxHeightStretch(self.handle);
    }

    pub fn setMaxWidth(self: Node, maxWidth: f32) void {
        cdef.YGNodeStyleSetMaxWidth(self.handle, maxWidth);
    }
    pub fn setMaxWidthFitContent(self: Node) void {
        cdef.YGNodeStyleSetMaxWidthFitContent(self.handle);
    }
    pub fn setMaxWidthMaxContent(self: Node) void {
        cdef.YGNodeStyleSetMaxWidthMaxContent(self.handle);
    }
    pub fn setMaxWidthPercent(self: Node, percent: f32) void {
        cdef.YGNodeStyleSetMaxWidthPercent(self.handle, percent);
    }
    pub fn setMaxWidthStretch(self: Node) void {
        cdef.YGNodeStyleSetMaxWidthStretch(self.handle);
    }

    pub fn setDirtiedFunc(self: Node, func: cdef.YGDirtiedFunc) void {
        cdef.YGNodeSetDirtiedFunc(self.handle, func);
    }
    pub fn setMeasureFunc(self: Node, func: cdef.YGMeasureFunc) void {
        cdef.YGNodeSetMeasureFunc(self.handle, func);
    }

    pub fn setMinHeight(self: Node, minHeight: f32) void {
        cdef.YGNodeStyleSetMinHeight(self.handle, minHeight);
    }
    pub fn setMinHeightFitContent(self: Node) void {
        cdef.YGNodeStyleSetMinHeightFitContent(self.handle);
    }
    pub fn setMinHeightMaxContent(self: Node) void {
        cdef.YGNodeStyleSetMinHeightMaxContent(self.handle);
    }
    pub fn setMinHeightPercent(self: Node, percent: f32) void {
        cdef.YGNodeStyleSetMinHeightPercent(self.handle, percent);
    }
    pub fn setMinHeightStretch(self: Node) void {
        cdef.YGNodeStyleSetMinHeightStretch(self.handle);
    }

    pub fn setMinWidth(self: Node, minWidth: f32) void {
        cdef.YGNodeStyleSetMinWidth(self.handle, minWidth);
    }
    pub fn setMinWidthFitContent(self: Node) void {
        cdef.YGNodeStyleSetMinWidthFitContent(self.handle);
    }
    pub fn setMinWidthMaxContent(self: Node) void {
        cdef.YGNodeStyleSetMinWidthMaxContent(self.handle);
    }
    pub fn setMinWidthPercent(self: Node, percent: f32) void {
        cdef.YGNodeStyleSetMinWidthPercent(self.handle, percent);
    }
    pub fn setMinWidthStretch(self: Node) void {
        cdef.YGNodeStyleSetMinWidthStretch(self.handle);
    }

    pub fn setOverflow(self: Node, overflow: enums.Overflow) void {
        cdef.YGNodeStyleSetOverflow(self.handle, @intFromEnum(overflow));
    }

    pub fn setPadding(self: Node, edge: enums.Edge, padding: f32) void {
        const ygEdge = @as(c_uint, @intFromEnum(edge));
        cdef.YGNodeStyleSetPadding(self.handle, ygEdge, padding);
    }
    pub fn setPaddingPercent(self: Node, edge: enums.Edge, percent: f32) void {
        const ygEdge = @as(c_uint, @intFromEnum(edge));
        cdef.YGNodeStyleSetPaddingPercent(self.handle, ygEdge, percent);
    }

    pub fn setPosition(self: Node, edge: enums.Edge, position: f32) void {
        const ygEdge = @as(c_uint, @intFromEnum(edge));
        cdef.YGNodeStyleSetPosition(self.handle, ygEdge, position);
    }
    pub fn setPositionPercent(self: Node, edge: enums.Edge, percent: f32) void {
        const ygEdge = @as(c_uint, @intFromEnum(edge));
        cdef.YGNodeStyleSetPositionPercent(self.handle, ygEdge, percent);
    }
    pub fn setPositionType(self: Node, positionType: enums.PositionType) void {
        cdef.YGNodeStyleSetPositionType(self.handle, @intFromEnum(positionType));
    }
    pub fn setPositionAuto(self: Node, edge: enums.Edge) void {
        const ygEdge = @as(c_uint, @intFromEnum(edge));
        cdef.YGNodeStyleSetPositionAuto(self.handle, ygEdge);
    }

    pub fn setBoxSizing(self: Node, boxSizing: enums.BoxSizing) void {
        cdef.YGNodeStyleSetBoxSizing(self.handle, @intFromEnum(boxSizing));
    }

    pub fn setWidth(self: Node, width: f32) void {
        cdef.YGNodeStyleSetWidth(self.handle, width);
    }
    pub fn setWidthAuto(self: Node) void {
        cdef.YGNodeStyleSetWidthAuto(self.handle);
    }
    pub fn setWidthFitContent(self: Node) void {
        cdef.YGNodeStyleSetWidthFitContent(self.handle);
    }
    pub fn setWidthMaxContent(self: Node) void {
        cdef.YGNodeStyleSetWidthMaxContent(self.handle);
    }
    pub fn setWidthPercent(self: Node, percent: f32) void {
        cdef.YGNodeStyleSetWidthPercent(self.handle, percent);
    }
    pub fn setWidthStretch(self: Node) void {
        cdef.YGNodeStyleSetWidthStretch(self.handle);
    }

    pub fn unsetDirtieFunc(self: Node) void {
        cdef.YGNodeSetDirtiedFunc(self.handle, null);
    }
    pub fn unsetMeasureFunc(self: Node) void {
        cdef.YGNodeSetMeasureFunc(self.handle, null);
    }

    pub fn setAlwaysFormsContainerBlock(self: Node, always: bool) void {
        cdef.YGNodeSetAlwaysFormsContainingBlock(self.handle, always);
    }
};

test "basic test" {
    const root = Node.new();
    defer root.free();
    root.setFlexDirection(enums.FlexDirection.Row);
    root.setWidth(100);
    root.setHeight(100);

    const child0 = Node.new();
    defer child0.free();
    child0.setFlexGrow(1);
    child0.setMargin(enums.Edge.Right, 10);
    root.insertChild(child0, 0);

    const child1 = Node.new();
    defer child1.free();
    child1.setFlexGrow(1);
    root.insertChild(child1, 1);

    root.calculateLayout(undefined, undefined, enums.Direction.LTR);
}
