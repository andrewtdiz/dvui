# Retained Mode Architecture Analysis

## Overview

The `src/retained` module implements a **retained-mode UI system** on top of the `dvui` immediate-mode library. This hybrid approach combines the performance and statelessness of immediate mode for low-level drawing with the ease of use, state persistence, and complex layout capabilities of a retained object model.

It allows developers to build UIs declaratively using a persistent tree of nodes (`SolidNode`), styled with a Tailwind-CSS-inspired syntax, and laid out using Flexbox.

## Core Pillars

### 1. Retained Object Model (`core/`)
At the heart of the system is the **Node Graph**, managed by `NodeStore`.
- **`SolidNode`**: The fundamental unit of the UI. Unlike immediate mode widgets that exist only during a function call, a `SolidNode` persists across frames. It aggregates:
    - **Hierarchy**: Parent/child relationships.
    - **Data**: Text content, image sources, tags.
    - **State**: Persistent state for scrolling, text input, and animations.
    - **Caches**: Layout results (`rect`) and paint commands (`PaintCache`) to minimize re-computation.
- **`NodeStore`**: A central repository mapping `u32` IDs to `SolidNode` instances. It handles tree operations (insert, remove) and employs a **Versioning System** (`version`, `subtree_version`) to efficiently track dirty nodes and minimize traversal during layout and render passes.

### 2. Declarative Styling (`style/`)
The system uses a string-based, functional styling approach inspired by **Tailwind CSS**.
- **Parsing**: Class strings (e.g., `bg-slate-800 p-4 rounded-lg flex-row`) are parsed into structured `Spec` objects.
- **Caching**: The `SpecCache` avoids re-parsing common strings.
- **Application**: The `derive` module maps these specs to concrete `VisualProps` (colors, radii) on nodes or `dvui.Options` for leaf widgets.
- **Reactivity**: Styles support pseudo-classes like `hover:` and transitions, automatically updating visual properties in response to interaction state.

### 3. State Persistence
State is managed explicitly within the node graph, solving a common pain point of immediate-mode GUIs.
- **Input State**: `InputState` buffers text input, tracking cursor position and selection, decoupling the UI update loop from the typing speed.
- **Scroll State**: `ScrollState` persists scroll offsets (`offset_x`, `offset_y`) and content dimensions, enabling complex scrollable containers (`scrollframe`) independent of the immediate mode frame.
- **Animation State**: `TransitionState` tracks previous and current values for animatable properties (opacity, transform, color), allowing the render engine to interpolate frames automatically.

### 4. Layout Engine (`layout/`)
The system creates a distinct layout phase before rendering.
- **Flexbox**: The primary layout model is a native Zig implementation of Flexbox (`flex.zig`), supporting nested containers, alignment (`justify-center`, `items-end`), and flexible sizing (`grow`, `shrink`).
- **Text Layout**: A dedicated text engine (`text_wrap.zig`) handles word wrapping, line breaking, and sizing based on font metrics, caching results to avoid expensive re-measurement.
- **Phased Update**: `layout.updateLayouts()` is called at the start of the frame. It checks dirty flags and only re-computes parts of the tree that have changed or are affected by screen resizing.

### 5. Rendering Pipeline (`render/`)
The `render()` function orchestrates the frame, bridging the retained graph with the immediate-mode backend.
1.  **Layout**: Recalculates geometry if versions have changed.
2.  **Input & Hit Testing**: The `interaction` module performs hit testing to determine hovered nodes, active drag targets, and focus, respecting z-index and overlay layers.
3.  **Dirty Tracking**: A `DirtyRegionTracker` identifies screen regions that need repainting, optimizing performance.
4.  **Paint Dispatch**:
    -   **Container Nodes**: Rendered directly using `dvui` primitives (rects, borders).
    -   **Leaf Widgets**: Delegated to `dvui` widgets (e.g., `dvui.button`, `dvui.textEntry`). This "hybrid" approach leverages `dvui`'s robust native input handling while imposing the retained system's strict layout and styling.
    -   **Overlays**: Portals (modals, tooltips) are identified and rendered in a separate pass into a `dvui` subwindow, ensuring they float above the content and break out of clipping contexts.

## Animation System
Simple animations are built-in via the **Transitions** engine.
- **Implicit Transitions**: When a style property changes (e.g., `opacity` goes from 0 to 1), the system detects the delta in `TransitionState`.
- **Interpolation**: It automatically interpolates the value over a specified duration using an easing function.
- **Properties**: Supports layout (width/height), transforms (scale/translate), colors, and opacity.

## Summary
The architecture effectively decouples **logic** (node graph manipulation) from **presentation** (rendering). It provides a high-level, web-like development experience (components, CSS styling, flexbox) while maintaining the performance and portability of the underlying Zig-based immediate mode renderer.
