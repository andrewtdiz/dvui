# Retained Mode Renderer

This directory implements the rendering engine for the retained mode GUI system. It transforms the high-level object graph (`SolidNode` tree) into low-level drawing commands and manages the visual lifecycle of the application.

## Key Responsibilities

1.  **Frame Orchestration**: The `render()` function in `mod.zig` is the heart of the system. It coordinates:
    -   Layout updates.
    -   Input handling (hit testing, drag & drop, focus).
    -   Overlay and portal management.
    -   Dirty region tracking and render caching.
    -   Recursive rendering of the node tree.

2.  **Rendering Strategies**:
    -   **Direct Rendering** (`direct.zig`): Immediate drawing of primitives (rectangles, text, triangles) for simple or non-interactive elements.
    -   **Cached Rendering** (`cache.zig`): Caches the geometry of static subtrees to optimize performance, invalidating only when bounds or styles change.
    -   **Widget Delegation**: Interactive elements (buttons, inputs, sliders) are often delegated to the underlying immediate-mode library (DVUI) to leverage its robust input handling, while strictly controlling their layout and styling.

3.  **Visual Effects & Styling**:
    -   **Transitions** (`transitions.zig`): Handles smooth animations for layout changes, transforms, and property updates (color, opacity).
    -   **Styling**: Applies Tailwind-like class specifications to visual properties, handling state changes like hover (`internal/derive.zig`).

4.  **Resource Management**:
    -   **Images** (`image_loader.zig`): Loading and caching of raster images.
    -   **Icons** (`icon_registry.zig`): Loading and resolving of vector (SVG/TVG) and raster icons.

## Directory Structure

### Core Modules

-   **`mod.zig`**: The public API and main render loop. Initializes/deinitializes subsystems and drives the frame.
-   **`cache.zig`**: Implements the `DirtyRegionTracker` and logic for caching node geometry.
-   **`direct.zig`**: Wrappers around low-level drawing commands.
-   **`transitions.zig`**: Animation engine for node properties.
-   **`icon_registry.zig`** & **`image_loader.zig`**: Asset management systems.

### Internal Implementation (`internal/`)

The `internal` directory contains the heavy lifting of the rendering logic. See `internal/SUMMARY.md` for details, but briefly:

-   **`renderers.zig`**: Specialized render functions for specific element types (`div`, `button`, `text`, etc.).
-   **`interaction.zig`**: Hit testing logic and input event routing.
-   **`overlay.zig`**: Manages z-index sorting, portals, and modal layers.
-   **`runtime.zig`** & **`state.zig`**: Manages frame-global state and rendering contexts (transforms, clips).
