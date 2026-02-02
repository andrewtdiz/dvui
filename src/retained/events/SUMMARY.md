# Retained Mode Events Subsystem

This directory contains the event handling infrastructure for the retained mode UI system. It manages event queuing, focus navigation, and drag-and-drop interactions.

## Files

### `mod.zig`
**Core Event Infrastructure**
- Defines the `EventKind` enum listing all supported event types (click, input, focus, drag, etc.).
- Defines `EventEntry` and payload structures (`ScrollPayload`, `PointerPayload`) for efficient event storage.
- Implements the `EventRing` struct, a ring buffer that:
  - Queues events and their variable-length details (strings, payloads).
  - Handles the producer-consumer cycle between the UI logic and the application backend.
  - Tracks dropped events and buffer capacity.

### `focus.zig`
**Focus Management & Keyboard Navigation**
- Manages the global `FocusState`, tracking the currently focused node and widget.
- Implements `TabIndexInfo` and logic for calculating effective tab indices.
- Handles **Focus Traps**: Restricts tab navigation within a specific node hierarchy (e.g., for modals).
- Handles **Roving Focus**: Manages keyboard navigation (arrow keys) within composite widgets (like lists or grids) where the "active" item changes but the container holds focus context.
- Processes key events (Tab, Arrows) to move focus between interactive elements.
- Dispatches `focus`, `blur`, `keydown`, and `keyup` events.

### `drag_drop.zig`
**Drag and Drop Interaction**
- Manages `DragState` (active status, source ID, start position, hover target).
- Implements the drag lifecycle:
  - **Initiation:** Detects drag start from mouse interactions.
  - **Motion:** Updates hover targets as the pointer moves, handling `dragenter` and `dragleave` dispatching.
  - **Termination:** Handles `drop` and `dragend` events.
- Provides `cancelIfMissing` to clean up state if the source node disappears.
- Implements hit-testing (`scanNode`) to find valid drop targets based on geometry and z-index.
