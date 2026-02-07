# DVUI Runtime Performance Audit

Date: 2026-02-07

Repo:
- Superproject: `dvui` @ `c3f1d0719a426039b2dbf28bfa9365c93a993696`
- Submodules (checked out in this workspace):
  - `deps/solidluau` @ `65a8bb7`
  - `deps/luaz` @ `479d5dc`
  - `deps/wgpu_native_zig` @ `8f1ae3e`

Build sanity check:
- `./zig_build_simple.sh` exited `0`.

## Scope

This audit focuses on **critical** and **high severity** runtime performance risks that can affect product release readiness:

- Frame-time CPU overhead (per-frame or per-node hot-path work)
- Avoidable allocations/copies in hot paths
- Algorithmic complexity traps (O(N) per frame where it should be O(1), O(N^2) under realistic input)
- Unbounded caches / long-session memory growth leading to degraded performance
- Startup stalls/hangs that impact perceived performance and release reliability

Directories reviewed (tracked files only; ignores `.gitignore`d output like `zig-out/`, `.zig-cache/`, etc.):
- `src/` (engine/runtime)
- `deps/` (vendored deps + submodules)
- `vendor/` (vendored C)
- `luau/` (demo/app scripts)
- `assets/` (embedded runtime assets)
- `tools/`, `docs/`, `deepwiki/`, `.github/`, `snapshots/` (non-runtime, but reviewed for release/perf relevance)

## Method

- Enumerated all tracked files via `git ls-files` in the superproject, and `git -C <submodule> ls-files` for submodules.
- For each major directory, performed targeted scans for known perf hazards (allocations in render loops, full-tree scans, frequent timestamping/logging, unbounded caches) and then manually inspected the hottest runtime paths.
- Where a suspected issue is structural (not a single “bad line”), evidence is presented as a set of file/line references plus the call-site chain.

## Executive Summary (Release-Risk Performance Findings)

### Critical

1. **Retained pipeline has per-frame full-tree recursive scans even when nothing changes**
   - `src/retained/layout/mod.zig:30` calls `hasActiveLayoutAnimations()` and (often) `hasMissingLayout()` every frame.
   - Both are recursive tree walks: `src/retained/layout/mod.zig:448` and `src/retained/layout/mod.zig:458`.
   - Impact: baseline O(N) CPU cost per frame for retained UIs; scales poorly with node count.

2. **High-resolution timing instrumentation is effectively always on in retained rendering and scales with node count**
   - Native renderer always passes a non-null timings struct: `src/native_renderer/window.zig:377` to `src/native_renderer/window.zig:381`.
   - Retained render measures phases via `std.time.nanoTimestamp()` unconditionally in multiple places: `src/retained/render/mod.zig:57` and many per-node sites in `src/retained/render/internal/renderers.zig` (e.g. `src/retained/render/internal/renderers.zig:583`, `src/retained/render/internal/renderers.zig:669`, `src/retained/render/internal/renderers.zig:738`).
   - Impact: large steady-state overhead at high node counts; on Windows this can easily become measurable frame time.

### High

3. **Retained rendering rebuilds paragraph/button text buffers every frame (tree traversal + allocations + copies)**
   - Paragraph: `src/retained/render/internal/renderers.zig:627` to `src/retained/render/internal/renderers.zig:632`.
   - Button caption: `src/retained/render/internal/renderers.zig:762` (via `buildText()` at `src/retained/render/internal/renderers.zig:1820`).
   - Impact: O(total text bytes in subtree) per frame for common tags (`p`, `h1`/`h2`/`h3`, `button`), even when text is unchanged.

4. **Font atlas regeneration is full-rebuild-on-new-glyph and is triggered unconditionally for non-ascii glyphs (including MSDF path)**
   - `src/text/font.zig:775` to `src/text/font.zig:788` invalidates the entire atlas on first encounter of each non-ascii glyph.
   - `src/text/font.zig:616` to `src/text/font.zig:763` rebuilds the atlas by rasterizing every glyph in the cache.
   - For MSDF fonts, invalidation causes re-decoding/re-upload of the same PNG atlas: `src/text/font.zig:619` to `src/text/font.zig:633`.
   - Impact: stutter spikes when encountering new glyphs; worst-case pathological when rendering diverse Unicode text.

5. **Retained frame scratch allocator is created and fully deinitialized every frame**
   - `src/retained/render/mod.zig:63` to `src/retained/render/mod.zig:65`.
   - Impact: allocator churn; prevents reuse of scratch capacity across frames; can amplify allocator costs under load.

6. **Retained paint-cache/dirty-region system appears unused; background rendering allocates transient geometry per call**
   - Paint cache update entrypoint has no call sites:
     - Defined at `src/retained/render/cache.zig:239` but not referenced elsewhere.
   - Background fallback builds transient `std.ArrayList` buffers:
     - `src/retained/render/cache.zig:220` to `src/retained/render/cache.zig:236`.
   - Impact: per-node transient allocations/copies in a core render path, even when geometry is stable.

7. **Unbounded global caches can grow without limit in long-running sessions**
   - Tailwind spec cache: `src/retained/style/tailwind.zig:23` to `src/retained/style/tailwind.zig:71`.
   - Image cache: `src/retained/render/image_loader.zig:8` to `src/retained/render/image_loader.zig:73`.
   - Icon cache: `src/retained/render/icon_registry.zig:31` to `src/retained/render/icon_registry.zig:60`.
   - Impact: memory growth; eventual allocator pressure and degraded performance.

8. **WGPU texture upload path violates WebGPU `bytes_per_row` alignment requirement**
   - Create: `src/backends/wgpu.zig:1120`.
   - Update: `src/backends/wgpu.zig:513`.
   - Impact: validation failures or undefined behavior; common widths will break. This can turn into perf issues (fallback paths, retries) and release failures.

9. **Synchronous adapter/device acquisition with zero poll interval can busy-spin or hang**
   - `src/backends/pipeline/swap_chain.zig:43` and `src/backends/pipeline/swap_chain.zig:75`.
   - Impact: startup hang/busy CPU on platforms where callbacks don’t resolve promptly.

## Detailed Findings

