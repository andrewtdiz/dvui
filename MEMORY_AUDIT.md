# DVUI Memory Management Audit (Release-Focused)

Date: 2026-02-09  
Repo: `/mnt/c/Users/andre/Documents/dvui`  
Git HEAD: `880085a19f8cd2870d362854677987f6cd7458ee` (working tree may be dirty)  
Zig: `zigwin 0.15.2`

## Scope

This is a static review focused on memory management, lifetime/ownership safety, and unbounded retention risks that could impact product release.

Review coverage:

- File set: all non-ignored files from `rg --files` (447 files).
- Deep dive: `src/retained/` and `src/native_renderer/` (subagent-assisted).
- Additional manual review: allocator-heavy modules in `src/window/`, `src/render/`, `src/backends/`, `src/text/`, `src/core/`, `src/utils/`, plus integration boundaries in `deps/*`.

## Inventory

File counts by extension (from `rg --files`):

- `.zig`: 187
- `.luau`: 76
- `.ttf`: 62
- `.md`: 51
- `.txt`: 11
- `.mdx`: 8
- `<noext>`: 7
- `.png`: 6
- `.zon`: 6
- `.json`: 6
- `.c`: 5
- `.otf`: 4
- `.h`: 4
- `.wgsl`: 4
- `.ts`: 2
- `.sh`: 2
- `.svg`: 1
- `.conf`: 1
- `.manifest`: 1
- `.yml`: 1
- `.cpp`: 1
- `.m`: 1

## Severity Scale

- Critical: likely UAF/double-free/memory corruption or unbounded resource exhaustion in realistic use.
- High: strong release risk via unbounded retention/leak or API-boundary lifetime hazard.
- Medium: plausible hazard requiring unusual call order, future refactor, or less common workload.
- Low: minor leaks in tooling/dev paths, or bounded retention with clear tradeoffs.

## Architectural Memory Model (What Exists Today)

- Global allocator selection: `src/utils/alloc.zig` uses `std.heap.GeneralPurposeAllocator` in Debug and `std.heap.c_allocator` otherwise.
- Per-frame allocators in immediate-mode DVUI: `src/window/window.zig` maintains `_arena`, `_lifo_arena`, `_widget_stack` (all arenas) and resets them each `Window.end` with `retain_with_limit`.
- GPU resources: backends (`src/backends/*`) use explicit `release()`/`textureDestroy()` and deferred retirement for buffers/bind groups (wgpu backend).
- Retained renderer: long-lived `NodeStore` allocations (strings, children lists, caches) use `store.allocator`; per-frame scratch uses a temporary arena in `src/retained/render/mod.zig`.
- Native renderer: owns a GPA instance and a frame arena (`Renderer.frame_arena`), and allocates retained `NodeStore` + `EventRing` from `renderer.allocator` (`src/native_renderer/lifecycle.zig`).

## Critical Findings (Fix Before Release)

### C1. Native Renderer Destruction Is Not Safe Under Reentrancy / Multi-Threading (UAF Risk)

Severity: Critical

Evidence:
- `src/native_renderer/lifecycle.zig:1092-1097` `tryFinalize` finalizes immediately when `pending_destroy` and `busy == false` and `callback_depth == 0`.
- `src/native_renderer/types.zig:53` `busy` exists but is not set/cleared by `renderFrame` or other public entrypoints.
- `src/native_renderer/lifecycle.zig:1208-1215` `destroyRendererImpl` sets `pending_destroy = true` and calls `tryFinalize` immediately.
- `src/native_renderer/window.zig:228-375` `renderFrame` does not early-return on `pending_destroy`/`destroy_started`.

Impact:
- If a host calls `destroyRendererImpl` while another thread is inside `renderFrame`/`ensureWindow` (or any other renderer call), `finalizeDestroy` can free allocators and state while still in use. This is a classic use-after-free crash class at the API boundary.

Minimal fix direction:
- Enforce single-threaded usage explicitly (document + runtime assert), or add real synchronization.
- At minimum, set `renderer.busy = true` on entry and clear on exit for all host-callable entrypoints (including `renderFrame`, `ensureWindow`, and destroy), and only allow finalization when not busy.
- Add an early return in `renderFrame` when `pending_destroy` or `destroy_started` is set.

### C2. Retained `NodeStore.insert` Allows Cycles (Infinite Recursion / Stack Overflow)

Severity: Critical

Evidence:
- `src/retained/core/node_store.zig:621-643` sets `child.parent = parent_id` and appends `child_id` to `parent.children` with no cycle check.

Impact:
- A single bad patch/update can create a cycle and cause infinite recursion/stack overflow in layout, rendering, hit-testing, and removal (many walkers are recursive).

Minimal fix direction:
- Reject inserts where `parent_id == child_id` or where `parent_id` is in `child_id`'s subtree.
- Return an error and leave the tree unchanged on violation.

### C3. Core `Data` Store Type Checks Compile Out In Non-Debug Builds (Type Confusion Risk)

Severity: Critical

Evidence:
- `src/core/data.zig:27-38` `SavedData.DebugInfo` is `void` outside Debug builds.
- `src/core/data.zig:85-107` `getPtr`/`getSlice` do unchecked `@ptrCast(@alignCast(...))` when debug info is disabled.

Impact:
- Bugs in keying can become silent type confusion in release builds (wrong type interpretation, misaligned loads, logic corruption). Some cases can become memory safety issues if a mismatched type is written through a pointer.

Minimal fix direction:
- Keep a minimal runtime type signature in all builds (size, alignment, stable type hash) and validate on get/set.
- Or make keys type-specific at the API boundary so collisions are impossible.

## High Findings

### H1. `registerFocusable` Uses `dvui.widgetAlloc` Without `widgetFree` (Contract Violation, Retention Spike, Future UAF Footgun)

Severity: High

Evidence:
- `src/retained/events/focus.zig:112-123` allocates `stored_wd = dvui.widgetAlloc(dvui.WidgetData)` and stores it in `FocusEntry.widget_data`.
- `src/dvui.zig:360-401` documents that callers must call `dvui.widgetFree` for stack-style allocations.

