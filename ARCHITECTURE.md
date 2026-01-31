# DVUI Architecture

A comprehensive guide to the DVUI codebase structure and design patterns.

## Overview

DVUI is a general-purpose **Zig GUI toolkit** that supports two UI paradigms:

1. **Immediate Mode** - Traditional immediate-mode UI where widgets are created/updated every frame
2. **Retained Mode** - A virtual DOM-like approach with a node store, CSS-like styling, and incremental updates

The library is designed to be **backend-agnostic**, supporting Web (WASM), WGPU, raylib, and testing backends.

---

## Directory Structure

```
src/
  dvui.zig              # Main public API - single import point for users
  
  core/                 # Fundamental data types
  layout/               # Layout algorithms and positioning
  render/               # Rendering primitives (triangles, textures, paths)
  text/                 # Font rendering and text selection
  theming/              # Theme definitions and color presets
  widgets/              # Immediate-mode widget implementations
  window/               # Window management and event handling
  
  retained/             # Retained-mode UI system
    core/               # Node store and types
    events/             # Event handling (drag-drop, focus)
    layout/             # Flexbox/Yoga layout engine
    render/             # Retained-mode rendering
    style/              # CSS-like styling (Tailwind-inspired)
  
  backends/             # Platform-specific implementations
  accessibility/        # AccessKit integration
  testing/              # Test utilities
  utils/                # Helper utilities
```

---

## Core Concepts

### Entry Point: `dvui.zig`

All public API is exported through `dvui.zig`. Users import only this:

```zig
const dvui = @import("dvui");
```

This module re-exports types from submodules and provides top-level convenience functions like `dvui.button()`, `dvui.label()`, etc.

### Window (`src/window/window.zig`)

The `Window` struct represents an OS window and holds all frame-to-frame state:

- **Backend handle** - Connection to the rendering backend
- **Event queue** - Input events for the current frame
- **Widget state** - Min sizes, animations, data store
- **Subwindows** - Floating windows/dialogs within the main window
- **Font/texture caches** - Cached resources
- **Theme** - Current visual theme

**Frame lifecycle:**
```zig
var win = try Window.init(@src(), gpa, backend, .{});
defer win.deinit();

while (running) {
    win.begin();           // Start frame, process events
    // ... build UI ...
    win.end();             // Render, cleanup
}
```

### Widget System (`src/widgets/`)

Widgets are the building blocks of the UI. Each widget follows this pattern:

1. **WidgetData** (`widget_data.zig`) - Common widget state (id, rect, options)
2. **Widget** (`widget.zig`) - Vtable-based interface for parent-child relationships

**Widget lifecycle:**
```zig
pub fn init(src: @src(), opts: Options) *ButtonWidget {
    const self = dvui.widgetAlloc(ButtonWidget);
    self.wd = WidgetData.init(src, .{}, opts);
    // ...
    return self;
}

pub fn deinit(self: *ButtonWidget) void {
    // Report min size, cleanup
    dvui.widgetFree(self);
}
```

**Available widgets** (in `src/widgets/mod.zig`):
- `BoxWidget`, `FlexBoxWidget` - Containers
- `ButtonWidget`, `LabelWidget` - Basic controls
- `MenuWidget`, `MenuItemWidget` - Navigation
- `ScrollBarWidget`, `PanedWidget` - Scrolling/splitting
- `PlotWidget`, `GizmoWidget` - Visualization
- `ColorPickerWidget`, `TreeWidget` - Advanced controls

### Options (`src/core/options.zig`)

Widget configuration is done through `Options`:

```zig
dvui.button("Click me", .{
    .gravity = .center,
    .expand = .both,
    .corner_radius = .{ .all = 8 },
    .background_color = .{ .color = dvui.Color.blue },
});
```

Options include: sizing, positioning, colors, borders, margins, padding, accessibility roles, etc.

### Identifiers (`dvui.Id`)

Widgets are identified by hashing:
- Source location (`@src()`)
- Optional `id_extra` for loops
- Parent widget id

```zig
const id = parent.extendId(@src(), id_extra);
```

---

## Coordinate Systems

DVUI uses three coordinate spaces:

| Type | Unit | Usage |
|------|------|-------|
| `Rect` | Untyped | Relative positioning |
| `Rect.Natural` | Natural pixels | UI layout (matches OS window size) |
| `Rect.Physical` | Physical pixels | Rendering (may differ on HiDPI) |

Convert between them using `RectScale` (rect + scale factor).

---

## Rendering Pipeline (`src/render/`)

### Key Components

- **`render.zig`** - High-level render commands (text, textures, icons)
- **`triangles.zig`** - Geometry builder for filled shapes
- **`path.zig`** - Vector path builder (for outlines, curves)
- **`texture.zig`** - Texture management and caching

### Render Flow

1. Widgets call render functions (`dvui.render.renderText()`, etc.)
2. Commands are batched into `RenderCommand` structs
3. Commands queue to the current `RenderTarget`
4. At frame end, backend processes commands into GPU draw calls

### Backends (`src/backends/`)

Backends implement the rendering interface:

| Backend | File | Description |
|---------|------|-------------|
| WGPU | `wgpu.zig` | WebGPU-based rendering |
| Web | `web.zig` | Browser WASM target |
| Testing | `testing.zig` | Headless testing |

Backends handle:
- Texture creation/destruction
- Draw command execution
- Clipboard access
- System dialogs

---

## Event System (`src/window/event.zig`)