### 1) Retained Layout: Per-Frame Full-Tree Scans (Critical)

**Evidence**

- `src/retained/layout/mod.zig:57` to `src/retained/layout/mod.zig:65`:
  - `has_layout_animation = hasActiveLayoutAnimations(store, root)` is computed every frame.
  - `missing_layout = hasMissingLayout(store, root)` is computed in the steady-state path.
- `src/retained/layout/mod.zig:448` to `src/retained/layout/mod.zig:456` is a recursive tree walk.
- `src/retained/layout/mod.zig:458` to `src/retained/layout/mod.zig:466` is another recursive tree walk.

**Why this is high impact**

Even when nothing changes, retained mode pays O(N) traversal cost each frame. This is a fundamental scaling problem: increasing node count increases baseline frame time.

**Release risk**

- Large retained trees (real apps) will suffer a hard CPU floor independent of actual changes.
- This also compounds with other per-frame O(N) passes (hit testing, rendering).

**Fix direction (minimal, core-first)**

- Replace `hasMissingLayout()` with a tracked boolean (or a root-level “layout complete” version flag) updated during layout.
- Replace `hasActiveLayoutAnimations()` with a counter or a subtree flag updated when spacing transitions start/stop.
- Avoid doing full-tree scans in the “no layout dirty” fast path.

### 2) Retained Timing Instrumentation Is Always-On and Per-Node (Critical)

**Evidence**

- Native frame loop always passes timings:
  - `src/native_renderer/window.zig:377` to `src/native_renderer/window.zig:381`.
- Retained render always takes timestamps for major phases:
  - `src/retained/render/mod.zig:57` to `src/retained/render/mod.zig:61`.
  - `src/retained/render/mod.zig:77` to `src/retained/render/mod.zig:81`.
  - `src/retained/render/mod.zig:84` to `src/retained/render/mod.zig:88`.
- Retained renderers take additional per-node timestamps when `runtime.timings != null`:
  - Background: `src/retained/render/internal/renderers.zig:583` to `src/retained/render/internal/renderers.zig:590`.
  - Paragraph text: `src/retained/render/internal/renderers.zig:669` to `src/retained/render/internal/renderers.zig:697`.
  - Text nodes: `src/retained/render/internal/renderers.zig:738` to `src/retained/render/internal/renderers.zig:746`.

**Why this is high impact**

`std.time.nanoTimestamp()` is not free, and per-node timing can become a dominant cost at scale.

**Fix direction (minimal, core-first)**

- Make timings collection opt-in:
  - Pass `null` for timings in `src/native_renderer/window.zig` unless actively profiling.
- Gate timestamp calls so they are not executed when timings are off:
  - In `src/retained/render/mod.zig`, only call `nanoTimestamp()` when timings != null.

### 3) Retained Hit-Testing Always Scans the Whole Tree (High)

**Evidence**

- Per frame hit test: `src/retained/render/mod.zig:74` to `src/retained/render/mod.zig:82`.
- Hit-test implementation is a full recursive traversal (clip-prunes only when clip is active):
  - `src/retained/hit_test.zig:13` to `src/retained/hit_test.zig:78`.

**Impact**

Baseline O(N) per-frame cost when input is enabled, even if mouse hasn’t moved.

**Fix direction**

- Skip hit-test when `current_mouse == runtime.last_mouse_pt` and there is no relevant version change.
- Consider caching bounds per subtree for pointer picking, so it can prune earlier.

### 4) Per-Frame Text Aggregation (Paragraphs/Buttons) (High)

**Evidence**

- Paragraph rebuilds a `std.ArrayList(u8)` every frame:
  - `src/retained/render/internal/renderers.zig:627` to `src/retained/render/internal/renderers.zig:632`.
- Buttons rebuild concatenated caption text every frame:
  - `src/retained/render/internal/renderers.zig:762` and `src/retained/render/internal/renderers.zig:1820`.

**Impact**

- O(subtree size) traversal and memory writes every frame.
- GC/allocator pressure from repeatedly allocating and copying buffers.

**Fix direction**

- Cache aggregated text on the node keyed by `subtree_version` (or a dedicated “text subtree version”).
- For buttons, avoid concatenation entirely by using the first text child or by rendering child text nodes directly.

### 5) Font Atlas Rebuild Strategy (High)

**Evidence**

- New glyph invalidates atlas unconditionally:
  - `src/text/font.zig:775` to `src/text/font.zig:788`.
- Atlas rebuild is full-raster of all cached glyphs:
  - `src/text/font.zig:635` to `src/text/font.zig:763`.
- MSDF atlas path decodes PNG each rebuild:
  - `src/text/font.zig:619` to `src/text/font.zig:633`.

**Impact**

- “First time” cost for new Unicode glyphs becomes a multi-glyph rebuild.
- For MSDF, unnecessary texture destruction/recreate introduces avoidable stalls.

**Fix direction**

- Only invalidate/rebuild atlas for raster fonts.
- Move toward incremental atlas updates (pack new glyph + update subregion), or reserve space up-front for common glyph ranges.

### 6) Retained Scratch Arena Lifetime (High)

**Evidence**

- `src/retained/render/mod.zig:63` to `src/retained/render/mod.zig:65` creates an arena every frame and deinitializes it.

**Impact**

Repeated allocate/free of arena chunks prevents amortization and can fragment upstream allocators.

**Fix direction**

- Store a scratch arena in `RenderRuntime` and `reset(.retain_capacity)` each frame.

### 7) Retained Paint Cache Appears Unused (High)

**Evidence**

- `src/retained/render/cache.zig:239` defines `updatePaintCache(...)`, but the symbol has no call sites in `src/retained/` (static scan shows only the definition).
- Background rendering fallback allocates transient `std.ArrayList` buffers each call:
  - `src/retained/render/cache.zig:220` to `src/retained/render/cache.zig:236`.

**Impact**

Even with stable geometry, core background rendering may allocate and build vertex/index buffers per element per frame (for the non-rounded path). That’s avoidable churn on a hot path.

**Fix direction**

- Either wire in `updatePaintCache` (with a strict “only when dirty” policy) or remove the dynamic allocation in the fallback path by using fixed-size stack buffers for the simple-rect case.