Impact:
- Per-focusable allocation each frame increases peak `_widget_stack` usage and makes spikes sticky due to arena retention.
- It is easy for this to become a real leak/UAF if allocator semantics or usage ordering changes.

Fix direction:
- Store `WidgetData` by value in `FocusEntry` and remove the allocation entirely.

### H2. Retained Image/Icon Loaders Cache Raw Bytes With No Eviction (Unbounded CPU Memory Growth)

Severity: High

Evidence:
- `src/retained/render/image_loader.zig` global `image_cache` stores `ImageResource.bytes` indefinitely.
- `src/retained/render/icon_registry.zig` global `icon_cache` stores SVG/TVG bytes and strings indefinitely.

Impact:
- Long-running apps with many unique assets can grow memory without bound; CPU-side raw bytes can duplicate GPU texture memory.

Fix direction:
- Add eviction (max entries / max bytes) and/or drop raw bytes after texture creation.
- Provide explicit purge APIs and call them on scene transitions.

### H3. Native Renderer FFI Callbacks Pass Pointers To Stack Buffers Without Explicit Lifetime Contract

Severity: High

Evidence:
- `src/native_renderer/lifecycle.zig:23-35`, `42-54`, `1058-1085` pass stack buffer pointers to callbacks.

Impact:
- Host code that retains pointers beyond callback scope can trigger immediate use-after-free.

Fix direction:
- Document the contract (valid only during callback), or switch to stable storage (arena/ring) or copy-based API.

### H4. `NodeStore.node()` Returns Pointers Into `AutoHashMap` (Pointer Stability Footgun)

Severity: High

Evidence:
- `src/retained/core/node_store.zig:657-659` returns `self.nodes.getPtr(id)` directly.

Impact:
- Any caller caching `*SolidNode` across `nodes` mutations risks UAF due to rehash/resize or remove.
- This is especially risky at the Luau patch boundary where inserts/removes are frequent.

Fix direction:
- Avoid exposing stable pointers unless storage is stable.
- Return IDs/copies, or store nodes in stable backing storage and map IDs to stable indices.

## Medium / Low Findings

### M1. Retained `RenderRuntime` Allocator-Lifetime Coupling

Severity: Medium

Evidence:
- `src/retained/render/internal/hover.zig:25-28` caches `store.allocator`.
- `src/retained/render/internal/overlay.zig:21-29` caches `store.allocator`.
- `src/retained/render/internal/runtime.zig:58-76` deinit uses cached allocators.

Risk:
- If `store.allocator` does not outlive runtime, `deinit` can use a dead allocator.

Fix direction:
- Enforce teardown order or make runtime own a stable allocator.

### M2. `Font.Cache.deinit` Frees `TTFEntry.bytes` But Not `TTFEntry.name` When `allocator != null`

Severity: Medium-Low

Evidence:
- `src/text/font.zig:365-371` only frees `ttf.bytes`.
- `src/text/font.zig:236-248` `TTFEntry.deinit` would free both fields.

Fix direction:
- Call `TTFEntry.deinit` for each entry or free both `bytes` and `name` when allocator is present.

### L1. Tooling: `src/utils/cache_buster.zig` Does Not Close Opened Files

Severity: Low

Evidence:
- `src/utils/cache_buster.zig:21` opens file handles without `defer file.close()`.

Fix direction:
- Add `defer file.close()` after `openFile`.

## Dependency Findings (deps/)

These findings are in vendored/submodule code under `deps/`. They can impact product release, but per repo rules I did not modify anything in `deps/`.

### D1. `deps/wgpu_native_zig`: Chained-Descriptor Helper Footguns (`next_in_chain` Lifetime)

Severity: Critical if misused, High as a common footgun

Finding:
- Several `pub inline fn` helpers build chained structs using `@ptrCast(&SomeChainedStruct{ ... })` and return a descriptor by value that contains `next_in_chain` pointing at that temporary.
- This is only safe if the returned descriptor is used immediately in the same statement that consumes it (and is not stored for later use). If it is stored in a variable and used later, `next_in_chain` can dangle and cause use-after-free at descriptor consumption.

Examples (non-exhaustive, from subagent audit):
- `deps/wgpu_native_zig/src/shader.zig`: `shaderModuleWGSLDescriptor`, `shaderModuleSPIRVDescriptor`, `shaderModuleGLSLDescriptor`
- `deps/wgpu_native_zig/src/device.zig`: `DeviceDescriptor.withTracePath`
- `deps/wgpu_native_zig/src/surface.zig`: `surfaceDescriptorFromWindowsHWND` and other platform variants, `SurfaceConfiguration.withDesiredMaxFrameLatency`
- `deps/wgpu_native_zig/src/pipeline.zig`: `PipelineLayoutDescriptor.withPushConstantRanges`
- `deps/wgpu_native_zig/src/bind_group.zig`: `BindGroupLayoutEntry.withCount`
- `deps/wgpu_native_zig/src/query_set.zig`: `QuerySetDescriptor.withPipelineStatistics`
- `deps/wgpu_native_zig/src/command_encoder.zig`: `RenderPassDescriptor.withMaxDrawCount`

DVUI exposure:
- DVUI uses `wgpu.shaderModuleWGSLDescriptor(...)` in:
  - `src/backends/wgpu.zig:671`
  - `src/backends/wgpu.zig:811`
  - `src/backends/pipeline/render.zig:27`
  - `src/backends/pipeline/render.zig:196`
  - `src/backends/pipeline/compute.zig:18`
- These call sites currently pass the descriptor directly into `createShaderModule(...)` (immediate consumption), which is the safe usage pattern for this style of helper.

Fix direction (upstream / deps):
- Provide APIs that do not return descriptors with pointers to temporaries.
- Options:
  - Require caller-supplied storage for chained structs, or
  - Return a wrapper that owns the chained storage, or
  - Move to “merged descriptor” APIs that take the merged input directly and perform chaining internally in the consuming call.

### D2. `deps/luaz`: Thread + Registry Ref Ownership Hazards

Severity: High (UAF/leak potential), dependent on usage

