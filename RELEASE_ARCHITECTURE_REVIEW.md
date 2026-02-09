# DVUI Release Architecture Review (2026-02-09)

## Scope And Method

Reviewed repository-tracked files (`rg --files`: 444). Deep-dive reviews were done for:

- `src/retained/` (retained UI core, layout, render, events)
- `src/native_renderer/` (Luau + retained integration, windowing, lifecycle)
- Remaining `src/` modules (render, core, widgets, etc)
- `luau/` and UI JSON tooling (`luau/ui/*`, `tools/ui_codegen.zig`)

Build verification:

- `./zig_build_simple.sh` succeeded on 2026-02-09.

Notes:

- Binary assets (fonts, images) were inventoried but are not meaningfully “code reviewed”.
- `deps/` was reviewed for integration risk only (no dependency changes made).

## Architecture Snapshot

This repo effectively contains two UI pipelines:

- Immediate-mode DVUI library (`src/dvui.zig` plus `src/widgets/`, `src/render/`, `src/window/`, `src/backends/`).
- Retained-mode renderer driven by Luau/SolidLuau, implemented on top of DVUI primitives (`src/retained/` + `src/native_renderer/` + `luau/`).

The retained pipeline, at a high level:

- Luau builds a tree of node tables, SolidLuau issues imperative `ui.*` calls into Zig (`src/native_renderer/luau_ui.zig`).
- Zig stores a retained node graph (`retained.NodeStore`) and renders it each frame via DVUI rendering primitives.
- A ring buffer transports input events from retained render to Luau handlers.

This hybrid architecture is viable, but it introduces sharp edges at boundaries:

- Lifetime and thread ownership at the native renderer API boundary.
- Data structure invariants for the retained tree (acyclic, no self-parenting).
- Contract alignment between UI JSON tooling, Luau “node shape”, and SolidLuau expectations.
- “Text must be valid UTF-8” assumptions are inconsistently enforced.

## Critical Findings (Release Blockers)

### C1: Native Renderer Destruction Is Not Safe Under Reentrancy Or Multi-Threading

Why it matters:

- If the host can call `destroyRendererImpl` while a frame is running (or while other native calls are in flight), the renderer can free its own allocators and state while still being used, causing use-after-free and hard crashes.

Evidence:

- `src/native_renderer/types.zig:39` includes `busy`, `pending_destroy`, `destroy_started`, `callback_depth` but `busy` is never set/cleared anywhere.
- `src/native_renderer/lifecycle.zig:1092` `tryFinalize` gates finalization on `pending_destroy`, `busy`, and `callback_depth`, but `busy` is effectively always `false`.
- `src/native_renderer/lifecycle.zig:1208` `destroyRendererImpl` sets `pending_destroy = true` and immediately calls `tryFinalize`.
- `src/native_renderer/window.zig:228` `renderFrame` does not guard against `pending_destroy` / `destroy_started` before touching `renderer.window`, `renderer.webgpu`, `renderer.backend`, arenas, etc.

Release risk:

- If this dynamic library is called from a multi-threaded host (typical for games/tools), this is a real crash-class issue.

Fix direction:

- Make the API explicitly single-threaded (and enforce it), or add real synchronization.
- At minimum: set `renderer.busy = true` at entry to every public entrypoint and clear on exit, and add an early return in `renderFrame` when `pending_destroy` or `destroy_started` is set.

### C2: `lua_entry_path` Lifetime Is Not Owned By The Renderer (FFI Dangling Pointer Risk)

Why it matters:

- `lua_entry_path` is stored as a slice in the renderer without copying. Any FFI caller that passes a temporary buffer can cause a dangling pointer later when Lua is loaded.

Evidence:

- `src/native_renderer/lifecycle.zig:1147` stores `.lua_entry_path = lua_entry_path` directly.
- That value is later used for script loading (via the Lua init path).

Release risk:

- Intermittent crashes or reading arbitrary paths depending on host memory reuse.

Fix direction:

- Copy `lua_entry_path` into renderer-owned memory at creation time and free it during renderer teardown, or enforce and document a strict ownership contract and validate it at the boundary.

### C3: UTF-8 Handling Can Still Panic In The Render Path

Why it matters:

- The render path contains `catch unreachable` when decoding UTF-8. Invalid input can panic and take down the entire process. This is especially risky because some widget code intentionally “falls back” to using non-UTF-8 data after a conversion error.

Evidence:

- `src/render/render.zig:140` converts `opts.text` to `utf8_text`.
- `src/render/render.zig:221` then iterates and decodes `opts.text` (not `utf8_text`) with `catch unreachable` (`src/render/render.zig:222` and `src/render/render.zig:223`).
- `src/widgets/LabelWidget.zig:68` falls back to the original `label_str` when `toUtf8` fails, then calls `textSize(label_str)` (`src/widgets/LabelWidget.zig:81`) which depends on the same text decode assumptions.

Release risk:

- Any invalid user text, bad input from file/network, or internal data corruption can become a crash.

Fix direction:

- Make `renderText` decode `utf8_text` (the validated slice) rather than `opts.text`.
- Remove `catch unreachable` on UTF-8 decode in rendering and measurement paths; use replacement characters or return an error consistently.

### C4: Retained Tree Can Be Made Cyclic (Infinite Recursion / Stack Overflow)

Why it matters:

- `NodeStore.insert` does not prevent inserting a node under itself or its descendants. A single cycle can cause infinite recursion or stack overflow in layout, render, hit-testing, and removal.

Evidence:

- `src/retained/core/node_store.zig:621` `insert` sets `child.parent = parent_id` and appends `child_id` to `parent.children` with no cycle check.
- Recursion-based walkers exist across retained (layout/render/hit-test). For example: `src/retained/layout/mod.zig:109` recursively invalidates layout subtrees; `src/retained/layout/mod.zig:386` recursively applies anchoring; `src/retained/render/internal/overlay.zig:50` recursively collects portal nodes.

Release risk:

- A malformed UI update (or a bug in the Luau renderer/adapter) can hang or crash the whole app.

Fix direction:

- Enforce the invariant at the mutation boundary: reject inserts where `parent_id` is `child_id` or in `child_id`’s subtree. Return an error and keep the tree unchanged.

### C5: Type Safety In The Core Data Store Is Debug-Only (Release Builds Allow Type Confusion)

Why it matters:

- `Data` stores untyped bytes keyed by `dvui.Id`. In Debug it panics on type mismatches, but in non-Debug builds those checks compile out, allowing silent type confusion and memory corruption.

Evidence:

- `src/core/data.zig:27` `SavedData.DebugInfo` is only present in Debug; otherwise it’s `void`.
- Type mismatch checks are gated behind `if (@TypeOf(debug) != void)` (`src/core/data.zig:158` and `src/core/data.zig:181`).

Release risk:

- A bug in widget state keying can become non-deterministic corruption rather than a loud crash in development.

Fix direction:

- Keep a minimal runtime type signature in all builds (size, alignment, stable type hash), or restructure the API so type is encoded into the key namespace and cannot collide.

## High Severity Findings

### H1: `NodeStore.node()` Returns Unstable Pointers (Hidden Lifetime Contract)

Why it matters:

- `NodeStore.node` returns a pointer into an `AutoHashMap`. Any subsequent mutation that triggers rehashing can invalidate previously returned pointers. The API makes it easy to cache node pointers across calls.

Evidence:

- `src/retained/core/node_store.zig:657` returns `self.nodes.getPtr(id)` directly.

Release risk:

- Use-after-free bugs in callers that store `*SolidNode` across inserts/removes/puts.

Fix direction:

- Return IDs or copies, or move storage to a stable arena/array and map IDs to stable indices. If keeping the pointer API, document and enforce “valid only until next mutation”.

### H2: Native Command Layout Recurses Without Cycle Detection

Why it matters:

- The fallback command renderer builds a parent/child graph from headers and recursively lays it out. A cycle (or very deep tree) can overflow the stack.

Evidence:

- `src/native_renderer/commands.zig:75` recursive `layoutNode.run` traverses `node.children` with no visited set or depth guard.

Release risk:

- If the command buffer can be malformed (input from a host), this is a crash/hang at the API boundary.

Fix direction:

- Add cycle detection (visited set keyed by `node_id`) and a max depth guard with a clear failure mode.

### H3: `renderTriangles` Mutates Input Geometry When Render Target Offset Is Non-Zero

Why it matters:

- Mutating `triangles.vertexes` in-place can corrupt cached geometry or surprise callers that reuse the same `Triangles` for multiple draws.

Evidence:

- `src/render/render.zig:103` applies `render_target.offset` by modifying each vertex position in `triangles.vertexes`.

Release risk:

- Hard-to-debug “drifting UI” or mis-rendering when the same triangles are reused.

Fix direction:

- Apply offsets in the backend, or draw from a temporary copy, or explicitly document/rename the API to make mutation unavoidable and obvious.

### H4: `Texture.updateImageSource` Panics On A Public Enum Variant

Why it matters:

- `ImageSource` includes `.texture`, and `fromImageSource` accepts it, but `updateImageSource` panics on `.texture`.

Evidence:

- `src/render/texture.zig:250` `updateImageSource` has `.texture => |_| @panic("this is not supported currently")` (`src/render/texture.zig:266`).

Release risk:

- User code can crash at runtime by passing a value that the type system appears to allow.

Fix direction:

- Return an error for `.texture` instead of panicking, or redesign the API to make unsupported variants unrepresentable.

### H5: UI JSON Tooling Conflicts With SolidLuau’s Node Contract (`props` Is Generated But Hard-Errors At Runtime)

Why it matters:

- The generator and loader accept a nested `props` object, but SolidLuau explicitly errors if `node.props` exists. Any JSON spec containing `props` is a guaranteed runtime failure.

Evidence:

- `tools/ui_codegen.zig:723` reads `props` into the generated node representation and emits it (`tools/ui_codegen.zig:805`, `tools/ui_codegen.zig:947`).
- `luau/ui/load_ui.luau:66` copies all keys except `children`, so `props` survives into `UINode`.
- `deps/solidluau/src/ui/renderer.luau:272` and `deps/solidluau/src/ui/hydrate.luau:73` hard-error when `props` is present.

Release risk:

- Generated UI JSON can crash immediately in production.

Fix direction:

- Decide the contract: if `props` is permanently removed, reject it in codegen and loader with an actionable error. If it is desired, SolidLuau must be updated (dependency change would require explicit approval).

### H6: UI JSON Child-Key Collisions Can Corrupt Runtime State

Why it matters:

- `load_ui` stores child nodes under `node[child_key]` for keyed children. If `child_key` collides with core node properties (`visual`, `transform`, `scroll`, `anchor`, `image`, `src`, `listen`), it overwrites those properties and breaks runtime behavior.

Evidence:

- `tools/ui_codegen.zig:596` reserved keys do not include `visual`, `transform`, `scroll`, `anchor`, `image`, `src`, `listen`.
- `luau/ui/load_ui.luau:92` assigns `node[child_key] = child`.

Release risk:

- Subtle, non-local corruption of nodes during loading; manifests later as type errors or missing styling/events.

Fix direction:

- Expand reserved key list in codegen validation to include all core props used by SolidLuau + adapter.
- Consider namespacing child references (e.g. `node.refs[child_key]`) rather than writing directly onto the node table.

### H7: Retained Overlay/Portal Subsystem Exists But Is Not Wired Into The Frame Render