### 8) Unbounded Global Caches (High)

**Evidence**

- Tailwind spec cache uses `c_allocator`, duplicates keys, no eviction:
  - `src/retained/style/tailwind.zig:23` to `src/retained/style/tailwind.zig:71`.
- Image cache duplicates and holds file bytes, no eviction:
  - `src/retained/render/image_loader.zig:8` to `src/retained/render/image_loader.zig:73`.
- Icon cache holds vector/icon bytes, no eviction:
  - `src/retained/render/icon_registry.zig:31` and surrounding.

**Impact**

Long sessions that dynamically generate many class strings / image paths / icon names will see unbounded memory growth.

**Fix direction**

- Add size caps and eviction (LRU) or explicit `clearCache()` APIs tied to application lifecycle.

### 9) WGPU Texture Upload Alignment (High)

**Evidence**

- `bytes_per_row = width * 4` in creation: `src/backends/wgpu.zig:1120`.
- Same pattern in update: `src/backends/wgpu.zig:513`.

**Impact**

WebGPU requires `bytes_per_row` to be 256-byte aligned; most widths violate this. This can break rendering and/or introduce expensive fallback behavior.

### 10) Adapter/Device Request Sync Busy-Spin/Hang (High)

**Evidence**

- `requestAdapterSync(..., 0)` / `requestDeviceSync(..., 0)`:
  - `src/backends/pipeline/swap_chain.zig:43`
  - `src/backends/pipeline/swap_chain.zig:75`

**Impact**

Startup time can become unbounded; CPU can spin hard on failure modes.

## Medium Severity / Watchlist

- `src/window/window.zig:851` to `src/window/window.zig:858` uses a `sleep(0)` loop to “spin” into a timing target.
  - Risk: elevated CPU usage on platforms where `sleep(0)` does not truly yield.
- `src/retained/render/internal/state.zig:141` to `src/retained/render/internal/state.zig:145` computes `nodeIdExtra()` using Wyhash each call.
  - Risk: extra hashing overhead per node per frame; consider using `@intCast(node_id)` or caching the computed value.
- `src/retained/render/internal/renderers.zig:1119` to `src/retained/render/internal/renderers.zig:1124` calls `dvui.imageSize()` (stb header parse) when `min_size_content` isn’t supplied.
  - Risk: repeated image header parsing per frame; consider caching intrinsic size per image resource.
- `src/render/texture.zig:172` uses `h.update(@ptrCast(pixels.rgba))` for `.pixelsPMA` `.bytes` invalidation.
  - Risk: likely hashes the wrong byte count; can cause stale textures and wasted redraws.

## Large Embedded Assets (Perf/Distribution)

`assets/fonts.zig` embeds multiple fonts by default, including very large fonts:

- Largest tracked assets (bytes):
  - `assets/fonts/NotoSansKR-Regular.ttf` (6,192,764)
  - `assets/fonts/Segoe/Segoe-UI.TTF` (975,088)
  - `assets/fonts/Segoe/Segoe-UI-Bold.TTF` (964,768)
  - `assets/fonts/Segoe/Segoe-UI-Light.TTF` (925,552)

Impact:
- Larger binaries, slower downloads, higher working set at startup.

Fix direction:
- Provide a build option to exclude builtin fonts, and/or lazy-load fonts from disk for product builds.

## Directory-By-Directory Notes

### Root

- `RELEASE_AUDIT.md` contains additional non-perf release blockers; this audit focuses on runtime performance only.

### `src/`

Primary runtime hot paths identified:
- `src/native_renderer/window.zig` (frame loop)
- `src/retained/render/mod.zig` and `src/retained/render/internal/renderers.zig` (retained frame cost)
- `src/retained/layout/mod.zig` (layout gating logic)
- `src/text/font.zig` (font atlas behavior)

### `deps/`

- `deps/solidluau` (Luau reactive renderer): generally reactive/diff-driven, but patch batching and dynamic prop resolution still imply per-frame work when animations/signals update.
- `deps/wgpu_native_zig` and `deps/luaz`: treated as upstream deps; reviewed for “obvious” hot-loop patterns and callbacks that can crash/hang.

### `luau/`

- Demo scripts; perf impact depends on how closely product code matches these patterns. Watch for per-frame allocations and deep recursion.

### `vendor/`

- stb headers and implementations; standard performance characteristics.

### `assets/`

- Large embedded fonts impact artifact size and may impact startup and memory.

### `tools/`, `docs/`, `deepwiki/`, `.github/`, `snapshots/`

- Not in runtime hot path; reviewed for release gating, documentation correctness, and build workflow issues.

## Appendix A: File Inventory

This appendix lists tracked files reviewed in this audit. Non-runtime files are included for completeness but generally do not affect frame-time performance.
### Superproject Files (git ls-files)

