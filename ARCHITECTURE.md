# Architecture

## Overview
DVUI is an immediate-mode GUI toolkit written in Zig. It ships with multiple native backends (raylib, dx11, wgpu, web, testing), a retained-mode tree for data-driven rendering, and a SolidJS frontend that drives a native renderer over FFI. The repo is split into Zig core (`src/`) and a TypeScript frontend (`frontend/`), with glue code that keeps both sides in sync.

## High-level flow

### Immediate-mode (pure Zig)
1. Application code imports `src/dvui.zig` and calls widget helpers each frame.
2. `window.Window` owns per-frame state, event processing, and render submission.
3. Widgets resolve layout, produce render commands, and hand them to the backend.
4. The chosen backend (raylib/dx11/wgpu/web) draws the frame and reports input events back.

### Retained-mode (Solid + native renderer)
1. Solid universal runtime creates a HostNode tree in JS (no DOM).
2. The host flush builds command buffers and optional snapshot/ops payloads.
3. `frontend/solid/native/ffi.ts` calls into the `native_renderer` dynamic library.
4. `src/integrations/native_renderer` decodes commands, updates the retained `NodeStore`, runs layout, renders, and emits events through a ring buffer.
5. The frontend polls the ring buffer and dispatches events to Solid listeners.

## Repository layout

- `src/` (aka @src)
  - `dvui.zig`: Public API surface and top-level re-exports. This is the main entry point for Zig users.
  - `core/`: Fundamental types (Point, Rect, Color, Options, enums) used everywhere.
  - `window/`: App and Window lifecycle, event handling, cursor state, debug helpers.
  - `layout/`: Layout primitives, alignment, scroll info, easing.
  - `render/`: Render commands, paths, textures, image encoders.
  - `text/`: Fonts, text layout, selection helpers.
  - `widgets/`: Immediate-mode widget implementations used by the high-level API.
  - `theming/`: Theme definitions and presets.
  - `backends/`: Platform render backends (raylib, dx11, wgpu, web, testing).
  - `platform/`: OS integration (dialogs, io, compatibility helpers).
  - `accessibility/`: AccessKit integration for assistive tech.
  - `retained/`: Retained-mode tree, layout, render, and event ring.
  - `integrations/solid/`: Lightweight Zig entry points used by the Solid integration.
  - `integrations/native_renderer/`: FFI boundary and native renderer implementation.
  - `testing/`, `utils/`, `fonts/`: Test helpers, utilities, bundled fonts.

- `frontend/` (aka @frontend)
  - `index.ts`: Demo runner that owns the render loop and event polling.
  - `solid/`
    - `host/`: Host tree, mutation queue, and flush logic.
    - `runtime/`: Solid universal runtime bindings (`createElement`, `insert`, etc.).
    - `native/`: FFI adapter, command encoder, opcode schema, core renderer.
    - `util/`, `state/`: Frame scheduling and demo state helpers.
    - `solid-entry.tsx`: Example Solid app wiring.
  - `scripts/`: Build pipeline for Solid universal transform.
  - `dist/`: Bundled output.

- `build.zig` / `build.zig.zon`: Zig build graph and dependencies.
- `docs/`: Internal design notes and render path deep dives.

## Key build artifacts
- `dvui` module: Main Zig library entry point (`src/dvui.zig`).
- `native_renderer` dynamic library: Built from `src/integrations/native_renderer` for the frontend.
- `raylib-ontop` example: `src/raylib-ontop-zig.zig` wired in `build.zig`.
- `retained-harness`: A snapshot playback tool for retained rendering.

## Extension points
- Add a new widget: implement under `src/widgets/`, then expose a helper in `src/dvui.zig` if it should be public.
- Add a backend: implement in `src/backends/` and plumb through `backends/mod.zig`.
- Add Solid feature:
  - Update the command schema/encoder in `frontend/solid/native/`.
  - Mirror changes in `src/integrations/native_renderer/commands.zig` or retained render logic.
  - Keep snapshot/ops handling in sync between JS and Zig.

## State and memory expectations
- Core state lives in `window.Window` and retained `NodeStore` (explicit `init`/`deinit`).
- Allocators are passed in explicitly; subsystems own and clean up what they allocate.
- Backend and FFI lifecycles are explicit (create, resize, present, destroy).