Why it matters:

- There is substantial code for portal discovery, overlay state computation, modal overlays, and overlay rendering ordering, but the main render loop does not call it. This creates dead/incomplete architecture that will surprise maintainers and is risky if portals are expected for release features (dropdowns, modals, tooltips).

Evidence:

- Overlay pipeline entrypoints exist: `src/retained/render/internal/overlay.zig:21` `ensurePortalCache`, `src/retained/render/internal/overlay.zig:36` `ensureOverlayState`, `src/retained/render/internal/overlay.zig:147` `renderPortalNodesOrdered`.
- Frame render sets overlay-related runtime fields but does not compute or render overlay layers: `src/retained/render/mod.zig:69` to `src/retained/render/mod.zig:73`.
- Drag-drop has an explicit hit-test context for portals/overlays, but it is only set via `setHitTestContext` (`src/retained/events/drag_drop.zig:38`) and is not updated from the render loop.

Release risk:

- If portal tags are introduced in UI content, rendering and hit-testing behavior will not match intended stacking/modal semantics.

Fix direction:

- Either wire the overlay pipeline into `src/retained/render/mod.zig` (portal collection, overlay state, render base then overlay layer, update hit-test context), or remove/feature-flag it until it’s complete.

### H8: Docs And “Findings” Docs Are Out Of Sync With Current Code

Why it matters:

- Several docs in `docs/` present themselves as “current supported API”, but contain statements that do not match the implementation. This harms onboarding, increases integration bugs, and slows release stabilization.

Evidence:

- `docs/RETAINED_API.md:207` says anchor placement is “currently not applied”, but anchoring is applied in layout via `applyAnchoredPlacement` (`src/retained/layout/mod.zig:100`, `src/retained/layout/mod.zig:386`).
- `docs/luau-findings/*.md` record “High severity” issues that appear to be fixed in code:
  - Pointer/drag payloads are now decoded to Lua tables (`src/native_renderer/window.zig:184`, `src/native_renderer/event_payload.zig:6`).
  - Event ring saturation after Lua teardown is mitigated by passing `null` ring when Lua is down (`src/native_renderer/window.zig:389`).
  - Patch clear semantics for object props are implemented via explicit clear functions (`src/native_renderer/luau_ui.zig:215` onward).

Release risk:

- Teams will make incorrect assumptions about supported behaviors and contracts, wasting time and shipping mismatched UI content.

Fix direction:

- Update `docs/RETAINED_API.md` to reflect actual behavior and explicitly list what is implemented vs accepted-but-unused.
- Mark `docs/luau-findings/*.md` with a “Status: Resolved on <date/commit>” header or move them to an archive folder.

## Recommended Fix Order Before A Release

1. Fix native renderer destruction safety (C1) and clarify the threading model.
2. Fix `lua_entry_path` ownership (C2).
3. Fix UTF-8 crash paths (C3).
4. Add retained tree cycle prevention at mutation boundary (C4).
5. Address `Data` type confusion in non-Debug builds (C5).
6. Resolve UI JSON `props` mismatch and child-key collision hazards (H5, H6).
7. Decide what to do with the overlay/portal subsystem (wire it or remove/flag) (H7).
8. Clean up doc drift for retained API + Luau findings (H8).

## Appendix: File Inventory Stats

Tracked files by top-level directory (`rg --files`):

- `deps/`: 175
- `src/`: 133
- `assets/`: 86
- `luau/`: 20
- `vendor/`: 8
- `docs/`: 7
- `tools/`: 4
- `deepwiki/`: 2
- `snapshots/`: 1
- repo root: 8

Tracked files by extension (top 10):

- `.zig`: 187
- `.luau`: 76
- `.ttf`: 62
- `.md`: 48
- `.txt`: 11
- `.mdx`: 8
- `.png`: 6
- `.zon`: 6
- `.json`: 6
- `.c`: 5