- `.DS_Store` (misc)
- `.github/workflows/test.yml` (ci)
- `.gitignore` (misc)
- `.gitmodules` (misc)
- `AGENTS.md` (docs)
- `LICENSE` (misc)
- `RELEASE_AUDIT.md` (docs)
- `UI_FEATURES.md` (docs)
- `assets/branding/zig-favicon.png` (asset (embedded/runtime))
- `assets/branding/zig-mark.svg` (asset (embedded/runtime))
- `assets/fonts.zig` (asset (embedded/runtime))
- `assets/fonts/Aleo/Aleo-Italic-VariableFont_wght.ttf` (asset (embedded/runtime))
- `assets/fonts/Aleo/Aleo-VariableFont_wght.ttf` (asset (embedded/runtime))
- `assets/fonts/Aleo/OFL.txt` (asset (embedded/runtime))
- `assets/fonts/Aleo/README.txt` (asset (embedded/runtime))
- `assets/fonts/Aleo/static/Aleo-Black.ttf` (asset (embedded/runtime))
- `assets/fonts/Aleo/static/Aleo-BlackItalic.ttf` (asset (embedded/runtime))
- `assets/fonts/Aleo/static/Aleo-Bold.ttf` (asset (embedded/runtime))
- `assets/fonts/Aleo/static/Aleo-BoldItalic.ttf` (asset (embedded/runtime))
- `assets/fonts/Aleo/static/Aleo-ExtraBold.ttf` (asset (embedded/runtime))
- `assets/fonts/Aleo/static/Aleo-ExtraBoldItalic.ttf` (asset (embedded/runtime))
- `assets/fonts/Aleo/static/Aleo-ExtraLight.ttf` (asset (embedded/runtime))
- `assets/fonts/Aleo/static/Aleo-ExtraLightItalic.ttf` (asset (embedded/runtime))
- `assets/fonts/Aleo/static/Aleo-Italic.ttf` (asset (embedded/runtime))
- `assets/fonts/Aleo/static/Aleo-Light.ttf` (asset (embedded/runtime))
- `assets/fonts/Aleo/static/Aleo-LightItalic.ttf` (asset (embedded/runtime))
- `assets/fonts/Aleo/static/Aleo-Medium.ttf` (asset (embedded/runtime))
- `assets/fonts/Aleo/static/Aleo-MediumItalic.ttf` (asset (embedded/runtime))
- `assets/fonts/Aleo/static/Aleo-Regular.ttf` (asset (embedded/runtime))
- `assets/fonts/Aleo/static/Aleo-SemiBold.ttf` (asset (embedded/runtime))
- `assets/fonts/Aleo/static/Aleo-SemiBoldItalic.ttf` (asset (embedded/runtime))
- `assets/fonts/Aleo/static/Aleo-Thin.ttf` (asset (embedded/runtime))
- `assets/fonts/Aleo/static/Aleo-ThinItalic.ttf` (asset (embedded/runtime))
- `assets/fonts/Consolas/Consolas.TTF` (asset (embedded/runtime))
- `assets/fonts/Inter/Inter-Bold.ttf` (asset (embedded/runtime))
- `assets/fonts/Inter/Inter-Regular.ttf` (asset (embedded/runtime))
- `assets/fonts/NotoSansKR-Regular.ttf` (asset (embedded/runtime))
- `assets/fonts/OpenDyslexic/FONTLOG.txt` (asset (embedded/runtime))
- `assets/fonts/OpenDyslexic/OFL-FAQ.txt` (asset (embedded/runtime))
- `assets/fonts/OpenDyslexic/OFL.txt` (asset (embedded/runtime))
- `assets/fonts/OpenDyslexic/README.md` (asset (embedded/runtime))
- `assets/fonts/OpenDyslexic/compiled/OpenDyslexic-Bold-Italic.otf` (asset (embedded/runtime))
- `assets/fonts/OpenDyslexic/compiled/OpenDyslexic-Bold.otf` (asset (embedded/runtime))
- `assets/fonts/OpenDyslexic/compiled/OpenDyslexic-Italic.otf` (asset (embedded/runtime))
- `assets/fonts/OpenDyslexic/compiled/OpenDyslexic-Regular.otf` (asset (embedded/runtime))
- `assets/fonts/PixelOperator/LICENSE.txt` (asset (embedded/runtime))
- `assets/fonts/PixelOperator/PixelOperator-Bold.ttf` (asset (embedded/runtime))
- `assets/fonts/PixelOperator/PixelOperator.ttf` (asset (embedded/runtime))
- `assets/fonts/PixelOperator/PixelOperator8-Bold.ttf` (asset (embedded/runtime))
- `assets/fonts/PixelOperator/PixelOperator8.ttf` (asset (embedded/runtime))
- `assets/fonts/PixelOperator/PixelOperatorHB.ttf` (asset (embedded/runtime))
- `assets/fonts/PixelOperator/PixelOperatorHB8.ttf` (asset (embedded/runtime))
- `assets/fonts/PixelOperator/PixelOperatorHBSC.ttf` (asset (embedded/runtime))
- `assets/fonts/PixelOperator/PixelOperatorMono-Bold.ttf` (asset (embedded/runtime))
- `assets/fonts/PixelOperator/PixelOperatorMono.ttf` (asset (embedded/runtime))
- `assets/fonts/PixelOperator/PixelOperatorMono8-Bold.ttf` (asset (embedded/runtime))
- `assets/fonts/PixelOperator/PixelOperatorMono8.ttf` (asset (embedded/runtime))
- `assets/fonts/PixelOperator/PixelOperatorMonoHB.ttf` (asset (embedded/runtime))
- `assets/fonts/PixelOperator/PixelOperatorMonoHB8.ttf` (asset (embedded/runtime))
- `assets/fonts/PixelOperator/PixelOperatorSC-Bold.ttf` (asset (embedded/runtime))
- `assets/fonts/PixelOperator/PixelOperatorSC.ttf` (asset (embedded/runtime))
- `assets/fonts/Pixelify_Sans/OFL.txt` (asset (embedded/runtime))
- `assets/fonts/Pixelify_Sans/PixelifySans-VariableFont_wght.ttf` (asset (embedded/runtime))
- `assets/fonts/Pixelify_Sans/README.txt` (asset (embedded/runtime))
- `assets/fonts/Pixelify_Sans/static/PixelifySans-Bold.ttf` (asset (embedded/runtime))
- `assets/fonts/Pixelify_Sans/static/PixelifySans-Medium.ttf` (asset (embedded/runtime))
- `assets/fonts/Pixelify_Sans/static/PixelifySans-Regular.ttf` (asset (embedded/runtime))
- `assets/fonts/Pixelify_Sans/static/PixelifySans-SemiBold.ttf` (asset (embedded/runtime))
- `assets/fonts/Segoe/Segoe-UI-Bold.TTF` (asset (embedded/runtime))
- `assets/fonts/Segoe/Segoe-UI-Italic.TTF` (asset (embedded/runtime))
- `assets/fonts/Segoe/Segoe-UI-Light.TTF` (asset (embedded/runtime))
- `assets/fonts/Segoe/Segoe-UI.TTF` (asset (embedded/runtime))
- `assets/fonts/bitstream-vera/COPYRIGHT.TXT` (asset (embedded/runtime))
- `assets/fonts/bitstream-vera/README.TXT` (asset (embedded/runtime))
- `assets/fonts/bitstream-vera/RELEASENOTES.TXT` (asset (embedded/runtime))
- `assets/fonts/bitstream-vera/Vera.ttf` (asset (embedded/runtime))
- `assets/fonts/bitstream-vera/VeraBI.ttf` (asset (embedded/runtime))
- `assets/fonts/bitstream-vera/VeraBd.ttf` (asset (embedded/runtime))
- `assets/fonts/bitstream-vera/VeraIt.ttf` (asset (embedded/runtime))
- `assets/fonts/bitstream-vera/VeraMoBI.ttf` (asset (embedded/runtime))
- `assets/fonts/bitstream-vera/VeraMoBd.ttf` (asset (embedded/runtime))
- `assets/fonts/bitstream-vera/VeraMoIt.ttf` (asset (embedded/runtime))
- `assets/fonts/bitstream-vera/VeraMono.ttf` (asset (embedded/runtime))
- `assets/fonts/bitstream-vera/VeraSe.ttf` (asset (embedded/runtime))
- `assets/fonts/bitstream-vera/VeraSeBd.ttf` (asset (embedded/runtime))
- `assets/fonts/bitstream-vera/local.conf` (asset (embedded/runtime))
- `assets/fonts/hack/Hack-Bold.ttf` (asset (embedded/runtime))
- `assets/fonts/hack/Hack-BoldItalic.ttf` (asset (embedded/runtime))
- `assets/fonts/hack/Hack-Italic.ttf` (asset (embedded/runtime))
- `assets/fonts/hack/Hack-Regular.ttf` (asset (embedded/runtime))
- `assets/fonts/hack/LICENSE` (asset (embedded/runtime))
- `assets/mod.zig` (asset (embedded/runtime))
- `assets/sprite.png` (asset (embedded/runtime))
- `assets/windows/main.manifest` (asset (embedded/runtime))
- `build.zig` (misc)
- `build.zig.zon` (misc)
- `deepwiki/pages.json` (docs tooling)
- `deepwiki/parse.ts` (docs tooling)
- `deps/luaz` (dep (submodule pointer))
- `deps/msdf_zig/assets/msdf_placeholder_atlas.png` (dep (zig))
- `deps/msdf_zig/assets/msdf_placeholder_font.json` (dep (zig))
- `deps/msdf_zig/msdf_zig.zig` (dep (zig))
- `deps/msdf_zig/src/msdf_zig.zig` (dep (zig))
- `deps/msdf_zig/src/shader.zig` (dep (zig))
- `deps/msdf_zig/src/shaders/msdf_text_ui.wgsl` (dep (zig))
- `deps/msdf_zig/src/shaders/msdf_text_world.wgsl` (dep (zig))
- `deps/msdf_zig/src/types.zig` (dep (zig))
- `deps/solidluau` (dep (submodule pointer))
- `deps/wgpu_native_zig` (dep (submodule pointer))
- `deps/zig-yoga/build.zig` (dep (zig))
- `deps/zig-yoga/build.zig.zon` (dep (zig))
- `deps/zig-yoga/src/enums.zig` (dep (zig))
- `deps/zig-yoga/src/root.zig` (dep (zig))
- `docs/LAYOUT_TREE_DUMP.md` (docs)
- `docs/RETAINED.md` (docs)
- `docs/RETAINED_API.md` (docs)
- `docs/UI_PRIMITIVES.md` (docs)
- `docs/luau-findings/high-binary-event-payload-contract.md` (docs)
- `docs/luau-findings/high-event-ring-saturation-after-lua-teardown.md` (docs)
- `docs/luau-findings/high-stale-object-prop-clear-semantics.md` (docs)
- `favicon.png` (misc)
- `luau/_smoke/checkbox.luau` (runtime (luau))
- `luau/_smoke/ui_refs.luau` (runtime (luau))
- `luau/app.luau` (runtime (luau))
- `luau/components/bar.luau` (runtime (luau))
- `luau/components/checkbox.luau` (runtime (luau))
- `luau/components/toggle.luau` (runtime (luau))
- `luau/index.luau` (runtime (luau))
- `luau/ui/cn.luau` (runtime (luau))
- `luau/ui/load_ui.luau` (runtime (luau))
- `luau/ui/types.luau` (runtime (luau))
- `luau/ui_features_image_1.png` (runtime (luau))
- `luau/ui_gen/app_ui.luau` (runtime (luau))
- `luau/ui_json/app.json` (runtime (luau))
- `readme-implementation.md` (docs)
- `retained-architecture.md` (docs)
- `snapshots/app.layout.json` (snapshot/test)
- `solidluau_embedded.zig` (misc)
- `src/accessibility/accesskit.zig` (runtime (zig))
- `src/accessibility/mod.zig` (runtime (zig))
- `src/backends/backend.zig` (runtime (zig))
- `src/backends/common.zig` (runtime (zig))
- `src/backends/mod.zig` (runtime (zig))
- `src/backends/pipeline/compute.zig` (runtime (zig))
- `src/backends/pipeline/depth.zig` (runtime (zig))
- `src/backends/pipeline/geometry.zig` (runtime (zig))
- `src/backends/pipeline/main.zig` (runtime (zig))
- `src/backends/pipeline/render.zig` (runtime (zig))
- `src/backends/pipeline/swap_chain.zig` (runtime (zig))
- `src/backends/pipeline/types.zig` (runtime (zig))
- `src/backends/raylib-zig.zig` (runtime (zig))
- `src/backends/webgpu.zig` (runtime (zig))
- `src/backends/webgpu/mod.zig` (runtime (zig))
- `src/backends/webgpu/platform_macos.zig` (runtime (zig))
- `src/backends/webgpu/platform_macos_metal_layer.m` (runtime (zig))
- `src/backends/webgpu/platform_windows.zig` (runtime (zig))
- `src/backends/wgpu.zig` (runtime (zig))
- `src/core/color.zig` (runtime (zig))
- `src/core/data.zig` (runtime (zig))
- `src/core/enums.zig` (runtime (zig))
- `src/core/mod.zig` (runtime (zig))
- `src/core/options.zig` (runtime (zig))
- `src/core/point.zig` (runtime (zig))
- `src/core/rect.zig` (runtime (zig))
- `src/core/size.zig` (runtime (zig))
- `src/core/vertex.zig` (runtime (zig))
- `src/dvui.zig` (runtime (zig))
- `src/layout/easing.zig` (runtime (zig))
- `src/layout/layout.zig` (runtime (zig))
- `src/layout/mod.zig` (runtime (zig))
- `src/layout/scroll_info.zig` (runtime (zig))
- `src/main.zig` (runtime (zig))
- `src/native_renderer/commands.zig` (runtime (zig))
- `src/native_renderer/event_payload.zig` (runtime (zig))
- `src/native_renderer/lifecycle.zig` (runtime (zig))
- `src/native_renderer/luau_ui.zig` (runtime (zig))
- `src/native_renderer/mod.zig` (runtime (zig))
- `src/native_renderer/profiling.zig` (runtime (zig))
- `src/native_renderer/types.zig` (runtime (zig))
- `src/native_renderer/utils.zig` (runtime (zig))
- `src/native_renderer/window.zig` (runtime (zig))
- `src/platform/dialogs.zig` (runtime (zig))
- `src/platform/io_compat.zig` (runtime (zig))
- `src/platform/mod.zig` (runtime (zig))
- `src/render/jpg_encoder.zig` (runtime (zig))
- `src/render/mod.zig` (runtime (zig))
- `src/render/path.zig` (runtime (zig))
- `src/render/png_encoder.zig` (runtime (zig))
- `src/render/render.zig` (runtime (zig))
- `src/render/texture.zig` (runtime (zig))
- `src/render/triangles.zig` (runtime (zig))
- `src/retained/core/SUMMARY.md` (runtime (zig))
- `src/retained/core/geometry.zig` (runtime (zig))
- `src/retained/core/layout.zig` (runtime (zig))
- `src/retained/core/media.zig` (runtime (zig))
- `src/retained/core/node_store.zig` (runtime (zig))
- `src/retained/core/types.zig` (runtime (zig))
- `src/retained/core/visual.zig` (runtime (zig))
- `src/retained/events/SUMMARY.md` (runtime (zig))
- `src/retained/events/drag_drop.zig` (runtime (zig))
- `src/retained/events/focus.zig` (runtime (zig))
- `src/retained/events/mod.zig` (runtime (zig))
- `src/retained/hit_test.zig` (runtime (zig))
- `src/retained/layout/SUMMARY.md` (runtime (zig))
- `src/retained/layout/flex.zig` (runtime (zig))
- `src/retained/layout/measure.zig` (runtime (zig))
- `src/retained/layout/mod.zig` (runtime (zig))
- `src/retained/layout/text_wrap.zig` (runtime (zig))
- `src/retained/layout/yoga.zig` (runtime (zig))
- `src/retained/mod.zig` (runtime (zig))
- `src/retained/render/cache.zig` (runtime (zig))
- `src/retained/render/direct.zig` (runtime (zig))
- `src/retained/render/icon_registry.zig` (runtime (zig))
- `src/retained/render/image_loader.zig` (runtime (zig))
- `src/retained/render/internal/derive.zig` (runtime (zig))
- `src/retained/render/internal/hover.zig` (runtime (zig))
- `src/retained/render/internal/interaction.zig` (runtime (zig))
- `src/retained/render/internal/overlay.zig` (runtime (zig))
- `src/retained/render/internal/renderers.zig` (runtime (zig))
- `src/retained/render/internal/runtime.zig` (runtime (zig))
- `src/retained/render/internal/state.zig` (runtime (zig))
- `src/retained/render/internal/visual_sync.zig` (runtime (zig))
- `src/retained/render/mod.zig` (runtime (zig))
- `src/retained/render/transitions.zig` (runtime (zig))
- `src/retained/style/apply.zig` (runtime (zig))
- `src/retained/style/colors.zig` (runtime (zig))
- `src/retained/style/mod.zig` (runtime (zig))
- `src/retained/style/tailwind.zig` (runtime (zig))
- `src/retained/style/tailwind/parse.zig` (runtime (zig))
- `src/retained/style/tailwind/parse_color_typography.zig` (runtime (zig))
- `src/retained/style/tailwind/parse_layout.zig` (runtime (zig))
- `src/retained/style/tailwind/types.zig` (runtime (zig))
- `src/testing/mod.zig` (runtime (zig))
- `src/text/font.zig` (runtime (zig))
- `src/text/mod.zig` (runtime (zig))
- `src/text/selection.zig` (runtime (zig))
- `src/theming/mod.zig` (runtime (zig))
- `src/theming/shadcn.zon` (runtime (zig))
- `src/theming/theme.zig` (runtime (zig))
- `src/utils/alloc.zig` (runtime (zig))
- `src/utils/cache_buster.zig` (runtime (zig))
- `src/utils/mod.zig` (runtime (zig))
- `src/utils/struct_ui.zig` (runtime (zig))
- `src/utils/tracking_hash_map.zig` (runtime (zig))
- `src/widgets/AnimateWidget.zig` (runtime (zig))
- `src/widgets/BoxWidget.zig` (runtime (zig))
- `src/widgets/ButtonWidget.zig` (runtime (zig))
- `src/widgets/FlexBoxWidget.zig` (runtime (zig))
- `src/widgets/GizmoWidget.zig` (runtime (zig))
- `src/widgets/IconWidget.zig` (runtime (zig))
- `src/widgets/LabelWidget.zig` (runtime (zig))
- `src/widgets/MenuItemWidget.zig` (runtime (zig))
- `src/widgets/MenuWidget.zig` (runtime (zig))
- `src/widgets/ScaleWidget.zig` (runtime (zig))
- `src/widgets/ScrollBarWidget.zig` (runtime (zig))
- `src/widgets/SelectionWidget.zig` (runtime (zig))
- `src/widgets/SelectionWidget/drawing.zig` (runtime (zig))
- `src/widgets/SelectionWidget/events.zig` (runtime (zig))
- `src/widgets/SelectionWidget/transform.zig` (runtime (zig))
- `src/widgets/mod.zig` (runtime (zig))
- `src/widgets/widget.zig` (runtime (zig))
- `src/widgets/widget_data.zig` (runtime (zig))
- `src/window/app.zig` (runtime (zig))
- `src/window/debug.zig` (runtime (zig))
- `src/window/dragging.zig` (runtime (zig))
- `src/window/event.zig` (runtime (zig))
- `src/window/mod.zig` (runtime (zig))
- `src/window/subwindows.zig` (runtime (zig))
- `src/window/window.zig` (runtime (zig))
- `tools/layoutdump_scenes.json` (tooling)
- `tools/luau_layout_dump_main.zig` (tooling)
- `tools/luau_smoke.zig` (tooling)
- `tools/ui_codegen.zig` (tooling)
- `vendor/stb/stb_image.h` (vendored native)
- `vendor/stb/stb_image_impl.c` (vendored native)
- `vendor/stb/stb_image_libc.c` (vendored native)
- `vendor/stb/stb_image_write.h` (vendored native)
- `vendor/stb/stb_image_write_impl.c` (vendored native)
- `vendor/stb/stb_truetype.h` (vendored native)
- `vendor/stb/stb_truetype_impl.c` (vendored native)
- `vendor/stb/stb_truetype_libc.c` (vendored native)
- `zig_build_simple.sh` (tooling)