Findings (from subagent audit):
- `deps/luaz/src/State.zig` `newThread()` (`lua_newthread`) pushes a thread object on the parent stack and returns a `lua_State*`.
- `deps/luaz/src/Lua.zig` `createThread()` returns a `Lua` wrapper but does not pin the thread in the registry and does not pop it from the parent stack.
  - If the parent stack is popped later, the thread can be GC’d leaving a dangling `lua_State*` (UAF).
  - If the parent stack is not popped, the thread object can remain on the stack (stack growth/leak).
- `deps/luaz/src/Lua.zig` ref-like types are plain copyable value types (`Ref`, `Table`, `Function`, `Buffer`, `Value`) with `deinit()` methods that unref but do not invalidate the ref, making accidental copies a double-unref/UAF risk.
- `deps/luaz/src/Lua.zig` `Table.Iterator.next()` only deinitializes the previous entry when `next()` is called again; breaking early can leak the last entry’s refs.

Fix direction (upstream / deps):
- Make thread creation pin a registry reference (and ensure balanced stack behavior).
- Make ref-holding types non-copyable by convention (store a “moved” sentinel) or explicitly invalidate on deinit to make double-deinit benign.
- Add `Iterator.deinit()` to ensure early-exit cleanup.

## Zig Memory Hotspots (Keyword-Based)

This is a heuristic list to highlight allocator-heavy files (keyword hit count for common alloc/free/deinit tokens).

Top 30 Zig files by keyword hits:

- `deps/luaz/src/Lua.zig`: 238
- `src/native_renderer/lifecycle.zig`: 171
- `tools/ui_codegen.zig`: 154
- `src/retained/core/node_store.zig`: 135
- `src/dvui.zig`: 116
- `tools/luau_smoke.zig`: 105
- `src/backends/wgpu.zig`: 98
- `src/retained/render/internal/renderers.zig`: 89
- `deps/luaz/examples/guided_tour.zig`: 88
- `src/window/window.zig`: 85
- `tools/luau_layout_dump_main.zig`: 80
- `src/retained/render/icon_registry.zig`: 66
- `src/utils/struct_ui.zig`: 66
- `src/text/font.zig`: 60
- `src/testing/mod.zig`: 59
- `src/render/texture.zig`: 55
- `src/retained/loaders/ui_json.zig`: 49
- `src/backends/pipeline/render.zig`: 45
- `deps/luaz/src/Debug.zig`: 41
- `src/render/path.zig`: 41
- `src/retained/render/cache.zig`: 38
- `src/retained/render/image_loader.zig`: 37
- `deps/luaz/src/alloc.zig`: 34
- `deps/solidluau/zig/solidluau_embed.zig`: 34
- `deps/luaz/src/stack.zig`: 31
- `src/backends/raylib-zig.zig`: 31
- `src/render/triangles.zig`: 29
- `src/utils/tracking_hash_map.zig`: 29
- `src/native_renderer/luau_ui.zig`: 28
- `src/widgets/LabelWidget.zig`: 28

## Appendix: Full File Index (Auto-Categorized)

Category is based on extension. For Zig files, `zig_alloc_bucket` is a keyword-hit heuristic (not a proof of safety).

