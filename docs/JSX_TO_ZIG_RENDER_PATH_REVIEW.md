# Review: JSX → Zig Render Path Architecture

This note evaluates the architecture described in `docs/JSX_TO_ZIG_RENDER_PATH.md` for building a JSX‑to‑native UI rendering runtime.

## High‑level assessment

At a high level, the proposed pipeline is the right shape for a Solid/JSX → native renderer:

- Solid compiled in `universal` mode emits host ops rather than DOM calls.
- A custom JS runtime creates a retained `HostNode` tree and queues mutations.
- Flush sends a full snapshot for initial sync and incremental ops thereafter over FFI.
- Zig reconstructs a `NodeStore` of `SolidNode`s.
- Zig render walks the store, maps tags/styles to DVUI widgets, and draws.
- Events are pushed into a ring buffer and polled by JS to invoke handlers.

This mirrors established patterns in Solid Native / React Native‑style renderers.

## Risks / gaps (with MVP priority)

1. **FFI protocol cost**
   - The boundary currently uses JSON `stringify`/`parse` for snapshots and ops.
   - **MVP note:** acceptable for a minimum‑viable prototype *if* full snapshots are rare and ops stay small.
   - Will dominate runtime cost for medium/large trees; plan to move to a binary op stream (or shared memory) for scaling.

2. **Work per frame on JS side**
   - `flush()` appears to traverse/serialize the whole tree every frame.
   - **MVP:** must fix. After first successful sync, switch to ops‑only flush: touch only dirty nodes and avoid re‑encoding unaffected subtrees.
   - Keep snapshot fallback for mismatch or when mutations aren’t supported.

3. **Dirty tracking / caching on Zig side**
   - `updateLayouts()` and Tailwind class parsing each frame for all nodes is expensive.
   - **MVP:** cache parsed Tailwind `ClassSpec` per `className` and recompute only when style‑affecting props change.
   - Fine‑grained layout/paint dirtiness can wait until after MVP if node counts are small.

4. **Retained store + immediate DVUI**
   - This combo is valid and common, but relies on stable widget IDs (`id_extra`) and clear state boundaries.
   - **MVP:** keep `NodeStore` purely declarative and widget IDs stable; otherwise you’ll get correctness bugs.

5. **Event model robustness**
   - Ring‑buffer polling is fine but needs:
     - overflow/drop strategy and backpressure reporting;
     - memory fences or single‑thread guarantees if JS/Zig can run concurrently;
     - richer event payloads (pointer coords/buttons, scroll, key/text input, focus/blur).
   - **MVP:** implement only the payloads you need for the prototype (likely pointer + basic keyboard). Overflow/backpressure and fencing can defer if you stay single‑threaded and event volume is low.

6. **Lifecycle and memory ownership**
   - Ensure `NodeStore`, per‑node `children` lists, and `listeners` maps have explicit `init()`/`deinit()` and clear allocator ownership.
   - **MVP:** avoid per‑frame leaks and unbounded allocations. Use allocator layering:
     - long‑lived allocator for the store/tree;
     - per‑frame arena for layout/paint caches and temporary strings (reset each frame).

## Minimum‑viable prototype priorities (Lua‑level perf)

Target: a game‑engine prototype with roughly Lua‑level runtime performance. That bar tolerates some overhead, but not “full tree work every frame”.

**Must‑fix for MVP**
- Ops‑only flush after first sync (JS dirty tracking; no per‑frame snapshots).
- Keep JSON for now but ensure ops are small and incremental.
- Cache Tailwind/class parsing on Zig side (`className → ClassSpec`).
- Ensure per‑frame temps use arenas and are reset; no unbounded allocations/leaks.

**Can defer until after MVP**
- Replace JSON with a binary/shared‑memory protocol.
- Deep layout/paint dirty propagation and other micro‑optimizations.
- Full event payload richness, overflow/backpressure, and cross‑thread fencing (unless you add multithreading).

## Suggested next steps (minimal‑change path)

- Add dirty flags to `HostNode` and make `flush()` ops‑only after first sync.
- Add a Zig `className → ClassSpec` cache and only re‑apply on change.
- Audit per‑frame allocations and move temps to a resettable arena.
- After MVP: define a compact binary ops format for `applyOps` / `commit`, then deepen dirty propagation and event payloads as needed.