### Submodule: deps/solidluau (git -C deps/solidluau ls-files)

- `deps/solidluau/.gitignore`
- `deps/solidluau/.gitmodules`
- `deps/solidluau/README.md`
- `deps/solidluau/TASK.md`
- `deps/solidluau/ZIG_NATIVE_PLAN.md`
- `deps/solidluau/build-docs`
- `deps/solidluau/build.zig`
- `deps/solidluau/build.zig.zon`
- `deps/solidluau/docs/solidluau-animation.mdx`
- `deps/solidluau/docs/solidluau-animationentry.mdx`
- `deps/solidluau/docs/solidluau-reactivity.mdx`
- `deps/solidluau/docs/solidluau-scheduler.mdx`
- `deps/solidluau/docs/solidluau-ui-dsl.mdx`
- `deps/solidluau/docs/solidluau-ui.mdx`
- `deps/solidluau/docs/solidluau-uientry.mdx`
- `deps/solidluau/docs/solidluau.mdx`
- `deps/solidluau/luau-docs/README.md`
- `deps/solidluau/luau-docs/index.ts`
- `deps/solidluau/luau-docs/moonwave-extractor`
- `deps/solidluau/luaz`
- `deps/solidluau/scripts/build-docs.sh`
- `deps/solidluau/solidluau_embed.zig`
- `deps/solidluau/solidluau_modules.zig`
- `deps/solidluau/src/ARCHITECTURE_REVIEW.md`
- `deps/solidluau/src/README.md`
- `deps/solidluau/src/animation.luau`
- `deps/solidluau/src/animation/easing.luau`
- `deps/solidluau/src/animation/engine.luau`
- `deps/solidluau/src/animation/index.luau`
- `deps/solidluau/src/animation/spring.luau`
- `deps/solidluau/src/animation/tween.luau`
- `deps/solidluau/src/core/reactivity.luau`
- `deps/solidluau/src/core/scheduler.luau`
- `deps/solidluau/src/solidluau.luau`
- `deps/solidluau/src/ui.luau`
- `deps/solidluau/src/ui/adapter_types.luau`
- `deps/solidluau/src/ui/adapters/compat_ui.luau`
- `deps/solidluau/src/ui/dsl.luau`
- `deps/solidluau/src/ui/hydrate.luau`
- `deps/solidluau/src/ui/index.luau`
- `deps/solidluau/src/ui/renderer.luau`
- `deps/solidluau/src/ui/types.luau`
- `deps/solidluau/tests/luau/animation-mutableOutput-test.luau`
- `deps/solidluau/tests/luau/reactivity-memo_invalidation_test.luau`
- `deps/solidluau/tests/luau/reactivity-scope_unlink_test.luau`
- `deps/solidluau/tests/luau/ui-dsl_tag_call_test.luau`
- `deps/solidluau/tests/luau/ui-flat-props_cutover_test.luau`
- `deps/solidluau/tests/luau/ui-patch_test.luau`
- `deps/solidluau/vide/.gitignore`
- `deps/solidluau/vide/OVERVIEW.md`
- `deps/solidluau/vide/README.md`
- `deps/solidluau/vide/docs/advanced/dynamic-scopes.md`
- `deps/solidluau/vide/docs/api/animation.md`
- `deps/solidluau/vide/docs/api/creation.md`
- `deps/solidluau/vide/docs/api/reactivity-core.md`
- `deps/solidluau/vide/docs/api/reactivity-dynamic.md`
- `deps/solidluau/vide/docs/api/reactivity-utility.md`
- `deps/solidluau/vide/docs/api/strict-mode.md`
- `deps/solidluau/vide/docs/crash-course/1-introduction.md`
- `deps/solidluau/vide/docs/crash-course/10-cleanup.md`
- `deps/solidluau/vide/docs/crash-course/11-dynamic-scopes.md`
- `deps/solidluau/vide/docs/crash-course/12-actions.md`
- `deps/solidluau/vide/docs/crash-course/13-strict-mode.md`
- `deps/solidluau/vide/docs/crash-course/14-concepts.md`
- `deps/solidluau/vide/docs/crash-course/2-creation.md`
- `deps/solidluau/vide/docs/crash-course/3-components.md`
- `deps/solidluau/vide/docs/crash-course/4-source.md`
- `deps/solidluau/vide/docs/crash-course/5-effect.md`
- `deps/solidluau/vide/docs/crash-course/6-scope.md`
- `deps/solidluau/vide/docs/crash-course/7-reactive-component.md`
- `deps/solidluau/vide/docs/crash-course/8-implicit-effect.md`
- `deps/solidluau/vide/docs/crash-course/9-derived-source.md`
- `deps/solidluau/vide/init.luau`
- `deps/solidluau/vide/src/action.luau`
- `deps/solidluau/vide/src/apply.luau`
- `deps/solidluau/vide/src/batch.luau`
- `deps/solidluau/vide/src/branch.luau`
- `deps/solidluau/vide/src/changed.luau`
- `deps/solidluau/vide/src/cleanup.luau`
- `deps/solidluau/vide/src/context.luau`
- `deps/solidluau/vide/src/create.luau`
- `deps/solidluau/vide/src/defaults.luau`
- `deps/solidluau/vide/src/derive.luau`
- `deps/solidluau/vide/src/effect.luau`
- `deps/solidluau/vide/src/flags.luau`
- `deps/solidluau/vide/src/graph.luau`
- `deps/solidluau/vide/src/implicit_effect.luau`
- `deps/solidluau/vide/src/indexes.luau`
- `deps/solidluau/vide/src/init.luau`
- `deps/solidluau/vide/src/lib.luau`
- `deps/solidluau/vide/src/mount.luau`
- `deps/solidluau/vide/src/read.luau`
- `deps/solidluau/vide/src/root.luau`
- `deps/solidluau/vide/src/show.luau`
- `deps/solidluau/vide/src/source.luau`
- `deps/solidluau/vide/src/spring.luau`
- `deps/solidluau/vide/src/switch.luau`
- `deps/solidluau/vide/src/timeout.luau`
- `deps/solidluau/vide/src/untrack.luau`
- `deps/solidluau/vide/src/values.luau`
- `deps/solidluau/vide/test/benchmarks.luau`
- `deps/solidluau/vide/test/create-types.luau`
- `deps/solidluau/vide/test/mock.luau`
- `deps/solidluau/vide/test/spring-test.luau`
- `deps/solidluau/vide/test/stacktrace-test.luau`
- `deps/solidluau/vide/test/testkit.luau`
- `deps/solidluau/vide/test/tests.luau`
- `deps/solidluau/zig/solidluau_embed.zig`
- `deps/solidluau/zig/solidluau_modules.zig`
- `deps/solidluau/zig/solidluau_tests.zig`

