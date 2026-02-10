# DVUI Runtime Performance Audit (Release-Focused)

Date: 2026-02-09  
Repo: `/mnt/c/Users/andre/Documents/dvui`  
Git HEAD: `272cd18512987b5643f8d6a79793523ac17d34a8` (working tree currently dirty)

This report is a static, release-focused runtime performance review. I used subagents to deep-read `src/retained/` and `src/native_renderer/`, then reviewed the rest of the repo for hot-path allocation patterns, algorithmic scaling risks, and GPU/IO pitfalls that can cause frame drops.

## Inventory (What Was Reviewed)

Text/code files in this repo (from `rg --files`): 446

* Zig: 187 files
* Luau: 76 files
* C/C++/ObjC/H: 11 files
* Other text (md/json/ts/wgsl/sh/zon): 70 files
* Binary/assets (png/ttf/svg/etc): present, not decompiled; reviewed for runtime loading patterns only

## Executive Summary (Release Risk)

The dominant release risks are:

* **Per-frame allocator churn** in retained rendering due to a scratch allocator rooted in the long-lived store allocator, not the window frame allocator.
* **O(N) full-tree hit testing per frame** (and potentially multiple times per frame), with little pruning; this scales poorly as UI node count grows.
* **Guaranteed per-frame overlay recomputation** because overlay caching includes `frameTimeNS()` in the cache key.
* **Potential O(N^2) behavior in layout recompute** during large layout changes due to recursive subtree invalidation inside `computeNodeLayout`.
* **Luau GC pressure on input bursts** from per-event/per-frame table allocation and repeated global lookups.

If the product ships with large retained UI trees, rapid pointer motion, overlays/modals, or frequent layout changes/animations, the current code has several paths that can plausibly cause frame pacing issues.

## Critical Issues (Fix Before Release)

### 1. Retained Render Scratch Allocator Causes Per-Frame Heap Churn

**Where**

* `src/retained/render/mod.zig:63`

**What**

`retained.render()` creates a fresh `std.heap.ArenaAllocator` every frame using `store.allocator` (the renderer GPA), then `deinit()`s it at the end of the frame.

That scratch allocator is used for many transient allocations (ordering arrays, temporary vertex/index arrays, text aggregation buffers, etc). With complex scenes, this will allocate multiple underlying blocks from the GPA each frame and free them at the end of the frame, which is the opposite of what you want for stable frame time.

**Why This Is Release-Critical**

* The retained renderer does a lot of transient allocation work by design (sorting, geometry building, widget glue).
* With an arena backed by the GPA and recreated each frame, you get repeated heap allocations/frees (and potential fragmentation) under load.
* DVUI already provides a per-frame allocator (`Window.arena()` / `Window.lifo()`) designed to retain capacity across frames and reset cheaply.

**Direction**

Use `dvui.currentWindow().arena()` (or an explicit per-frame allocator passed in from the caller) for scratch, so the allocations are frame-bounded without per-frame heap churn.

### 2. Full-Tree Hit Testing Per Frame With Minimal Pruning

**Where**

* `src/retained/hit_test.zig:14`
* Called from `src/retained/render/mod.zig:78` via `interaction.scanPickPair`

**What**

`hit_test.scan()` recursively walks every node’s children unconditionally (subject only to clip/hidden/opacity checks). It does not prune subtrees based on interactivity, hover-relevance, or point containment. It also computes transform context (`transitions.effectiveTransform`) per visited node.

**Why This Is Release-Critical**

This is effectively **O(N)** per frame for hit testing where `N` is the total number of nodes, even when only a small subset can receive pointer events. In large UIs (lists, trees, complex layouts), this can dominate CPU time and scale poorly across devices.

**Direction**

Prune aggressively:

* Skip subtrees with `total_interactive == 0` and no hover-relevant descendants.
* Consider early-out when the point is outside a node’s bounds and children cannot be outside (non-absolute, no transforms), or when `clip_children` constrains descendants.
* Consider caching bounding volumes for interactive nodes or maintaining a lightweight spatial index for pointer picking.

### 3. Overlay Cache Always Invalidates Every Frame

**Where**

* `src/retained/render/internal/overlay.zig:36`

**What**

`ensureOverlayState()` hashes `version` and `dvui.frameTimeNS()` to create a cache key. Because `frameTimeNS()` changes every frame, overlay state recomputes every frame even if the UI tree is unchanged.

This recomputation includes traversing portal nodes and their children to compute modal state and the overlay hit rect.

**Why This Is Release-Critical**

Overlays/modals are common, and this forces extra full-subtree work every frame (even when idle).

**Direction**

Remove `frameTimeNS()` from the cache key. Tie invalidation to real causes:

* subtree version changes, portal list changes, and overlay-relevant style/state changes.
* If animation affects overlay extents, incorporate a dedicated “overlay geometry changed” version/flag rather than time.

### 4. Layout Recompute Can Go O(N^2) During Large Changes

**Where**

* `src/retained/layout/mod.zig:328`
* `src/retained/layout/mod.zig:109`

**What**

