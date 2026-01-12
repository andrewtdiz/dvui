# Architecture

## Overview
This repository implements DVUI, a Zig GUI toolkit with multiple rendering backends, a core runtime built around a per-window state machine, and optional native/JS integrations. The project is split between:

- `src/`: the Zig runtime, widgets, rendering, backends, and native integrations.
- `frontend/`: a SolidJS universal renderer host with Bun FFI bindings for the native renderer and a minimal DVUI core FFI.

At runtime, UI construction happens between `Window.begin()` and `Window.end()`, with rendering routed through a backend implementation. For JS-driven UI, a native renderer hosts a Solid-like node tree and uses a ring buffer to dispatch events back to JS.

## Core Runtime (Zig)
### Public API Surface
- `src/dvui.zig` is the top-level module exporting all core types and functions. It also owns the global `current_window` pointer used during frame construction.
- `dvui.App` (`src/window/app.zig`) provides an application loop interface that integrates with backend `main/panic/logFn` when available.

### Global Window Context
- `dvui.current_window` is a global pointer set by `Window.begin()` and cleared/restored by `Window.end()`.
- Many top-level helpers (rendering, theme access, caching, input queries) route through `dvui.currentWindow()`.

### Window State
`src/window/window.zig` defines the central `Window` struct. It owns:
- Backend instance and per-frame timing.
- Event queue and focus/capture state.
- Layout state, subwindows, drag state, and debug overlays.
- Caches and persistent state: `Data` store, fonts, textures, animations, tags, dialog queues.
- Allocators: a general allocator (`gpa`) plus an arena, a LIFO arena, and a widget stack allocator.

This window state is reset per frame (arenas, caches, layout state) while long-lived structures stay in the `gpa` allocator. The window lifecycle is explicit: `init()` -> `begin()`/`end()` per frame -> `deinit()`.

### Core Data Model
- Geometry and primitives live in `src/core/`: `Point`, `Size`, `Rect`, `Color`, `Vertex`.
- `Options` (`src/core/options.zig`) carries layout and styling knobs used by widgets.
- `WidgetData` (`src/widgets/widget_data.zig`) is the per-widget record: ID, rect, min-size, options, scale, and debug/accessibility metadata.
- `Widget` (`src/widgets/widget.zig`) is a vtable-backed interface that allows parent widgets to measure and place children.
- `Data` (`src/core/data.zig`) is an ID-keyed store for persistent widget data and slices, with type validation in debug builds.

### Events
- `Event` (`src/window/event.zig`) encapsulates mouse/key/text events and a handled flag.
- `Window` accumulates events each frame, handles focus/capture, and exposes helpers to mark events as handled.

## Layout
- `BasicLayout` (`src/layout/layout.zig`) provides vertical/horizontal stacking, handling expansion, gravity, and min-size aggregation.
- Alignment helpers and `placeOnScreen` handle common positioning behaviors.
- Subwindows (`src/window/subwindows.zig`, referenced by Window) allow floating layers and render ordering.

## Rendering
- `src/render/` owns rendering primitives: triangles, paths, textures, text rendering, and render command deferral.
- `RenderCommand` (`src/render/render.zig`) enables deferring draw calls (e.g., floating windows that must render above later widgets).
- `Texture.Cache` (`src/render/texture.zig`) keeps GPU textures alive across frames and cleans them via explicit `reset()`/`deinit()`.

## Backend Abstraction
`src/backends/backend.zig` defines a uniform backend interface:
- Frame lifecycle (`begin`, `end`).
- Window sizing, content scale, and timing.
- Rendering of triangles with optional clipping.
- Texture creation/update/target rendering.
- Clipboard and URL helpers.

Implementations live under `src/backends/` (raylib, web, dx11, wgpu, testing). The concrete backend is provided at build time and imported as `@import("backend")`.

## Memory and Allocators
- The runtime uses a layered allocator strategy:
  - `gpa` for long-lived state (Window, caches, widget data, hash maps).
  - Per-frame `ArenaAllocator` for transient allocations (`Window.arena`).
  - Per-frame LIFO arena for short-lived buffers (`Window.lifo`).
  - Widget stack allocator for widget instances that are freed in a LIFO order.
- `src/utils/alloc.zig` provides a global allocator helper for non-window contexts.

All ownership is explicit: modules expose `init()`/`deinit()` functions and the owning struct frees its children or nested resources.

## Solid Integration (Zig)
The Solid integration is a data-oriented tree renderer that maps JS-driven nodes to DVUI draws:

- `src/integrations/solid/core/types.zig`
  - `SolidNode`: node tree entry with layout, paint cache, visual/transform props, listeners, and input state.
  - `NodeStore`: hash map of nodes with version tracking for dirty propagation.
- `src/integrations/solid/layout/`: computes layout from a Tailwind-like class spec.
- `src/integrations/solid/render/`: renders nodes using DVUI primitives and maintains paint caches/dirty regions.
- `src/integrations/solid/events/`: ring buffer for JS-bound events (`EventRing`).
- `src/integrations/solid/style/`: parses Tailwind-like classes into layout/visual settings.