### Submodule: deps/luaz (git -C deps/luaz ls-files)

- `deps/luaz/.claude/agents/general-purpose.md`
- `deps/luaz/.claude/commands/changelog.md`
- `deps/luaz/.claude/commands/commit.md`
- `deps/luaz/.claude/commands/guide.md`
- `deps/luaz/.claude/commands/release.md`
- `deps/luaz/.claude/commands/update-luau.md`
- `deps/luaz/.claude/settings.json`
- `deps/luaz/.github/actions/setup-zig/action.yml`
- `deps/luaz/.github/actions/setup-zig/install-zig.sh`
- `deps/luaz/.github/workflows/ci.yml`
- `deps/luaz/.github/workflows/claude.yml`
- `deps/luaz/.github/workflows/docs.yml`
- `deps/luaz/.gitignore`
- `deps/luaz/AGENTS.md`
- `deps/luaz/CHANGELOG.md`
- `deps/luaz/CONTRIBUTING.md`
- `deps/luaz/LICENSE`
- `deps/luaz/LUAU_API.md`
- `deps/luaz/README.md`
- `deps/luaz/build.zig`
- `deps/luaz/build.zig.zon`
- `deps/luaz/codecov.yml`
- `deps/luaz/docs/logo.png`
- `deps/luaz/examples/guided_tour.zig`
- `deps/luaz/examples/runtime_loop.zig`
- `deps/luaz/src/Compiler.zig`
- `deps/luaz/src/Debug.zig`
- `deps/luaz/src/GC.zig`
- `deps/luaz/src/Lua.zig`
- `deps/luaz/src/State.zig`
- `deps/luaz/src/alloc.zig`
- `deps/luaz/src/assert.zig`
- `deps/luaz/src/handler.cpp`
- `deps/luaz/src/handler.h`
- `deps/luaz/src/lib.zig`
- `deps/luaz/src/stack.zig`
- `deps/luaz/src/userdata.zig`
- `deps/luaz/zlint.json`

