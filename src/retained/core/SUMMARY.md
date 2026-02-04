# Retained Core

This module implements the fundamental data structures and state management for the retained mode UI system. It centers around a node graph managed by a `NodeStore`, where each `SolidNode` represents a UI element with its associated state, style, and layout data.

## Key Components

### Node Management (`node_store.zig`)
- **`NodeStore`**: The central repository for all UI nodes. It maps `u32` IDs to `SolidNode` instances and handles tree operations (insertion, removal) and property updates. It uses a versioning system to track changes and minimize rendering work.
- **`SolidNode`**: A comprehensive structure representing a UI element. It aggregates:
  - **Hierarchy**: Parent and child relationships.
  - **State**: `InputState` (text editing), `ScrollState` (scrolling offsets), `TransitionState` (animations).
  - **Caches**: `LayoutCache` and `PaintCache` for performance.
  - **Properties**: Visual styles, event listeners, and accessibility data.

### Geometry & Types
- **`geometry.zig`**: Defines core geometric primitives like `Rect`, `Size`, `Transform`.
- **`visual.zig`**: Defines styling primitives including `PackedColor`, `Gradient`, and `VisualProps`.
- **`media.zig`**: Handles resources like icons (`IconKind`) and images (`CachedImage`).
- **`layout.zig`**: Defines the caching structures (`LayoutCache`, `PaintCache`) used to store the results of layout and rendering passes.

### API Facade
- **`types.zig`**: Re-exports all public types from the sub-modules, serving as the main import point for type definitions within the retained core.
