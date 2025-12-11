# Solid TS Re-architecture (LLM-friendly)

Purpose: make the Solid/Bun side immediately legible to new contributors (and LLMs) by separating responsibilities, shrinking per-file scope, and aligning with `ARCHITECTURE_GOAL.md` and `SOLID_ARCHITECTURE.md`.

## Proposed Layers & Files
- **Native FFI boundary**  
  - `frontend/solid/native/ffi.ts`: dlopen logic, PATH setup, symbol table, callback wiring. No rendering concepts.  
  - `frontend/solid/native/encoder.ts`: `CommandEncoder` + command schema helpers.  
  - `frontend/solid/native/adapter.ts`: `RendererAdapter` implementation that wraps the FFI symbols, owns callbacks, `present/resize/applyOps/setSolidTree/pollEvents`.
- **Host tree & mutation pipeline**  
  - `frontend/solid/host/node.ts`: `HostNode`, `NodeProps`, event registration, DOM-like accessors. Pure data; no flushing.  
  - `frontend/solid/host/props.ts`: color packing, class parsing (bg lookup), transform/visual extractors.  
  - `frontend/solid/host/mutation-queue.ts`: mutation op types, enqueue helpers (`create/move/remove/set_text/set_class/set_transform/set_visual/listen`).  
  - `frontend/solid/host/snapshot.ts`: tree serialization to `SerializedNode[]` for full syncs.  
  - `frontend/solid/host/flush.ts`: mutation-mode state machine (snapshot vs mutations), listener resync, `commit` glue to the renderer adapter. Keeps scheduling and `queueMicrotask` in one place.  
  - `frontend/solid/host/index.ts`: `createSolidHost(renderer)` orchestrator that wires scheduler + node registry + event dispatch; exports `render`, `flushIfPending`, `getNodeIndex`.
- **Solid universal runtime adapter**  
  - `frontend/solid/runtime/bridge.ts`: `registerRuntimeBridge`, `notifyRuntimePropChange`, `registerRuntimeNode` typed against the host interface.  
  - `frontend/solid/runtime/universal.ts`: the exports Solid universal mode expects (`createElement`, `createTextNode`, `insertNode`, `setProperty`, etc.) implemented as thin delegations to the host controller. Eliminates duplication between `runtime.ts` and `solid-host.tsx`.  
  - `frontend/solid/runtime/index.ts`: re-export for the compiler (`moduleName: "#solid-runtime"`).
- **Entry/demo & integration**  
  - `frontend/solid/app/solid-entry.tsx`: keeps only demo UI composition; delegates all host/runtime setup to `createSolidApp(renderer)` from a tiny bootstrap module.  
  - `frontend/solid/components/*`: UI-only; no host/native logic.

## Key Cleanups
- Split `solid-host.tsx` into small modules (node model, prop helpers, mutation queue, snapshot/flush) so each file explains one concern.  
- Remove duplicated property/event handling by routing all universal runtime exports through the host controller; `setProperty` lives in one module.  
- Keep FFI noise isolated under `native/` so UI/runtime files never import `bun:ffi`.  
- Make the event bridge explicit: host owns `nodeIndex` and listener tracking; runtime only calls `registerRuntimeNode`/`notifyRuntimePropChange`.  
- Treat mutation mode state (snapshot vs mutations) as a tiny state machine with readable thresholds and comments in `host/flush.ts`.

## Suggested Migration Steps
1) Move FFI pieces from `native.ts`/`native-renderer.ts` into `native/ffi.ts` + `native/encoder.ts` + `native/adapter.ts`; update imports.  
2) Extract `HostNode` + prop helpers + mutation op types from `solid-host.tsx` into `host/*`.  
3) Rebuild `solid-host` as `host/index.ts` that wires scheduler + node registry + event dispatch, exporting the small surface needed by the demo and runtime bridge.  
4) Rewrite `runtime.ts` as `runtime/universal.ts` delegating to the host controller; keep bridge wiring in `runtime/bridge.ts`.  
5) Slim `solid-entry.tsx` to demo-only composition and a bootstrap that creates the renderer + host, then renders the Solid tree.  
6) Update docs to point at the new directories and the universal runtime entry (`#solid-runtime`).