### Submodule: deps/wgpu_native_zig (git -C deps/wgpu_native_zig ls-files)

- `deps/wgpu_native_zig/.gitignore`
- `deps/wgpu_native_zig/LICENSE`
- `deps/wgpu_native_zig/README.md`
- `deps/wgpu_native_zig/build.zig`
- `deps/wgpu_native_zig/build.zig.zon`
- `deps/wgpu_native_zig/examples/bmp.zig`
- `deps/wgpu_native_zig/examples/output/.gitkeep`
- `deps/wgpu_native_zig/examples/triangle/shader.wgsl`
- `deps/wgpu_native_zig/examples/triangle/triangle.zig`
- `deps/wgpu_native_zig/src/adapter.zig`
- `deps/wgpu_native_zig/src/async.zig`
- `deps/wgpu_native_zig/src/bind_group.zig`
- `deps/wgpu_native_zig/src/buffer.zig`
- `deps/wgpu_native_zig/src/chained_struct.zig`
- `deps/wgpu_native_zig/src/command_encoder.zig`
- `deps/wgpu_native_zig/src/device.zig`
- `deps/wgpu_native_zig/src/global.zig`
- `deps/wgpu_native_zig/src/instance.zig`
- `deps/wgpu_native_zig/src/limits.zig`
- `deps/wgpu_native_zig/src/log.zig`
- `deps/wgpu_native_zig/src/misc.zig`
- `deps/wgpu_native_zig/src/pipeline.zig`
- `deps/wgpu_native_zig/src/query_set.zig`
- `deps/wgpu_native_zig/src/queue.zig`
- `deps/wgpu_native_zig/src/render_bundle.zig`
- `deps/wgpu_native_zig/src/root.zig`
- `deps/wgpu_native_zig/src/sampler.zig`
- `deps/wgpu_native_zig/src/shader.zig`
- `deps/wgpu_native_zig/src/surface.zig`
- `deps/wgpu_native_zig/src/texture.zig`
- `deps/wgpu_native_zig/test-all`
- `deps/wgpu_native_zig/tests/compute.wgsl`
- `deps/wgpu_native_zig/tests/compute.zig`
- `deps/wgpu_native_zig/tests/compute_c.zig`
