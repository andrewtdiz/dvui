# Retained Mode UI

The `retained` directory implements a retained-mode UI system on top of the immediate-mode `dvui` library. Unlike immediate mode, where the UI is rebuilt every frame, this system maintains a persistent tree of stateful nodes (`SolidNode`), allowing for efficient updates, complex layouts (Flexbox), CSS-inspired styling (Tailwind), and smooth animations.

## Modules

### Core (`core/`)
Defines the fundamental data structures and state management for the system.
- **Node Graph**: Managed by `NodeStore`, where each `SolidNode` represents a UI element.
- **State**: Handles persistent state like scroll offsets, input text, and animations.
- **Geometry**: Defines primitives like `Rect`, `Size`, and `Transform`.

### Events (`events/`)
Manages user interaction and the event loop.
- **Event Ring**: A ring buffer (`EventRing`) that queues events (clicks, input, focus) for processing.
- **Focus**: Handles keyboard navigation, focus traps (modals), and roving focus (grids/lists).
- **Drag & Drop**: Manages the lifecycle of drag interactions.

### Layout (`layout/`)
Responsible for positioning and sizing nodes.
- **Flexbox**: Implements a native Flexbox layout engine (`flex.zig`).
- **Measurement**: Calculates intrinsic sizes for text and elements (`measure.zig`).
- **Text Wrapping**: Handles line breaking and text layout.

### Render (`render/`)
Transforms the high-level node tree into low-level drawing commands.
- **Strategies**: Supports both direct rendering for simple shapes and caching for static subtrees.
- **Visuals**: Handles rendering of backgrounds, borders, images, and icons.
- **Transitions**: Implements a transition engine for smooth property animations.
- **Overlays**: Manages z-indexed layers for modals and popups.

### Style (`style/`)
Implements a Tailwind-CSS-inspired styling system.
- **Parser**: Parses string-based class names (e.g., `bg-red-500`, `p-4`, `flex`) into structured specifications.
- **Application**: Applies styles to `SolidNode` visual properties and `dvui` widgets.
- **Theming**: Integrates with the application's color palette and typography settings.