| Path | Category | Zig alloc bucket | Zig keyword hits |
| --- | --- | --- | --- |
| `AGENTS.md` | doc |  |  |
| `LICENSE` | other |  |  |
| `MEMORY_AUDIT.md` | doc |  |  |
| `PERFORMANCE_AUDIT.md` | doc |  |  |
| `RELEASE_ARCHITECTURE_REVIEW.md` | doc |  |  |
| `UI_FEATURES.md` | doc |  |  |
| `assets/branding/zig-favicon.png` | asset |  |  |
| `assets/branding/zig-mark.svg` | asset(text) |  |  |
| `assets/fonts.zig` | code | none | 0 |
| `assets/fonts/Aleo/Aleo-Italic-VariableFont_wght.ttf` | asset |  |  |
| `assets/fonts/Aleo/Aleo-VariableFont_wght.ttf` | asset |  |  |
| `assets/fonts/Aleo/OFL.txt` | doc |  |  |
| `assets/fonts/Aleo/README.txt` | doc |  |  |
| `assets/fonts/Aleo/static/Aleo-Black.ttf` | asset |  |  |
| `assets/fonts/Aleo/static/Aleo-BlackItalic.ttf` | asset |  |  |
| `assets/fonts/Aleo/static/Aleo-Bold.ttf` | asset |  |  |
| `assets/fonts/Aleo/static/Aleo-BoldItalic.ttf` | asset |  |  |
| `assets/fonts/Aleo/static/Aleo-ExtraBold.ttf` | asset |  |  |
| `assets/fonts/Aleo/static/Aleo-ExtraBoldItalic.ttf` | asset |  |  |
| `assets/fonts/Aleo/static/Aleo-ExtraLight.ttf` | asset |  |  |
| `assets/fonts/Aleo/static/Aleo-ExtraLightItalic.ttf` | asset |  |  |
| `assets/fonts/Aleo/static/Aleo-Italic.ttf` | asset |  |  |
| `assets/fonts/Aleo/static/Aleo-Light.ttf` | asset |  |  |
| `assets/fonts/Aleo/static/Aleo-LightItalic.ttf` | asset |  |  |
| `assets/fonts/Aleo/static/Aleo-Medium.ttf` | asset |  |  |
| `assets/fonts/Aleo/static/Aleo-MediumItalic.ttf` | asset |  |  |
| `assets/fonts/Aleo/static/Aleo-Regular.ttf` | asset |  |  |
| `assets/fonts/Aleo/static/Aleo-SemiBold.ttf` | asset |  |  |
| `assets/fonts/Aleo/static/Aleo-SemiBoldItalic.ttf` | asset |  |  |
| `assets/fonts/Aleo/static/Aleo-Thin.ttf` | asset |  |  |
| `assets/fonts/Aleo/static/Aleo-ThinItalic.ttf` | asset |  |  |
| `assets/fonts/Consolas/Consolas.TTF` | asset |  |  |
| `assets/fonts/Inter/Inter-Bold.ttf` | asset |  |  |
| `assets/fonts/Inter/Inter-Regular.ttf` | asset |  |  |
| `assets/fonts/NotoSansKR-Regular.ttf` | asset |  |  |
| `assets/fonts/OpenDyslexic/FONTLOG.txt` | doc |  |  |
| `assets/fonts/OpenDyslexic/OFL-FAQ.txt` | doc |  |  |
| `assets/fonts/OpenDyslexic/OFL.txt` | doc |  |  |
| `assets/fonts/OpenDyslexic/README.md` | doc |  |  |
| `assets/fonts/OpenDyslexic/compiled/OpenDyslexic-Bold-Italic.otf` | asset |  |  |
| `assets/fonts/OpenDyslexic/compiled/OpenDyslexic-Bold.otf` | asset |  |  |
| `assets/fonts/OpenDyslexic/compiled/OpenDyslexic-Italic.otf` | asset |  |  |
| `assets/fonts/OpenDyslexic/compiled/OpenDyslexic-Regular.otf` | asset |  |  |
| `assets/fonts/PixelOperator/LICENSE.txt` | doc |  |  |
| `assets/fonts/PixelOperator/PixelOperator-Bold.ttf` | asset |  |  |
| `assets/fonts/PixelOperator/PixelOperator.ttf` | asset |  |  |
| `assets/fonts/PixelOperator/PixelOperator8-Bold.ttf` | asset |  |  |
| `assets/fonts/PixelOperator/PixelOperator8.ttf` | asset |  |  |
| `assets/fonts/PixelOperator/PixelOperatorHB.ttf` | asset |  |  |
| `assets/fonts/PixelOperator/PixelOperatorHB8.ttf` | asset |  |  |
| `assets/fonts/PixelOperator/PixelOperatorHBSC.ttf` | asset |  |  |
| `assets/fonts/PixelOperator/PixelOperatorMono-Bold.ttf` | asset |  |  |
| `assets/fonts/PixelOperator/PixelOperatorMono.ttf` | asset |  |  |
| `assets/fonts/PixelOperator/PixelOperatorMono8-Bold.ttf` | asset |  |  |
| `assets/fonts/PixelOperator/PixelOperatorMono8.ttf` | asset |  |  |
| `assets/fonts/PixelOperator/PixelOperatorMonoHB.ttf` | asset |  |  |
| `assets/fonts/PixelOperator/PixelOperatorMonoHB8.ttf` | asset |  |  |
| `assets/fonts/PixelOperator/PixelOperatorSC-Bold.ttf` | asset |  |  |
| `assets/fonts/PixelOperator/PixelOperatorSC.ttf` | asset |  |  |
| `assets/fonts/Pixelify_Sans/OFL.txt` | doc |  |  |
| `assets/fonts/Pixelify_Sans/PixelifySans-VariableFont_wght.ttf` | asset |  |  |
| `assets/fonts/Pixelify_Sans/README.txt` | doc |  |  |
| `assets/fonts/Pixelify_Sans/static/PixelifySans-Bold.ttf` | asset |  |  |
| `assets/fonts/Pixelify_Sans/static/PixelifySans-Medium.ttf` | asset |  |  |
| `assets/fonts/Pixelify_Sans/static/PixelifySans-Regular.ttf` | asset |  |  |
| `assets/fonts/Pixelify_Sans/static/PixelifySans-SemiBold.ttf` | asset |  |  |
| `assets/fonts/Segoe/Segoe-UI-Bold.TTF` | asset |  |  |
| `assets/fonts/Segoe/Segoe-UI-Italic.TTF` | asset |  |  |
| `assets/fonts/Segoe/Segoe-UI-Light.TTF` | asset |  |  |
| `assets/fonts/Segoe/Segoe-UI.TTF` | asset |  |  |
| `assets/fonts/bitstream-vera/COPYRIGHT.TXT` | doc |  |  |
| `assets/fonts/bitstream-vera/README.TXT` | doc |  |  |
| `assets/fonts/bitstream-vera/RELEASENOTES.TXT` | doc |  |  |
| `assets/fonts/bitstream-vera/Vera.ttf` | asset |  |  |
| `assets/fonts/bitstream-vera/VeraBI.ttf` | asset |  |  |
| `assets/fonts/bitstream-vera/VeraBd.ttf` | asset |  |  |
| `assets/fonts/bitstream-vera/VeraIt.ttf` | asset |  |  |
| `assets/fonts/bitstream-vera/VeraMoBI.ttf` | asset |  |  |
| `assets/fonts/bitstream-vera/VeraMoBd.ttf` | asset |  |  |
| `assets/fonts/bitstream-vera/VeraMoIt.ttf` | asset |  |  |
| `assets/fonts/bitstream-vera/VeraMono.ttf` | asset |  |  |
| `assets/fonts/bitstream-vera/VeraSe.ttf` | asset |  |  |
| `assets/fonts/bitstream-vera/VeraSeBd.ttf` | asset |  |  |
| `assets/fonts/bitstream-vera/local.conf` | config |  |  |
| `assets/fonts/hack/Hack-Bold.ttf` | asset |  |  |
| `assets/fonts/hack/Hack-BoldItalic.ttf` | asset |  |  |
| `assets/fonts/hack/Hack-Italic.ttf` | asset |  |  |
| `assets/fonts/hack/Hack-Regular.ttf` | asset |  |  |
| `assets/fonts/hack/LICENSE` | other |  |  |
| `assets/mod.zig` | code | none | 0 |
| `assets/sprite.png` | asset |  |  |
| `assets/windows/main.manifest` | config |  |  |
| `build.zig` | code | medium | 26 |
| `build.zig.zon` | config |  |  |
| `deepwiki/pages.json` | config |  |  |
| `deepwiki/parse.ts` | code |  |  |
| `deps/luaz/AGENTS.md` | doc |  |  |
| `deps/luaz/CHANGELOG.md` | doc |  |  |
| `deps/luaz/CONTRIBUTING.md` | doc |  |  |
| `deps/luaz/LICENSE` | other |  |  |
| `deps/luaz/LUAU_API.md` | doc |  |  |
| `deps/luaz/README.md` | doc |  |  |
| `deps/luaz/build.zig` | code | medium | 11 |
| `deps/luaz/build.zig.zon` | config |  |  |
| `deps/luaz/codecov.yml` | config |  |  |
| `deps/luaz/docs/logo.png` | asset |  |  |
| `deps/luaz/examples/guided_tour.zig` | code | hot | 88 |
| `deps/luaz/examples/runtime_loop.zig` | code | light | 2 |
| `deps/luaz/src/Compiler.zig` | code | medium | 10 |
| `deps/luaz/src/Debug.zig` | code | heavy | 41 |
| `deps/luaz/src/GC.zig` | code | medium | 13 |
| `deps/luaz/src/Lua.zig` | code | hot | 238 |
| `deps/luaz/src/State.zig` | code | medium | 27 |
| `deps/luaz/src/alloc.zig` | code | medium | 34 |
| `deps/luaz/src/assert.zig` | code | none | 0 |
| `deps/luaz/src/handler.cpp` | code |  |  |
| `deps/luaz/src/handler.h` | code |  |  |
| `deps/luaz/src/lib.zig` | code | none | 0 |
| `deps/luaz/src/stack.zig` | code | medium | 31 |
| `deps/luaz/src/userdata.zig` | code | medium | 18 |
| `deps/luaz/zlint.json` | config |  |  |
| `deps/msdf_zig/assets/msdf_placeholder_atlas.png` | asset |  |  |
| `deps/msdf_zig/assets/msdf_placeholder_font.json` | config |  |  |
| `deps/msdf_zig/msdf_zig.zig` | code | none | 0 |
| `deps/msdf_zig/src/msdf_zig.zig` | code | none | 0 |
| `deps/msdf_zig/src/shader.zig` | code | none | 0 |
| `deps/msdf_zig/src/shaders/msdf_text_ui.wgsl` | code |  |  |
| `deps/msdf_zig/src/shaders/msdf_text_world.wgsl` | code |  |  |
| `deps/msdf_zig/src/types.zig` | code | none | 0 |
| `deps/solidluau/README.md` | doc |  |  |
| `deps/solidluau/TASK.md` | doc |  |  |
| `deps/solidluau/ZIG_NATIVE_PLAN.md` | doc |  |  |
| `deps/solidluau/build-docs` | other |  |  |
| `deps/solidluau/build.zig` | code | light | 1 |
| `deps/solidluau/build.zig.zon` | config |  |  |
| `deps/solidluau/docs/solidluau-animation.mdx` | doc |  |  |
| `deps/solidluau/docs/solidluau-animationentry.mdx` | doc |  |  |
| `deps/solidluau/docs/solidluau-reactivity.mdx` | doc |  |  |
| `deps/solidluau/docs/solidluau-scheduler.mdx` | doc |  |  |
| `deps/solidluau/docs/solidluau-ui-dsl.mdx` | doc |  |  |
| `deps/solidluau/docs/solidluau-ui.mdx` | doc |  |  |
| `deps/solidluau/docs/solidluau-uientry.mdx` | doc |  |  |
| `deps/solidluau/docs/solidluau.mdx` | doc |  |  |
| `deps/solidluau/luau-docs/README.md` | doc |  |  |
| `deps/solidluau/luau-docs/index.ts` | code |  |  |
| `deps/solidluau/luau-docs/moonwave-extractor` | other |  |  |
| `deps/solidluau/scripts/build-docs.sh` | code |  |  |
| `deps/solidluau/solidluau_embed.zig` | code | none | 0 |
| `deps/solidluau/solidluau_modules.zig` | code | none | 0 |
| `deps/solidluau/src/ARCHITECTURE_REVIEW.md` | doc |  |  |
| `deps/solidluau/src/README.md` | doc |  |  |
| `deps/solidluau/src/animation.luau` | code |  |  |
| `deps/solidluau/src/animation/easing.luau` | code |  |  |
| `deps/solidluau/src/animation/engine.luau` | code |  |  |
| `deps/solidluau/src/animation/index.luau` | code |  |  |
| `deps/solidluau/src/animation/spring.luau` | code |  |  |
| `deps/solidluau/src/animation/tween.luau` | code |  |  |
| `deps/solidluau/src/core/reactivity.luau` | code |  |  |
| `deps/solidluau/src/core/scheduler.luau` | code |  |  |
| `deps/solidluau/src/solidluau.luau` | code |  |  |
| `deps/solidluau/src/ui.luau` | code |  |  |
| `deps/solidluau/src/ui/adapter_types.luau` | code |  |  |
| `deps/solidluau/src/ui/adapters/compat_ui.luau` | code |  |  |
| `deps/solidluau/src/ui/dsl.luau` | code |  |  |
| `deps/solidluau/src/ui/hydrate.luau` | code |  |  |
| `deps/solidluau/src/ui/index.luau` | code |  |  |
| `deps/solidluau/src/ui/renderer.luau` | code |  |  |
| `deps/solidluau/src/ui/types.luau` | code |  |  |
| `deps/solidluau/tests/luau/animation-mutableOutput-test.luau` | code |  |  |
| `deps/solidluau/tests/luau/reactivity-memo_invalidation_test.luau` | code |  |  |
| `deps/solidluau/tests/luau/reactivity-scope_unlink_test.luau` | code |  |  |
| `deps/solidluau/tests/luau/ui-dsl_tag_call_test.luau` | code |  |  |
| `deps/solidluau/tests/luau/ui-flat-props_cutover_test.luau` | code |  |  |
| `deps/solidluau/tests/luau/ui-patch_test.luau` | code |  |  |
| `deps/solidluau/vide/OVERVIEW.md` | doc |  |  |
| `deps/solidluau/vide/README.md` | doc |  |  |
| `deps/solidluau/vide/docs/advanced/dynamic-scopes.md` | doc |  |  |
| `deps/solidluau/vide/docs/api/animation.md` | doc |  |  |
| `deps/solidluau/vide/docs/api/creation.md` | doc |  |  |
| `deps/solidluau/vide/docs/api/reactivity-core.md` | doc |  |  |
| `deps/solidluau/vide/docs/api/reactivity-dynamic.md` | doc |  |  |
| `deps/solidluau/vide/docs/api/reactivity-utility.md` | doc |  |  |
| `deps/solidluau/vide/docs/api/strict-mode.md` | doc |  |  |
| `deps/solidluau/vide/docs/crash-course/1-introduction.md` | doc |  |  |
| `deps/solidluau/vide/docs/crash-course/10-cleanup.md` | doc |  |  |
| `deps/solidluau/vide/docs/crash-course/11-dynamic-scopes.md` | doc |  |  |
| `deps/solidluau/vide/docs/crash-course/12-actions.md` | doc |  |  |
| `deps/solidluau/vide/docs/crash-course/13-strict-mode.md` | doc |  |  |
| `deps/solidluau/vide/docs/crash-course/14-concepts.md` | doc |  |  |
| `deps/solidluau/vide/docs/crash-course/2-creation.md` | doc |  |  |
| `deps/solidluau/vide/docs/crash-course/3-components.md` | doc |  |  |
| `deps/solidluau/vide/docs/crash-course/4-source.md` | doc |  |  |
| `deps/solidluau/vide/docs/crash-course/5-effect.md` | doc |  |  |
| `deps/solidluau/vide/docs/crash-course/6-scope.md` | doc |  |  |
| `deps/solidluau/vide/docs/crash-course/7-reactive-component.md` | doc |  |  |
| `deps/solidluau/vide/docs/crash-course/8-implicit-effect.md` | doc |  |  |
| `deps/solidluau/vide/docs/crash-course/9-derived-source.md` | doc |  |  |
| `deps/solidluau/vide/init.luau` | code |  |  |
| `deps/solidluau/vide/src/action.luau` | code |  |  |
| `deps/solidluau/vide/src/apply.luau` | code |  |  |
| `deps/solidluau/vide/src/batch.luau` | code |  |  |
| `deps/solidluau/vide/src/branch.luau` | code |  |  |
| `deps/solidluau/vide/src/changed.luau` | code |  |  |
| `deps/solidluau/vide/src/cleanup.luau` | code |  |  |
| `deps/solidluau/vide/src/context.luau` | code |  |  |
| `deps/solidluau/vide/src/create.luau` | code |  |  |
| `deps/solidluau/vide/src/defaults.luau` | code |  |  |
| `deps/solidluau/vide/src/derive.luau` | code |  |  |
| `deps/solidluau/vide/src/effect.luau` | code |  |  |
| `deps/solidluau/vide/src/flags.luau` | code |  |  |
| `deps/solidluau/vide/src/graph.luau` | code |  |  |
| `deps/solidluau/vide/src/implicit_effect.luau` | code |  |  |
| `deps/solidluau/vide/src/indexes.luau` | code |  |  |
| `deps/solidluau/vide/src/init.luau` | code |  |  |
| `deps/solidluau/vide/src/lib.luau` | code |  |  |
| `deps/solidluau/vide/src/mount.luau` | code |  |  |
| `deps/solidluau/vide/src/read.luau` | code |  |  |
| `deps/solidluau/vide/src/root.luau` | code |  |  |
| `deps/solidluau/vide/src/show.luau` | code |  |  |
| `deps/solidluau/vide/src/source.luau` | code |  |  |
| `deps/solidluau/vide/src/spring.luau` | code |  |  |
| `deps/solidluau/vide/src/switch.luau` | code |  |  |
| `deps/solidluau/vide/src/timeout.luau` | code |  |  |
| `deps/solidluau/vide/src/untrack.luau` | code |  |  |
| `deps/solidluau/vide/src/values.luau` | code |  |  |
| `deps/solidluau/vide/test/benchmarks.luau` | code |  |  |
| `deps/solidluau/vide/test/create-types.luau` | code |  |  |
| `deps/solidluau/vide/test/mock.luau` | code |  |  |
| `deps/solidluau/vide/test/spring-test.luau` | code |  |  |
| `deps/solidluau/vide/test/stacktrace-test.luau` | code |  |  |
| `deps/solidluau/vide/test/testkit.luau` | code |  |  |
| `deps/solidluau/vide/test/tests.luau` | code |  |  |
| `deps/solidluau/zig/solidluau_embed.zig` | code | medium | 34 |
| `deps/solidluau/zig/solidluau_modules.zig` | code | none | 0 |
| `deps/solidluau/zig/solidluau_tests.zig` | code | medium | 26 |
| `deps/wgpu_native_zig/LICENSE` | other |  |  |
| `deps/wgpu_native_zig/README.md` | doc |  |  |
| `deps/wgpu_native_zig/build.zig` | code | light | 8 |
| `deps/wgpu_native_zig/build.zig.zon` | config |  |  |
| `deps/wgpu_native_zig/examples/bmp.zig` | code | light | 1 |
| `deps/wgpu_native_zig/examples/triangle/shader.wgsl` | code |  |  |
| `deps/wgpu_native_zig/examples/triangle/triangle.zig` | code | medium | 20 |
| `deps/wgpu_native_zig/src/adapter.zig` | code | light | 3 |
| `deps/wgpu_native_zig/src/async.zig` | code | light | 5 |
| `deps/wgpu_native_zig/src/bind_group.zig` | code | light | 2 |
| `deps/wgpu_native_zig/src/buffer.zig` | code | light | 2 |
| `deps/wgpu_native_zig/src/chained_struct.zig` | code | none | 0 |
| `deps/wgpu_native_zig/src/command_encoder.zig` | code | light | 4 |
| `deps/wgpu_native_zig/src/device.zig` | code | medium | 18 |
| `deps/wgpu_native_zig/src/global.zig` | code | none | 0 |
| `deps/wgpu_native_zig/src/instance.zig` | code | medium | 13 |
| `deps/wgpu_native_zig/src/limits.zig` | code | none | 0 |
| `deps/wgpu_native_zig/src/log.zig` | code | none | 0 |
| `deps/wgpu_native_zig/src/misc.zig` | code | light | 2 |
| `deps/wgpu_native_zig/src/pipeline.zig` | code | light | 5 |
| `deps/wgpu_native_zig/src/query_set.zig` | code | light | 2 |
| `deps/wgpu_native_zig/src/queue.zig` | code | light | 1 |
| `deps/wgpu_native_zig/src/render_bundle.zig` | code | light | 2 |
| `deps/wgpu_native_zig/src/root.zig` | code | none | 0 |
| `deps/wgpu_native_zig/src/sampler.zig` | code | light | 1 |
| `deps/wgpu_native_zig/src/shader.zig` | code | light | 1 |
| `deps/wgpu_native_zig/src/surface.zig` | code | medium | 15 |
| `deps/wgpu_native_zig/src/texture.zig` | code | light | 4 |
| `deps/wgpu_native_zig/test-all` | other |  |  |
| `deps/wgpu_native_zig/tests/compute.wgsl` | code |  |  |
| `deps/wgpu_native_zig/tests/compute.zig` | code | medium | 21 |
| `deps/wgpu_native_zig/tests/compute_c.zig` | code | light | 1 |
| `deps/zig-yoga/build.zig` | code | light | 1 |
| `deps/zig-yoga/build.zig.zon` | config |  |  |
| `deps/zig-yoga/src/enums.zig` | code | none | 0 |
| `deps/zig-yoga/src/root.zig` | code | light | 7 |
| `docs/LAYOUT_TREE_DUMP.md` | doc |  |  |
| `docs/RETAINED.md` | doc |  |  |
| `docs/RETAINED_API.md` | doc |  |  |
| `docs/UI_PRIMITIVES.md` | doc |  |  |
| `docs/luau-findings/high-binary-event-payload-contract.md` | doc |  |  |
| `docs/luau-findings/high-event-ring-saturation-after-lua-teardown.md` | doc |  |  |
| `docs/luau-findings/high-stale-object-prop-clear-semantics.md` | doc |  |  |
| `favicon.png` | asset |  |  |
| `luau/_smoke/checkbox.luau` | code |  |  |
| `luau/_smoke/ui_refs.luau` | code |  |  |
| `luau/_tests/conditional_visibility.luau` | code |  |  |
| `luau/_tests/disposal_and_batching.luau` | code |  |  |
| `luau/_tests/keyed_lists.luau` | code |  |  |
| `luau/_tests/mock_ui.luau` | code |  |  |
| `luau/_tests/reconciler.luau` | code |  |  |
| `luau/_tests/test_scheduler.luau` | code |  |  |
| `luau/_tests/testkit.luau` | code |  |  |
| `luau/app.luau` | code |  |  |
| `luau/components/bar.luau` | code |  |  |
| `luau/components/checkbox.luau` | code |  |  |
| `luau/components/toggle.luau` | code |  |  |
| `luau/index.luau` | code |  |  |
| `luau/ui/cn.luau` | code |  |  |
| `luau/ui/load_ui.luau` | code |  |  |
| `luau/ui/types.luau` | code |  |  |
| `luau/ui_features_image_1.png` | asset |  |  |
| `luau/ui_gen/app_ui.luau` | code |  |  |
| `luau/ui_json/app.json` | config |  |  |
| `snapshots/app.layout.json` | config |  |  |
| `solidluau_embedded.zig` | code | none | 0 |
| `src/accessibility/accesskit.zig` | code | medium | 24 |
| `src/accessibility/mod.zig` | code | none | 0 |
| `src/backends/backend.zig` | code | light | 4 |
| `src/backends/common.zig` | code | none | 0 |
| `src/backends/mod.zig` | code | none | 0 |
| `src/backends/pipeline/compute.zig` | code | medium | 26 |
| `src/backends/pipeline/depth.zig` | code | light | 7 |
| `src/backends/pipeline/geometry.zig` | code | medium | 18 |
| `src/backends/pipeline/main.zig` | code | none | 0 |
| `src/backends/pipeline/render.zig` | code | heavy | 45 |
| `src/backends/pipeline/swap_chain.zig` | code | medium | 22 |
| `src/backends/pipeline/types.zig` | code | light | 1 |
| `src/backends/raylib-zig.zig` | code | medium | 31 |
| `src/backends/webgpu.zig` | code | none | 0 |
| `src/backends/webgpu/mod.zig` | code | medium | 14 |
| `src/backends/webgpu/platform_macos.zig` | code | none | 0 |
| `src/backends/webgpu/platform_macos_metal_layer.m` | code |  |  |
| `src/backends/webgpu/platform_windows.zig` | code | none | 0 |
| `src/backends/wgpu.zig` | code | hot | 98 |
| `src/core/color.zig` | code | medium | 16 |
| `src/core/data.zig` | code | medium | 14 |
| `src/core/enums.zig` | code | light | 1 |
| `src/core/mod.zig` | code | none | 0 |
| `src/core/options.zig` | code | light | 2 |
| `src/core/point.zig` | code | none | 0 |
| `src/core/rect.zig` | code | medium | 16 |
| `src/core/size.zig` | code | none | 0 |
| `src/core/vertex.zig` | code | none | 0 |
| `src/dvui.zig` | code | hot | 116 |
| `src/layout/easing.zig` | code | none | 0 |
| `src/layout/layout.zig` | code | light | 1 |
| `src/layout/mod.zig` | code | none | 0 |
| `src/layout/scroll_info.zig` | code | none | 0 |
| `src/main.zig` | code | light | 5 |
| `src/native_renderer/commands.zig` | code | medium | 14 |
| `src/native_renderer/event_payload.zig` | code | light | 3 |
| `src/native_renderer/lifecycle.zig` | code | hot | 171 |
| `src/native_renderer/luau_ui.zig` | code | medium | 28 |
| `src/native_renderer/mod.zig` | code | none | 0 |
| `src/native_renderer/profiling.zig` | code | light | 2 |
| `src/native_renderer/types.zig` | code | light | 5 |
| `src/native_renderer/utils.zig` | code | none | 0 |
| `src/native_renderer/window.zig` | code | medium | 19 |
| `src/platform/dialogs.zig` | code | light | 2 |
| `src/platform/io_compat.zig` | code | light | 2 |
| `src/platform/mod.zig` | code | none | 0 |
| `src/render/jpg_encoder.zig` | code | none | 0 |
| `src/render/mod.zig` | code | none | 0 |
| `src/render/path.zig` | code | heavy | 41 |
| `src/render/png_encoder.zig` | code | none | 0 |
| `src/render/render.zig` | code | medium | 16 |
| `src/render/texture.zig` | code | heavy | 55 |
| `src/render/triangles.zig` | code | medium | 29 |
| `src/retained/core/ARCHITECTURE.md` | doc |  |  |
| `src/retained/core/geometry.zig` | code | none | 0 |
| `src/retained/core/layout.zig` | code | light | 6 |
| `src/retained/core/media.zig` | code | none | 0 |
| `src/retained/core/node_store.zig` | code | hot | 135 |
| `src/retained/core/types.zig` | code | none | 0 |
| `src/retained/core/visual.zig` | code | none | 0 |
| `src/retained/events/ARCHITECTURE.md` | doc |  |  |
| `src/retained/events/drag_drop.zig` | code | light | 2 |
| `src/retained/events/focus.zig` | code | medium | 19 |
| `src/retained/events/mod.zig` | code | medium | 23 |
| `src/retained/hit_test.zig` | code | none | 0 |
| `src/retained/layout/ARCHITECTURE.md` | doc |  |  |
| `src/retained/layout/flex.zig` | code | light | 3 |
| `src/retained/layout/measure.zig` | code | light | 5 |
| `src/retained/layout/mod.zig` | code | light | 5 |
| `src/retained/layout/text_wrap.zig` | code | medium | 17 |
| `src/retained/layout/yoga.zig` | code | light | 3 |
| `src/retained/loaders/ui_json.zig` | code | heavy | 49 |
| `src/retained/loaders/ui_json_test.zig` | code | light | 8 |
| `src/retained/mod.zig` | code | medium | 11 |
| `src/retained/render/cache.zig` | code | medium | 38 |
| `src/retained/render/direct.zig` | code | light | 8 |
| `src/retained/render/icon_registry.zig` | code | heavy | 66 |
| `src/retained/render/image_loader.zig` | code | medium | 37 |
| `src/retained/render/internal/derive.zig` | code | none | 0 |
| `src/retained/render/internal/hover.zig` | code | medium | 11 |
| `src/retained/render/internal/interaction.zig` | code | light | 4 |
| `src/retained/render/internal/overlay.zig` | code | medium | 14 |
| `src/retained/render/internal/renderers.zig` | code | hot | 89 |
| `src/retained/render/internal/runtime.zig` | code | medium | 15 |
| `src/retained/render/internal/state.zig` | code | none | 0 |
| `src/retained/render/internal/visual_sync.zig` | code | light | 2 |
| `src/retained/render/mod.zig` | code | medium | 12 |
| `src/retained/render/transitions.zig` | code | none | 0 |
| `src/retained/style/apply.zig` | code | light | 1 |
| `src/retained/style/colors.zig` | code | none | 0 |
| `src/retained/style/mod.zig` | code | none | 0 |
| `src/retained/style/tailwind.zig` | code | medium | 15 |
| `src/retained/style/tailwind/parse.zig` | code | none | 0 |
| `src/retained/style/tailwind/parse_color_typography.zig` | code | none | 0 |
| `src/retained/style/tailwind/parse_layout.zig` | code | none | 0 |
| `src/retained/style/tailwind/types.zig` | code | none | 0 |
| `src/testing/mod.zig` | code | heavy | 59 |
| `src/text/font.zig` | code | heavy | 60 |
| `src/text/mod.zig` | code | none | 0 |
| `src/text/selection.zig` | code | light | 9 |
| `src/theming/mod.zig` | code | light | 1 |
| `src/theming/shadcn.zon` | config |  |  |
| `src/theming/theme.zig` | code | medium | 20 |
| `src/utils/alloc.zig` | code | medium | 10 |
| `src/utils/cache_buster.zig` | code | light | 4 |
| `src/utils/mod.zig` | code | light | 2 |
| `src/utils/struct_ui.zig` | code | heavy | 66 |
| `src/utils/tracking_hash_map.zig` | code | medium | 29 |
| `src/widgets/AnimateWidget.zig` | code | light | 4 |
| `src/widgets/BoxWidget.zig` | code | light | 5 |
| `src/widgets/ButtonWidget.zig` | code | light | 4 |
| `src/widgets/FlexBoxWidget.zig` | code | medium | 18 |
| `src/widgets/GizmoWidget.zig` | code | light | 6 |
| `src/widgets/IconWidget.zig` | code | light | 4 |
| `src/widgets/LabelWidget.zig` | code | medium | 28 |
| `src/widgets/MenuItemWidget.zig` | code | light | 8 |
| `src/widgets/MenuWidget.zig` | code | light | 5 |
| `src/widgets/ScaleWidget.zig` | code | light | 5 |
| `src/widgets/ScrollBarWidget.zig` | code | light | 5 |
| `src/widgets/SelectionWidget.zig` | code | light | 4 |
| `src/widgets/SelectionWidget/drawing.zig` | code | light | 2 |
| `src/widgets/SelectionWidget/events.zig` | code | light | 3 |
| `src/widgets/SelectionWidget/transform.zig` | code | none | 0 |
| `src/widgets/mod.zig` | code | none | 0 |
| `src/widgets/widget.zig` | code | none | 0 |
| `src/widgets/widget_data.zig` | code | light | 6 |
| `src/window/app.zig` | code | light | 3 |
| `src/window/debug.zig` | code | light | 8 |
| `src/window/dragging.zig` | code | none | 0 |
| `src/window/event.zig` | code | light | 1 |
| `src/window/mod.zig` | code | none | 0 |
| `src/window/subwindows.zig` | code | light | 6 |
| `src/window/window.zig` | code | hot | 85 |
| `tools/layoutdump_scenes.json` | config |  |  |
| `tools/luau_layout_dump_main.zig` | code | hot | 80 |
| `tools/luau_smoke.zig` | code | hot | 105 |
| `tools/ui_codegen.zig` | code | hot | 154 |
| `vendor/stb/stb_image.h` | code |  |  |
| `vendor/stb/stb_image_impl.c` | code |  |  |
| `vendor/stb/stb_image_libc.c` | code |  |  |
| `vendor/stb/stb_image_write.h` | code |  |  |
| `vendor/stb/stb_image_write_impl.c` | code |  |  |
| `vendor/stb/stb_truetype.h` | code |  |  |
| `vendor/stb/stb_truetype_impl.c` | code |  |  |
| `vendor/stb/stb_truetype_libc.c` | code |  |  |
| `zig_build_simple.sh` | code |  |  |
