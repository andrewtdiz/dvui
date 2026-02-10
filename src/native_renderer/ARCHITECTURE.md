# Native Renderer (`native_renderer/`)

## Responsibility
Provides the FFI-facing native renderer runtime for DVUI. Owns window lifecycle (Raylib backend + WebGPU renderer), immediate-mode command-buffer rendering, and optional retained-mode UI driven by Luau via a retained `NodeStore`.

## Public Surface
- `src/native_renderer/mod.zig`: `Renderer`, `CommandHeader`, and the per-frame entrypoint `renderFrame(...)`.
- `src/native_renderer/lifecycle.zig`: renderer lifecycle helpers, logging, and event callbacks.
- `src/native_renderer/luau_ui.zig`: installs the global `ui` table used by Luau/SolidLuau to mutate retained state.

## High-Level Architecture
- `types.zig`: core ABI surface (`Renderer`, `CommandHeader`, callback types).
- `lifecycle.zig`: renderer creation/destruction, logging/event callbacks, and Luau VM lifecycle (script loading, `init/update/on_event` discovery, teardown on errors).
- `window.zig`: lazy window creation (`ensureWindow`) and the per-frame loop (`renderFrame`), including input polling, resize handling, DVUI begin/end, optional screenshots, retained event draining to Lua, Lua `update(dt, input_table)`, and rendering either retained UI or the command buffer.
- `commands.zig`: interprets `CommandHeader` + payload bytes and renders a small immediate-mode scene graph with absolute vs flow layout (`flag_absolute`); current opcodes include rectangle fill and text.
- `luau_ui.zig`: installs a global `ui` table in Luau that maps to retained `NodeStore` mutations (`create/remove/insert/patch/...`) and event subscription (`listen_kind`).
- `event_payload.zig`: parses packed pointer/drag payload bytes into Lua tables.
- `profiling.zig`: per-frame timing/profiling helpers.

## Core Data Model
- `types.Renderer`: long-lived runtime state (window state, command buffers, per-frame arena, lifecycle flags, retained store/event ring pointers, and Luau state).
- `types.CommandHeader` (`extern struct`): per-command metadata (opcode/flags, node ids, layout rect, payload slice, `extra`).
- `luau_ui.PropKey`: numeric keys for batched `ui.patch(id, key1, value1, ...)` updates.

## Critical Assumptions
- `window_ready` implies `backend`, `webgpu`, and `window` are initialized; `renderFrame` returns early otherwise.
- Command buffers must be internally consistent (payload ranges in-bounds; parent/child ids form a sane tree).
- Retained pointers are stored as `*anyopaque` and must remain valid while their corresponding `*_ready` flags are true.
- Lua integration is optional; Lua errors tear down the VM and disable Lua-driven retained UI.
- Destruction is deferred while inside callbacks (`callback_depth > 0`) to avoid invalidating in-flight FFI calls.