Events flow from backend to widgets:

1. **Backend** generates raw input events
2. **Window** collects events with `addEvent*` methods
3. **Widgets** query events via `eventMatch()` and `events()` iterator

```zig
const events = self.wd.events();
for (events) |*ev| {
    switch (ev.evt) {
        .mouse => |mouse| { ... },
        .key => |key| { ... },
        .focus => |focus| { ... },
        _ => {},
    }
}
```

### Mouse Capture

Widgets can capture mouse events to track drags beyond their bounds:

```zig
dvui.captureMouse(&self.wd, ev.num);
// ... handle drag ...
dvui.dragEnd();
```

---

## Retained Mode (`src/retained/`)

An alternative paradigm for building UIs with a persistent node tree.

### Node Store (`retained/core/types.zig`)

Maintains a tree of `SolidNode` elements:

```zig
pub const SolidNode = struct {
    id: u32,
    kind: NodeKind,        // root, element, text, slot
    tag: []const u8,       // HTML-like tag name
    children: ArrayList(u32),
    layout: LayoutState,
    visual_props: VisualProps,
    transform: Transform,
    // ... accessibility, scroll state, etc.
};
```

### Layout Engine (`retained/layout/`)

Uses **Yoga** (flexbox) for layout calculation:

- `yoga.zig` - FFI bindings to Yoga layout engine
- `flex.zig` - Flexbox implementation
- `measure.zig` - Text/content measurement

### Styling (`retained/style/`)

**Tailwind-inspired** CSS classes:

```zig
store.setClassName(node_id, "flex flex-col gap-4 p-4 bg-slate-100");
```

- `tailwind.zig` - Class parser and property application
- `apply.zig` - Style application to nodes
- `colors.zig` - Color palette definitions

### Luau Retained API (`src/integrations/luau_ui/mod.zig`)

Update the tree via Luau bindings:

```luau
ui.create("div", id, parent, nil)
ui.set_class(id, "flex flex-col gap-4 p-4 bg-slate-100")
ui.set_text(text_id, "Hello")
```

### Rendering (`retained/render/`)

- `direct.zig` - Direct rendering of retained nodes
- `cache.zig` - Render caching for unchanged subtrees
- `image_loader.zig` - Async image loading
- `icon_registry.zig` - Icon management

---

## Theming (`src/theming/`)

### Theme Structure

```zig
pub const Theme = struct {
    // Color palette
    background: Color,
    foreground: Color,
    primary: Color,
    // ... more colors

    // Typography
    font: Font,
    font_size: f32,
    
    // Spacing/sizing
    padding: f32,
    border_radius: f32,
    // ...
};
```

### Presets

Built-in themes in `theming/presets/`:
- `shadcn.zon` - shadcn/ui inspired theme

Set theme globally:
```zig
dvui.themeSet(dvui.Theme.builtin.shadcn);
```

---

## Text & Fonts (`src/text/`)

### Font System (`font.zig`)

- Supports **FreeType** (native) and **stb_truetype** (WASM)
- Font caching with size-specific entries
- Glyph atlas generation

```zig
dvui.addFont("CustomFont", ttf_bytes, null);
const font = Font{ .id = .fromName("CustomFont"), .size = 16 };
```

### Text Selection (`selection.zig`)

Utilities for text cursor positioning and selection ranges.

---

## Accessibility (`src/accessibility/`)

Integration with **AccessKit** for screen reader support:

- Widgets declare roles via `Options.role`
- AccessKit tree built during frame
- Platform-specific accessibility APIs bridged

```zig
.options = .{ .role = .button },
```

---

## Memory Management

### Allocator Hierarchy

| Allocator | Lifetime | Usage |
|-----------|----------|-------|
| `gpa` | Application | Long-lived data (caches, stores) |
| `arena` | Frame | Temporary frame data |
| `_widget_stack` | Frame | Widget allocations |

### Pattern

```zig
// Frame arena - reset each frame
const arena = window.arena();

// Persistent storage
window.gpa.create(T);

// Widget allocation (auto-freed)
const widget = dvui.widgetAlloc(WidgetType);
defer dvui.widgetFree(widget);
```

---

## Key Files Reference

| Path | Purpose |
|------|---------|
| `dvui.zig` | Public API surface |
| `window/window.zig` | Frame loop, state management |
| `window/event.zig` | Event types and handling |
| `widgets/widget.zig` | Widget interface (vtable) |
| `widgets/widget_data.zig` | Common widget state |
| `core/options.zig` | Widget configuration |
| `core/rect.zig` | Rectangle math |
| `core/color.zig` | Color representation |
| `render/render.zig` | Render command API |
| `render/triangles.zig` | Geometry generation |
| `retained/mod.zig` | Retained-mode entry point |
| `retained/core/types.zig` | Node definitions |
| `retained/style/tailwind.zig` | CSS class parsing |

---

## Getting Started

1. **Create a Window** with your backend
2. **Frame loop**: `begin()` -> build widgets -> `end()`
3. **Use high-level functions** (`dvui.button()`, etc.) for simple cases
4. **Create custom widgets** by composing existing ones or implementing the Widget interface

```zig
const dvui = @import("dvui");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var backend = try Backend.init(.{});
    var window = try dvui.Window.init(@src(), gpa.allocator(), backend, .{});
    
    while (backend.running()) {
        window.begin();
        
        if (dvui.button("Click me", .{})) {
            // Handle click
        }
        
        window.end();
    }
}
```