Inside `computeNodeLayout()`, when `rect` or `child_rect` changes, it calls `invalidateLayoutSubtree(store, node)`, which recursively walks the entire subtree and invalidates every descendant. The layout walk then continues to recurse into children again.

In the worst case (many nodes changing), this can compound into repeated subtree traversals.

**Why This Is Release-Critical**

Large responsive changes (window resize, flex relayout, hover layout invalidation, spacing animations) can trigger lots of rect changes. An O(N^2) step will blow frame budget at moderate `N`.

**Direction**

Avoid recursive invalidation per node during the same pass. Options:

* Use a single “layout pass id” or “parent geometry changed” flag propagated downward without recursive invalidation.
* Invalidate once at the highest changed ancestor, not at every node.
* If you need to force recompute, mark descendants dirty via versioning, not a recursive traversal.

## High Severity Issues (Very Likely to Matter)

### 5. Per-Event Lua Table Allocation (Pointer Events) Causes GC Churn

**Where**

* `src/native_renderer/window.zig:153` (`drainLuaEvents`)
* `src/native_renderer/event_payload.zig:6`

**What**

For pointer events (`pointermove`, drag events, etc.), `pointerPayloadTable()` allocates two Lua tables per event (payload + modifiers). During high-frequency pointer move/drag this can create significant GC pressure and CPU overhead on the render thread.

**Direction**

Prefer allocation-free dispatch:

* Pass scalars `(x, y, button, modifiers)` directly instead of a table.
* Or reuse a single table stored in the Lua registry and mutate fields in place per call.
* Or pass a packed byte slice and decode in Lua.

### 6. Per-Frame Lua Input Table Allocation + Repeated Global Lookups

**Where**

* `src/native_renderer/window.zig:310`
* `src/native_renderer/lifecycle.zig:61` (`isLuaFuncPresent`)

**What**

Each frame, the renderer:

* checks for `update` presence via global lookup (`isLuaFuncPresent`)
* creates a fresh input table and sets many fields
* calls `update(dt, input_table)`

Similar global lookup happens for `on_event`.

**Direction**

Cache the function references (or presence booleans) once at init. Reuse an input table across frames (stored in registry) and only update the numeric fields.

### 7. Native Command Rendering Path Has Draw Call Explosion + Per-Frame Hashing/Allocations

**Where**

* `src/native_renderer/commands.zig:27`
* `src/native_renderer/commands.zig:135`

**What**

The command renderer rebuilds a layout tree via `AutoHashMap` each frame, allocates per node, then for each rectangle command allocates a `dvui.Triangles.Builder` and calls `dvui.renderTriangles` immediately.

This scales poorly:

* O(n) hashing/allocation for layout tree build
* potentially one draw submission per primitive
* repeated text measurement per layout pass

**Direction**

Batch aggressively:

* Use a single builder per frame (or per material), append all rects, submit once.
* Replace per-frame hash maps with dense arrays (id->index map built once) or reuse cached structures when command list is unchanged.
* Cache text measurement by `(font, text)` or precompute sizes in the producer.

### 8. Paragraph Rendering Aggregates Text Every Frame

**Where**

* `src/retained/render/internal/renderers.zig:627`

**What**

For `p/h1/h2/h3`, the renderer collects descendant text into an `ArrayList(u8)` and trims it every frame. Even though line-break calculation is cached by hash, the aggregation cost still happens every frame and is O(total text size).

**Direction**

Cache aggregated text per node, keyed by a subtree text version/hash, and only rebuild when descendant text changes.

### 9. Button Label Aggregation Rebuilds Text Every Frame

**Where**

* `src/retained/render/internal/renderers.zig:1821`
* Called from `src/retained/render/internal/renderers.zig:762`

**What**

`buildText()` walks the subtree and builds an owned string every frame for each button.

**Direction**

Same as paragraphs: cache, or store a direct text child reference, or treat button label as a property set from Luau rather than inferred from children.

### 10. Focus Registration Copies `WidgetData` Per Focusable Per Frame

**Where**

* `src/retained/events/focus.zig:103`

**What**

`registerFocusable()` allocates a new `dvui.WidgetData` via `dvui.widgetAlloc` and copies the full `WidgetData` for every focusable each frame, storing a pointer in `FocusEntry`.

Even if `dvui.widgetAlloc` is a frame allocator, this is heavy and scales linearly with focusables per frame.

**Direction**

Store only what you need for focus traversal:

* `widget_id`, `node_id`, `border_rect`, `tab_index`, and minimal extra state.
* Avoid copying full `WidgetData` unless absolutely needed.

### 11. On-Demand SVG -> TVG Conversion and File IO in the Render Path

**Where**

* `src/retained/render/icon_registry.zig:317` (`ensureVectorBytes`)
* `src/retained/render/icon_registry.zig:391` (`readIconFile`)
* `src/retained/render/image_loader.zig:126` (`readImageFile`)

**What**

Icons and images are loaded synchronously on demand. SVG icons are converted to TVG on demand. First-time use of an image/icon can stall the render thread due to file IO and conversion work.

**Direction**

Preload or async-load:

* Require registration upfront at startup (or at least off the render thread).
* Convert SVG to TVG at build-time or preload time.

## Medium Severity / Watchlist