The Solid renderer updates layout when the window size/scale changes or when dirty flags propagate through the tree.

## Retained Solid Module (Zig)
The retained module mirrors the engine Solid runtime in a standalone DVUI package:

- `src/retained/mod.zig`: retained entry point that re-exports submodules.
- `src/retained/core/`: node store, tree state, and retained types from `src/engine/render/ui-solid/core/`.
- `src/retained/layout/`: Yoga-based layout from `src/engine/render/ui-solid/layout/`.
- `src/retained/style/`: class parsing and style translation from `src/engine/render/ui-solid/style/`.
- `src/retained/render/`: retained rendering pipeline from `src/engine/render/ui-solid/render/`.
- `src/retained/events/`: event ring and input handling from `src/engine/render/ui-solid/events/`.

Retained modules must depend only on `std`, `dvui`, and `yoga`, with no engine-specific imports.

## Native Renderer (Zig)
`src/integrations/native_renderer/` provides a Bun FFI-friendly renderer process:

- `Renderer` (`types.zig`) owns:
  - a `dvui.Window`, backend instance (Raylib), and allocator/arenas.
  - command buffers (headers + payload) for simple quad/text drawing.
  - optional Solid `NodeStore` and event ring.
- `window.zig` drives the frame loop: begin DVUI frame, render Solid if available, otherwise render command buffers, then present.
- `solid_sync.zig` rebuilds the Solid tree from JSON snapshots or incremental ops from JS.
- `events.zig` pushes UI events into the ring buffer for JS polling.

This path is intended for JS-driven UIs while reusing DVUI’s rendering backend and input/event processing.

## DVUI Core FFI (Zig)
`src/core/ffi.zig` defines a minimal, C ABI-safe interface:
- `dvui_core_init` / `deinit` to create a window and backend (raylib for now).
- `begin_frame` / `end_frame` to bracket rendering.
- `pointer`, `wheel`, `key`, `text` event injection.
- `commit` to render a compact command buffer (quads and text).

This path is simpler than the native renderer and is used by the `frontend` core-renderer adapter.

## Frontend (TypeScript / Solid)
The `frontend/` package provides a Solid universal host and FFI bindings:

### Host Nodes and Runtime
- `frontend/solid/host/node.ts` defines `HostNode`, a lightweight DOM-like node with props and event listeners.
- `frontend/solid/runtime/` implements the Solid universal renderer runtime (create/insert/remove/setProperty) using host nodes.
- `frontend/solid/host/index.ts` wires Solid’s universal renderer to a `RendererAdapter` and manages mutation queues.

### Flush + Mutation Pipeline
- `frontend/solid/host/flush.ts` generates:
  - command buffers (quads/text) for the native renderer core path.
  - Solid tree snapshots or incremental mutation ops for the native renderer’s Solid store.
- `frontend/solid/host/mutation-queue.ts` tracks ops; `snapshot.ts` serializes the tree.

### FFI Adapters
- `frontend/solid/native/adapter.ts` is the main Bun FFI binding to the native renderer shared library.
- `frontend/solid/native/encoder.ts` encodes compact command buffers (header + payload).
- `frontend/solid/native/dvui-core.ts` + `core-renderer.ts` bind to the minimal DVUI core FFI interface.

### Event Flow (JS)
The adapter polls the native event ring and dispatches events to `HostNode` listeners. Payloads are small binary blobs; node IDs map events back to handlers.

## Typical Runtime Flows
### 1) DVUI App (Zig)
1. Backend init.
2. `Window.begin()` sets `dvui.current_window`, clears frame state, and resets caches.
3. App constructs widgets; each widget registers `WidgetData` and emits render calls.
4. `Window.end()` flushes deferred commands and backend `end()` presents.

### 2) Solid UI via Native Renderer (JS -> Zig)
1. Solid universal runtime builds/updates a `HostNode` tree.
2. Flush builds either:
   - a full tree snapshot, or
   - incremental ops (create/move/set_class/set_visual/etc.).
3. Native renderer updates `NodeStore` and renders via Solid integration.
4. UI events are pushed into the ring buffer and polled back in JS.

### 3) Command Buffer Rendering (JS -> Zig)
1. JS encodes quad/text commands via `CommandEncoder`.
2. Native renderer or core FFI ingests the command buffer and renders with DVUI primitives.

## Key Directories
- `src/core/`: primitives, options, data store, FFI entrypoints.
- `src/window/`: Window/App runtime, events, subwindows, dragging.
- `src/render/`: rendering primitives and texture caching.
- `src/backends/`: backend interface + implementations.
- `src/integrations/solid/`: Solid node tree, layout, render, style parsing.
- `src/integrations/native_renderer/`: Bun FFI-native renderer implementation.
- `frontend/solid/`: Solid universal host + native bindings.

## Ownership and Lifecycle Summary
- All major structs (`Window`, `NodeStore`, `Renderer`, caches) provide `init()`/`deinit()` with explicit ownership.
- Parents own and free nested resources (Window owns caches, fonts, dialogs, and data stores).
- Per-frame memory is reclaimed by resetting arenas; long-lived allocations are in `gpa` and freed on `deinit()`.
