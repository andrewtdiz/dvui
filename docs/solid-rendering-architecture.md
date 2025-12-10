# Solid → DVUI render pipeline (high level)

This summarizes how the current Solid sample (`frontend/solid/solid-entry.tsx`) reaches the DVUI layer through the Bun FFI and Zig backend.

## Flow overview

- Solid view code (`frontend/solid/solid-entry.tsx`) renders into a custom host created by `createSolidNativeHost` (`frontend/solid/solid-host.tsx`).
- The host builds an in-memory tree of `HostNode`s and, on flush, both:
  - Encodes draw commands (quads/text) via `CommandEncoder` (`frontend/solid/native-renderer.ts`), then `native.commit(...)`.
  - Serializes the logical tree to JSON and calls `native.setSolidTree(...)` so Zig can rebuild its `NodeStore`.
- The Bun FFI in `native-renderer.ts` loads the native library and forwards `commit`, `present`, `resize`, `setSolidTree`, etc. into Zig.
- On the Zig side, `native_renderer.zig` receives:
  - `setRendererSolidTree` → `rebuildSolidStoreFromJson` repopulates the Solid `NodeStore`.
  - `commitCommands` buffers draw commands (fallback path if no Solid tree).
  - `presentRenderer` drives a frame: opens the window if needed, then either `solid_renderer.render` (preferred) or `renderCommandsDvui` (command-buffer fallback).
- `solid_renderer.zig` walks the `NodeStore`, maps tags to DVUI widgets, applies Tailwind-derived options, and renders via DVUI.

## Key files and responsibilities

- `frontend/solid/solid-entry.tsx`: Example Solid tree that is rendered into the native host.
- `frontend/solid/solid-host.tsx`:
  - Defines `HostNode` and the Solid custom renderer.
  - `flush()` serializes nodes (`serialize`) and emits commands (`emitNode`), then calls `native.setSolidTree` and `native.commit`.
- `frontend/solid/native-renderer.ts`:
  - Bun FFI bridge. `NativeRenderer.commit`, `present`, `resize`, `setSolidTree` forward to the native symbols.
  - `CommandEncoder.pushQuad/pushText/finalize` build the command buffers.
- `src/native_renderer.zig` (exports):
  - `setRendererSolidTree` → `rebuildSolidStoreFromJson` constructs `NodeStore` from the JSON sent by Solid.
  - `commitCommands` stores raw command headers/payload.
  - `presentRenderer` → `renderFrame` selects Solid path or command-buffer path.
  - Window setup happens in `ensureWindow`; per-frame rendering in `renderFrame`.
- `src/solid_renderer.zig`:
  - Traverses `NodeStore` and renders DVUI widgets. Tag handlers include `renderContainer`, `renderButton`, `renderInput`, `renderImage`, `renderParagraph`, `renderText`, etc.
  - Text nodes: `renderText`; paragraphs/headings: `renderParagraph`.
  - Uses `tailwind_dvui.applyToOptions` (`src/jsruntime/solid/dvui_tailwind.zig`) to translate Tailwind-ish classes.
- `src/jsruntime/solid/types.zig`: `NodeStore` and `SolidNode` definitions; tracks class names, text, children, listeners, and dirty state.
- `src/jsruntime/solid/tailwind.zig`: Parses class strings into a `Spec` and applies to `dvui.Options`.

## Render path specifics

1. **JS → FFI:** `host.flush()` → `CommandEncoder.finalize()` → `native.commit(...)` and `native.setSolidTree(...)`.
2. **FFI → Zig store:** `setRendererSolidTree` rebuilds `NodeStore` from the serialized nodes (tags, text, className, parent links).
3. **Frame:** `presentRenderer` calls `renderFrame`; if `solid_store_ready`, `solid_renderer.render(null, &solid_store)` builds DVUI widgets.
4. **DVUI:** Tag-specific functions emit DVUI primitives; Tailwind specs map to size/color/flex/padding via `tailwind_dvui`.

## Notes

- The Solid tree/JSON path is the primary one; the command-buffer path (`renderCommandsDvui`) is a fallback when no Solid store is ready.
- Class support is limited to the Tailwind subset parsed in `src/jsruntime/solid/tailwind.zig`.