These are likely not release blockers alone but could add up:

* `src/retained/render/internal/renderers.zig`: z-index sorting allocates and sorts per parent with z-indexed children. Usually small, but can spike for large sibling lists. (`renderChildrenOrdered`)
* `src/backends/webgpu/mod.zig:56`: `max_frames_in_flight = 1` may reduce throughput due to less CPU/GPU overlap. Validate with profiling; 2-3 frames often improves steady-state FPS at the cost of latency/memory.
* `src/backends/wgpu.zig`: MSDF path writes per-draw uniform data via `queue.writeBuffer` per MSDF command; can get expensive for lots of text draws. Consider grouping or using an instance buffer / vertex attribute indirection.

## Notes By Directory

### `src/native_renderer/`

* Hot path: `window.renderFrame()` is the frame loop. (`src/native_renderer/window.zig:228`)
* Major risks: Lua dispatch allocation and command rendering batching (see issues above).
* Non-frame code: `lifecycle.zig` includes file loading and JSON5 normalization for `require` and is mostly startup-time.

### `src/retained/`

* Hot path: `retained.render()` does layout update, hit test, hover sync, and full render every frame. (`src/retained/render/mod.zig`)
* Major risks: scratch allocator choice, hit test scaling, overlay caching bug, layout invalidation behavior, and per-frame text aggregation.

### `src/backends/` + `src/render/` + `src/text/` + `src/window/`

* These implement DVUI drawing primitives and the WGPU backend; performance is mostly determined by draw command batching and text rendering.
* Text rendering (`src/render/render.zig`) builds triangles per glyph run each draw; it is expected but can dominate CPU with lots of text.
* Font cache (`src/text/font.zig`) has reasonable caching but can still cause spikes when new glyphs cause atlas regeneration.

### `luau/`

* `luau/index.luau` is lean: `update` steps animation; `on_event` dispatches to SolidLuau.
* Runtime performance is likely dominated by SolidLuau’s reconciler/reactivity, plus the Zig bridge costs described above.

### `deps/` and `vendor/`

* Dependencies are large and mostly third-party. I reviewed integration points and obvious hot-path usage, but did not do a full upstream code audit.
* Notable: Yoga exists but retained layout currently uses custom flex (`use_yoga_layout = false` in `src/retained/layout/mod.zig:10`).

## Concrete “Release Gate” Checks (Recommended)

These are validation steps to run before release:

1. Add a stress scene in Luau that creates 1k-10k nodes (text + buttons + flex lists) and measure frame time breakdown using `src/native_renderer/profiling.zig` (currently mostly commented out).
2. Simulate pointermove bursts and measure GC time in Luau (or at least count allocations by instrumenting `pointerPayloadTable` calls).
3. Test overlays/modals in a static scene and confirm overlay recompute is not per-frame once caching is fixed.
4. Resize the window repeatedly and measure layout recompute time; look for superlinear behavior.

## Appendix B: Subagent Notes (src/retained)

This section is the subagent’s file-by-file scan summary for `src/retained/`, included verbatim (lightly reformatted) to preserve coverage.

Top risks called out by the subagent:

* Overlay cache invalidates every frame because `frameTimeNS()` is part of the cache key. (`src/retained/render/internal/overlay.zig:36`)
* Layout can become O(n^2) when many nodes change due to recursive subtree invalidation inside `computeNodeLayout`. (`src/retained/layout/mod.zig:109`, `src/retained/layout/mod.zig:328`)
* Paragraph rendering rebuilds combined text every frame. (`src/retained/render/internal/renderers.zig:627`)
* Button rendering rebuilds combined text every frame. (`src/retained/render/internal/renderers.zig:1821`)
* Focus registration allocates/copies `WidgetData` per focusable per frame. (`src/retained/events/focus.zig:103`)

Per-file scan notes:

* `src/retained/mod.zig`: no critical/high issues noted
* `src/retained/hit_test.zig`: no critical/high issues noted (but see “Critical Issue #2” above for additional analysis)
* `src/retained/events/focus.zig`: high, per-frame `WidgetData` allocation/copy in `registerFocusable` (`src/retained/events/focus.zig:103`)
* `src/retained/events/mod.zig`: no critical/high issues noted
* `src/retained/events/drag_drop.zig`: no critical/high issues noted
* `src/retained/events/ARCHITECTURE.md`: no critical/high issues noted
* `src/retained/layout/mod.zig`: high, recursive subtree invalidation can lead to O(n^2) (`src/retained/layout/mod.zig:109`, `src/retained/layout/mod.zig:328`)
* `src/retained/layout/measure.zig`: no critical/high issues noted
* `src/retained/layout/flex.zig`: no critical/high issues noted
* `src/retained/layout/text_wrap.zig`: no critical/high issues noted
* `src/retained/layout/ARCHITECTURE.md`: no critical/high issues noted
* `src/retained/layout/yoga.zig`: no critical/high issues noted
* `src/retained/loaders/ui_json.zig`: no critical/high issues noted
* `src/retained/loaders/ui_json_test.zig`: no critical/high issues noted
* `src/retained/render/mod.zig`: no critical/high issues noted (but see “Critical Issue #1” above for additional analysis)
* `src/retained/render/cache.zig`: no critical/high issues noted
* `src/retained/render/direct.zig`: no critical/high issues noted
* `src/retained/render/transitions.zig`: no critical/high issues noted
* `src/retained/render/image_loader.zig`: no critical/high issues noted (but see “High Severity #11” above for additional analysis)
* `src/retained/render/icon_registry.zig`: no critical/high issues noted (but see “High Severity #11” above for additional analysis)
* `src/retained/render/internal/runtime.zig`: no critical/high issues noted
* `src/retained/render/internal/renderers.zig`: high, per-frame text aggregation in `renderParagraph` and `buildText` (`src/retained/render/internal/renderers.zig:627`, `src/retained/render/internal/renderers.zig:1821`)
* `src/retained/render/internal/interaction.zig`: no critical/high issues noted
* `src/retained/render/internal/hover.zig`: no critical/high issues noted
* `src/retained/render/internal/derive.zig`: no critical/high issues noted
* `src/retained/render/internal/state.zig`: no critical/high issues noted
* `src/retained/render/internal/visual_sync.zig`: no critical/high issues noted
* `src/retained/render/internal/overlay.zig`: high, cache key includes `frameTimeNS` (`src/retained/render/internal/overlay.zig:36`)
* `src/retained/style/mod.zig`: no critical/high issues noted
* `src/retained/style/apply.zig`: no critical/high issues noted
* `src/retained/style/colors.zig`: no critical/high issues noted
* `src/retained/style/tailwind.zig`: no critical/high issues noted
* `src/retained/style/tailwind/parse.zig`: no critical/high issues noted
* `src/retained/style/tailwind/parse_layout.zig`: no critical/high issues noted
* `src/retained/style/tailwind/parse_color_typography.zig`: no critical/high issues noted
* `src/retained/style/tailwind/types.zig`: no critical/high issues noted
* `src/retained/core/types.zig`: no critical/high issues noted
* `src/retained/core/node_store.zig`: no critical/high issues noted
* `src/retained/core/layout.zig`: no critical/high issues noted
* `src/retained/core/geometry.zig`: no critical/high issues noted
* `src/retained/core/media.zig`: no critical/high issues noted
* `src/retained/core/visual.zig`: no critical/high issues noted
* `src/retained/core/ARCHITECTURE.md`: no critical/high issues noted

## Appendix C: Subagent Notes (src/native_renderer)

This section is the subagent’s file-by-file scan summary for `src/native_renderer/`, included verbatim (lightly reformatted) to preserve coverage.

Top risks called out by the subagent:

* Per-frame layout tree construction with hashing and heap allocations. (`src/native_renderer/commands.zig:27`)
* Excessive draw calls and per-draw allocations in command rendering. (`src/native_renderer/commands.zig:135`)
* Pointer event handling allocates Lua tables per event, causing GC churn under input bursts. (`src/native_renderer/window.zig:153`)

Per-file scan notes:

* `src/native_renderer/commands.zig`: high, per-frame `AutoHashMap` layout build; per-primitive builder and draw-call explosion; per-frame text measurement in layout (`src/native_renderer/commands.zig:27`, `src/native_renderer/commands.zig:60`, `src/native_renderer/commands.zig:135`)
* `src/native_renderer/window.zig`: high, allocates Lua tables per pointer event; calls `renderCommandsDvui` fallback which inherits the `commands.zig` costs (`src/native_renderer/window.zig:153`, `src/native_renderer/window.zig:390`)
* `src/native_renderer/lifecycle.zig`: no critical/high per-frame rendering risks noted (JSON parsing/file loading is not per-frame)
* `src/native_renderer/luau_ui.zig`: no critical/high per-frame rendering risks noted (mostly store mutation)
* `src/native_renderer/event_payload.zig`: no critical/high per-frame rendering risks noted beyond table allocation when used
* `src/native_renderer/profiling.zig`: no critical/high issues noted
* `src/native_renderer/types.zig`: no critical/high issues noted
* `src/native_renderer/utils.zig`: no critical/high issues noted

## Appendix A: Full Tracked File List (`rg --files`)

This is a verbatim snapshot of `rg --files` at the time of audit.

```text
LICENSE
favicon.png
solidluau_embedded.zig
UI_FEATURES.md
PERFORMANCE_AUDIT.md
RELEASE_ARCHITECTURE_REVIEW.md
zig_build_simple.sh
build.zig
build.zig.zon
AGENTS.md
docs/RETAINED.md
deepwiki/pages.json
deepwiki/parse.ts
docs/RETAINED_API.md
docs/UI_PRIMITIVES.md
luau/ui_features_image_1.png
snapshots/app.layout.json
tools/ui_codegen.zig
tools/luau_smoke.zig
tools/luau_layout_dump_main.zig
tools/layoutdump_scenes.json
luau/app.luau
luau/index.luau
docs/luau-findings/high-stale-object-prop-clear-semantics.md
docs/luau-findings/high-event-ring-saturation-after-lua-teardown.md
docs/luau-findings/high-binary-event-payload-contract.md
docs/LAYOUT_TREE_DUMP.md
luau/ui/types.luau
luau/ui/load_ui.luau
luau/ui/cn.luau
luau/ui_json/app.json
luau/_tests/keyed_lists.luau
luau/_tests/disposal_and_batching.luau
luau/_tests/conditional_visibility.luau
luau/components/toggle.luau
luau/components/checkbox.luau
luau/components/bar.luau
luau/_tests/test_scheduler.luau
luau/_tests/testkit.luau
luau/_tests/reconciler.luau
luau/_tests/mock_ui.luau
vendor/stb/stb_image_write.h
vendor/stb/stb_image_libc.c
vendor/stb/stb_image_impl.c
vendor/stb/stb_image.h
vendor/stb/stb_truetype.h
vendor/stb/stb_image_write_impl.c
vendor/stb/stb_truetype_impl.c
vendor/stb/stb_truetype_libc.c
luau/ui_gen/app_ui.luau
src/platform/mod.zig
src/platform/io_compat.zig
src/platform/dialogs.zig
src/window/window.zig
src/window/subwindows.zig
src/window/mod.zig
src/window/event.zig
src/window/dragging.zig
src/window/debug.zig
src/window/app.zig
src/main.zig
assets/fonts.zig
assets/windows/main.manifest
assets/sprite.png
assets/mod.zig
luau/_smoke/ui_refs.luau
luau/_smoke/checkbox.luau
src/layout/easing.zig
src/dvui.zig
src/layout/scroll_info.zig
src/layout/mod.zig
src/layout/layout.zig
src/backends/wgpu.zig
src/backends/webgpu.zig
src/widgets/widget_data.zig
src/widgets/widget.zig
src/widgets/SelectionWidget.zig
src/native_renderer/window.zig
src/native_renderer/utils.zig
src/native_renderer/types.zig
src/native_renderer/profiling.zig
src/native_renderer/mod.zig
src/native_renderer/luau_ui.zig
src/native_renderer/lifecycle.zig
src/native_renderer/event_payload.zig
src/native_renderer/commands.zig
deps/zig-yoga/src/root.zig
deps/zig-yoga/src/enums.zig
deps/zig-yoga/build.zig.zon
deps/zig-yoga/build.zig
src/backends/common.zig
src/backends/backend.zig
deps/msdf_zig/src/types.zig
src/testing/mod.zig
src/core/vertex.zig
src/core/size.zig
src/core/rect.zig
src/core/point.zig
src/core/options.zig
src/core/mod.zig
src/core/enums.zig
src/core/data.zig
src/core/color.zig
assets/fonts/Inter/Inter-Regular.ttf
assets/fonts/Inter/Inter-Bold.ttf
src/render/triangles.zig
src/render/texture.zig
src/render/render.zig
src/render/png_encoder.zig
src/render/path.zig
src/render/mod.zig
src/render/jpg_encoder.zig
src/widgets/IconWidget.zig
src/widgets/GizmoWidget.zig
src/widgets/FlexBoxWidget.zig
src/widgets/ButtonWidget.zig
src/widgets/BoxWidget.zig
src/widgets/AnimateWidget.zig
assets/fonts/Segoe/Segoe-UI.TTF
assets/fonts/Segoe/Segoe-UI-Light.TTF
assets/fonts/Segoe/Segoe-UI-Italic.TTF
assets/fonts/Segoe/Segoe-UI-Bold.TTF
src/backends/webgpu/platform_windows.zig
src/backends/webgpu/platform_macos_metal_layer.m
src/backends/webgpu/platform_macos.zig
src/backends/webgpu/mod.zig
src/backends/raylib-zig.zig
src/widgets/SelectionWidget/transform.zig
src/widgets/SelectionWidget/events.zig
src/widgets/SelectionWidget/drawing.zig
src/widgets/ScrollBarWidget.zig
src/widgets/ScaleWidget.zig
src/widgets/mod.zig
src/widgets/MenuWidget.zig
src/widgets/MenuItemWidget.zig
src/widgets/LabelWidget.zig
deps/msdf_zig/msdf_zig.zig
src/accessibility/mod.zig
src/accessibility/accesskit.zig
src/backends/mod.zig
deps/solidluau/ZIG_NATIVE_PLAN.md
deps/luaz/zlint.json
deps/msdf_zig/src/shaders/msdf_text_world.wgsl
deps/msdf_zig/src/shaders/msdf_text_ui.wgsl
deps/msdf_zig/src/shader.zig
deps/msdf_zig/src/msdf_zig.zig
deps/wgpu_native_zig/LICENSE
assets/fonts/Consolas/Consolas.TTF
assets/fonts/hack/LICENSE
assets/fonts/hack/Hack-Regular.ttf
assets/fonts/hack/Hack-Italic.ttf
assets/fonts/hack/Hack-BoldItalic.ttf
assets/fonts/hack/Hack-Bold.ttf
src/utils/tracking_hash_map.zig
src/utils/struct_ui.zig
src/utils/mod.zig
src/utils/cache_buster.zig
src/utils/alloc.zig
assets/fonts/PixelOperator/PixelOperatorSC.ttf
assets/fonts/PixelOperator/PixelOperatorSC-Bold.ttf
assets/fonts/PixelOperator/PixelOperatorMonoHB8.ttf
assets/fonts/PixelOperator/PixelOperatorMonoHB.ttf
assets/fonts/PixelOperator/PixelOperatorMono8.ttf
assets/fonts/PixelOperator/PixelOperatorMono8-Bold.ttf
assets/fonts/PixelOperator/PixelOperatorMono.ttf
assets/fonts/PixelOperator/PixelOperatorMono-Bold.ttf
assets/fonts/PixelOperator/PixelOperatorHBSC.ttf
assets/fonts/PixelOperator/PixelOperatorHB8.ttf
assets/fonts/PixelOperator/PixelOperatorHB.ttf
assets/fonts/PixelOperator/PixelOperator8.ttf
assets/fonts/PixelOperator/PixelOperator8-Bold.ttf
assets/fonts/PixelOperator/PixelOperator.ttf
assets/fonts/PixelOperator/PixelOperator-Bold.ttf
assets/fonts/PixelOperator/LICENSE.txt
deps/msdf_zig/assets/msdf_placeholder_font.json
deps/msdf_zig/assets/msdf_placeholder_atlas.png
deps/luaz/CONTRIBUTING.md
deps/luaz/codecov.yml
deps/luaz/CHANGELOG.md
deps/luaz/build.zig.zon
deps/luaz/build.zig
deps/luaz/AGENTS.md
deps/luaz/LICENSE
src/backends/pipeline/types.zig
src/backends/pipeline/swap_chain.zig
src/backends/pipeline/render.zig
src/backends/pipeline/main.zig
src/backends/pipeline/geometry.zig
src/backends/pipeline/depth.zig
src/backends/pipeline/compute.zig
assets/fonts/NotoSansKR-Regular.ttf
deps/luaz/src/userdata.zig
deps/luaz/src/State.zig
deps/luaz/src/stack.zig
deps/luaz/src/Lua.zig
deps/luaz/src/lib.zig
deps/luaz/src/handler.h
deps/luaz/src/handler.cpp
deps/luaz/src/GC.zig
deps/luaz/src/Debug.zig
deps/luaz/src/Compiler.zig
deps/luaz/src/assert.zig
deps/luaz/src/alloc.zig
deps/luaz/README.md
deps/luaz/LUAU_API.md
deps/wgpu_native_zig/build.zig
deps/wgpu_native_zig/build.zig.zon
deps/wgpu_native_zig/test-all
deps/solidluau/zig/solidluau_tests.zig
deps/solidluau/zig/solidluau_modules.zig
deps/solidluau/zig/solidluau_embed.zig
deps/wgpu_native_zig/tests/compute_c.zig
deps/wgpu_native_zig/tests/compute.zig
deps/wgpu_native_zig/tests/compute.wgsl
deps/solidluau/README.md
src/retained/style/tailwind.zig
assets/fonts/bitstream-vera/VeraSeBd.ttf
assets/fonts/bitstream-vera/VeraSe.ttf
assets/fonts/bitstream-vera/VeraMono.ttf
assets/fonts/bitstream-vera/VeraMoIt.ttf
assets/fonts/bitstream-vera/VeraMoBI.ttf
assets/fonts/bitstream-vera/VeraMoBd.ttf
assets/fonts/bitstream-vera/VeraIt.ttf
assets/fonts/bitstream-vera/VeraBI.ttf
assets/fonts/bitstream-vera/VeraBd.ttf
assets/fonts/bitstream-vera/Vera.ttf
assets/fonts/bitstream-vera/RELEASENOTES.TXT
assets/fonts/bitstream-vera/README.TXT
assets/fonts/bitstream-vera/local.conf
assets/fonts/bitstream-vera/COPYRIGHT.TXT
assets/fonts/OpenDyslexic/OFL-FAQ.txt
assets/fonts/OpenDyslexic/FONTLOG.txt
assets/fonts/OpenDyslexic/README.md
assets/fonts/OpenDyslexic/OFL.txt
src/theming/shadcn.zon
src/theming/mod.zig
src/theming/theme.zig
src/retained/style/apply.zig
deps/luaz/examples/runtime_loop.zig
deps/luaz/examples/guided_tour.zig
src/text/selection.zig
src/text/mod.zig
src/text/font.zig
deps/wgpu_native_zig/src/texture.zig
deps/wgpu_native_zig/src/surface.zig
deps/wgpu_native_zig/src/shader.zig
deps/wgpu_native_zig/src/sampler.zig
deps/wgpu_native_zig/src/root.zig
deps/wgpu_native_zig/src/render_bundle.zig
deps/wgpu_native_zig/src/queue.zig
deps/wgpu_native_zig/src/query_set.zig
deps/wgpu_native_zig/src/pipeline.zig
deps/wgpu_native_zig/src/misc.zig
deps/wgpu_native_zig/src/log.zig
deps/wgpu_native_zig/src/limits.zig
deps/wgpu_native_zig/src/instance.zig
deps/wgpu_native_zig/src/global.zig
deps/wgpu_native_zig/src/device.zig
deps/wgpu_native_zig/src/command_encoder.zig
deps/wgpu_native_zig/src/chained_struct.zig
deps/wgpu_native_zig/src/buffer.zig
deps/wgpu_native_zig/src/bind_group.zig
deps/wgpu_native_zig/src/async.zig
deps/wgpu_native_zig/src/adapter.zig
deps/wgpu_native_zig/README.md
deps/wgpu_native_zig/examples/bmp.zig
deps/solidluau/build.zig.zon
deps/solidluau/build.zig
deps/solidluau/build-docs
assets/fonts/Aleo/static/Aleo-ThinItalic.ttf
assets/fonts/Aleo/static/Aleo-Thin.ttf
assets/fonts/Aleo/static/Aleo-SemiBoldItalic.ttf
assets/fonts/Aleo/static/Aleo-SemiBold.ttf
assets/fonts/Aleo/static/Aleo-Regular.ttf
assets/fonts/Aleo/static/Aleo-MediumItalic.ttf
assets/fonts/Aleo/static/Aleo-Medium.ttf
assets/fonts/Aleo/static/Aleo-LightItalic.ttf
assets/fonts/Aleo/static/Aleo-Light.ttf
assets/fonts/Aleo/static/Aleo-Italic.ttf
assets/fonts/Aleo/static/Aleo-ExtraLightItalic.ttf
assets/fonts/Aleo/static/Aleo-ExtraLight.ttf
assets/fonts/Aleo/static/Aleo-ExtraBoldItalic.ttf
assets/fonts/Aleo/static/Aleo-ExtraBold.ttf
assets/fonts/Aleo/static/Aleo-BoldItalic.ttf
assets/fonts/Aleo/static/Aleo-Bold.ttf
assets/fonts/Aleo/static/Aleo-BlackItalic.ttf
assets/fonts/Aleo/static/Aleo-Black.ttf
assets/fonts/Aleo/README.txt
assets/fonts/Aleo/OFL.txt
assets/fonts/Aleo/Aleo-VariableFont_wght.ttf
assets/fonts/Aleo/Aleo-Italic-VariableFont_wght.ttf
src/retained/loaders/ui_json_test.zig
src/retained/loaders/ui_json.zig
assets/fonts/OpenDyslexic/compiled/OpenDyslexic-Regular.otf
assets/fonts/OpenDyslexic/compiled/OpenDyslexic-Italic.otf
assets/fonts/OpenDyslexic/compiled/OpenDyslexic-Bold.otf
assets/fonts/OpenDyslexic/compiled/OpenDyslexic-Bold-Italic.otf
src/retained/hit_test.zig
assets/fonts/Pixelify_Sans/PixelifySans-VariableFont_wght.ttf
assets/fonts/Pixelify_Sans/OFL.txt
assets/fonts/Pixelify_Sans/README.txt
src/retained/render/icon_registry.zig
src/retained/render/direct.zig
src/retained/render/cache.zig
src/retained/mod.zig
src/retained/render/transitions.zig
src/retained/render/mod.zig
src/retained/style/tailwind/parse.zig
src/retained/style/mod.zig
src/retained/style/colors.zig
src/retained/style/tailwind/parse_layout.zig
src/retained/style/tailwind/parse_color_typography.zig
src/retained/style/tailwind/types.zig
deps/wgpu_native_zig/examples/triangle/shader.wgsl
deps/wgpu_native_zig/examples/triangle/triangle.zig
deps/solidluau/solidluau_modules.zig
deps/solidluau/solidluau_embed.zig
deps/solidluau/TASK.md
src/retained/events/ARCHITECTURE.md
src/retained/events/mod.zig
src/retained/events/focus.zig
src/retained/events/drag_drop.zig
deps/luaz/docs/logo.png
deps/solidluau/docs/solidluau-scheduler.mdx
deps/solidluau/docs/solidluau-reactivity.mdx
deps/solidluau/docs/solidluau-animationentry.mdx
deps/solidluau/docs/solidluau-animation.mdx
deps/solidluau/docs/solidluau-ui.mdx
deps/solidluau/docs/solidluau-ui-dsl.mdx
deps/solidluau/docs/solidluau-uientry.mdx
deps/solidluau/docs/solidluau.mdx
deps/solidluau/vide/OVERVIEW.md
deps/solidluau/vide/init.luau
assets/fonts/Pixelify_Sans/static/PixelifySans-SemiBold.ttf
assets/fonts/Pixelify_Sans/static/PixelifySans-Regular.ttf
assets/fonts/Pixelify_Sans/static/PixelifySans-Medium.ttf
assets/fonts/Pixelify_Sans/static/PixelifySans-Bold.ttf
assets/branding/zig-mark.svg
assets/branding/zig-favicon.png
src/retained/render/image_loader.zig
src/retained/layout/mod.zig
src/retained/layout/measure.zig
src/retained/layout/flex.zig
src/retained/layout/text_wrap.zig
src/retained/layout/ARCHITECTURE.md
src/retained/layout/yoga.zig
deps/solidluau/vide/README.md
deps/solidluau/luau-docs/moonwave-extractor
deps/solidluau/luau-docs/index.ts
deps/solidluau/luau-docs/README.md
src/retained/render/internal/overlay.zig
src/retained/render/internal/interaction.zig
src/retained/render/internal/hover.zig
src/retained/render/internal/derive.zig
src/retained/render/internal/runtime.zig
src/retained/render/internal/renderers.zig
src/retained/render/internal/state.zig
src/retained/render/internal/visual_sync.zig
deps/solidluau/scripts/build-docs.sh
deps/solidluau/src/ARCHITECTURE_REVIEW.md
deps/solidluau/src/animation.luau
deps/solidluau/src/solidluau.luau
deps/solidluau/src/README.md
deps/solidluau/src/ui.luau
deps/solidluau/vide/src/implicit_effect.luau
deps/solidluau/vide/src/graph.luau
deps/solidluau/vide/src/flags.luau
deps/solidluau/vide/src/effect.luau
deps/solidluau/vide/src/derive.luau
deps/solidluau/vide/src/defaults.luau
deps/solidluau/vide/src/create.luau
deps/solidluau/vide/src/context.luau
deps/solidluau/vide/src/cleanup.luau
deps/solidluau/vide/src/changed.luau
deps/solidluau/vide/src/branch.luau
deps/solidluau/vide/src/batch.luau
deps/solidluau/vide/src/apply.luau
deps/solidluau/vide/src/action.luau
deps/solidluau/vide/src/show.luau
deps/solidluau/vide/src/root.luau
deps/solidluau/vide/src/read.luau
deps/solidluau/vide/src/mount.luau
deps/solidluau/vide/src/lib.luau
deps/solidluau/vide/src/init.luau
deps/solidluau/vide/src/indexes.luau
deps/solidluau/vide/src/switch.luau
deps/solidluau/vide/src/spring.luau
deps/solidluau/vide/src/source.luau
deps/solidluau/vide/src/untrack.luau
deps/solidluau/vide/src/timeout.luau
deps/solidluau/vide/src/values.luau
src/retained/core/node_store.zig
src/retained/core/media.zig
src/retained/core/layout.zig
src/retained/core/geometry.zig
src/retained/core/types.zig
src/retained/core/ARCHITECTURE.md
src/retained/core/visual.zig
deps/solidluau/vide/test/spring-test.luau
deps/solidluau/vide/test/mock.luau
deps/solidluau/vide/test/create-types.luau
deps/solidluau/vide/test/benchmarks.luau
deps/solidluau/vide/test/testkit.luau
deps/solidluau/vide/test/stacktrace-test.luau
deps/solidluau/vide/test/tests.luau
deps/solidluau/src/animation/index.luau
deps/solidluau/src/animation/engine.luau
deps/solidluau/src/animation/easing.luau
deps/solidluau/src/animation/spring.luau
deps/solidluau/src/animation/tween.luau
deps/solidluau/tests/luau/reactivity-scope_unlink_test.luau
deps/solidluau/tests/luau/ui-flat-props_cutover_test.luau
deps/solidluau/tests/luau/reactivity-memo_invalidation_test.luau
deps/solidluau/tests/luau/animation-mutableOutput-test.luau
deps/solidluau/src/core/reactivity.luau
deps/solidluau/src/core/scheduler.luau
deps/solidluau/tests/luau/ui-dsl_tag_call_test.luau
deps/solidluau/tests/luau/ui-patch_test.luau
deps/solidluau/src/ui/hydrate.luau
deps/solidluau/src/ui/dsl.luau
deps/solidluau/src/ui/adapter_types.luau
deps/solidluau/src/ui/renderer.luau
deps/solidluau/src/ui/index.luau
deps/solidluau/src/ui/types.luau
deps/solidluau/vide/docs/api/reactivity-core.md
deps/solidluau/vide/docs/api/creation.md
deps/solidluau/vide/docs/api/animation.md
deps/solidluau/vide/docs/api/reactivity-utility.md
deps/solidluau/vide/docs/api/reactivity-dynamic.md
deps/solidluau/vide/docs/api/strict-mode.md
deps/solidluau/vide/docs/advanced/dynamic-scopes.md
deps/solidluau/vide/docs/crash-course/2-creation.md
deps/solidluau/vide/docs/crash-course/14-concepts.md
deps/solidluau/vide/docs/crash-course/13-strict-mode.md
deps/solidluau/vide/docs/crash-course/12-actions.md
deps/solidluau/vide/docs/crash-course/11-dynamic-scopes.md
deps/solidluau/vide/docs/crash-course/10-cleanup.md
deps/solidluau/vide/docs/crash-course/1-introduction.md
deps/solidluau/vide/docs/crash-course/6-scope.md
deps/solidluau/vide/docs/crash-course/5-effect.md
deps/solidluau/vide/docs/crash-course/4-source.md
deps/solidluau/vide/docs/crash-course/3-components.md
deps/solidluau/vide/docs/crash-course/8-implicit-effect.md
deps/solidluau/vide/docs/crash-course/7-reactive-component.md
deps/solidluau/vide/docs/crash-course/9-derived-source.md
deps/solidluau/src/ui/adapters/compat_ui.luau
```
