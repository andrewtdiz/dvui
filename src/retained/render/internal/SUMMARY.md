# Retained Mode Render Internals

This directory contains the internal implementation details of the retained mode renderer. It bridges the high-level retained object model (`SolidNode`) with the immediate mode backend (DVUI) and handles low-level interaction, state management, and visual synchronization.

## File Overview

### Core Logic

- **`renderers.zig`**
  The central dispatch point for rendering. It contains specific rendering logic for all supported element types (`div`, `button`, `input`, `text`, `image`, etc.). It orchestrates the recursive rendering process, managing the context stack (transforms, clipping) and delegating to specialized render functions.

- **`runtime.zig`**
  Defines the `RenderRuntime` struct, which maintains frame-lifecycle state. This includes:
  - Current render layer (Base vs. Overlay).
  - Pointer interaction targets and input state.
  - Caches for portals, hover states, and overlays.

- **`state.zig`**
  Defines shared data structures and utility functions used across the rendering pipeline:
  - `RenderContext`: Propagates layout transforms (scale, offset) and clipping rectangles down the tree.
  - `RenderLayer`: Enum distinguishing between the base document and the overlay layer.
  - Geometric utilities for coordinate transformation and intersection.

### Interaction & Input

- **`interaction.zig`**
  Handles user input logic:
  - **Hit Testing:** `pickInteractiveId` and `scanPickInteractive` determine which node is under the cursor.
  - **Click Handling:** `clickedTopmost` manages click detection, focus, and mouse capture.
  - **Scrolling:** `handleScrollInput` and `renderScrollBars` implement custom scrolling logic for containers.

- **`hover.zig`**
  Manages the hover state machine. `syncHoverPath` traverses the node hierarchy to update `hovered` flags, triggering `mouseenter` and `mouseleave` events as appropriate, and updating the cursor style.

### Overlay & Portals

- **`overlay.zig`**
  Manages the rendering of elements that float above the normal document flow (e.g., modals, tooltips, portals).
  - Caches portal nodes for efficient access.
  - Computes the interactive area of the overlay layer to block input to the base layer when modals are active.
  - Renders portal nodes sorted by Z-index.

### Visuals & Styling

- **`derive.zig`**
  Responsible for applying CSS-like class specifications to visual properties. It prepares the `tailwind.Spec` for a node, applies hover modifiers, and sets up scroll state flags.

- **`visual_sync.zig`**
  Provides helper functions to synchronize state from `SolidNode` to DVUI's immediate mode widgets:
  - `applyLayoutScaleToOptions`: Adapts widget sizing and spacing based on layout scaling factors.
  - `applyAccessibilityState`: Maps accessibility properties (ARIA roles, labels, states) to AccessKit nodes.
