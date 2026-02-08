# Memory Management Release Audit (DVUI)

Date: 2026-02-07  
Repo: `dvui` @ `dfbb0d78a699de424749612a9e27d70336662155`  
Zig: `0.15.2`  
Submodules:
- `deps/luaz` @ `479d5dcf907ceef5aafc224f8ed735561ca19e6a`
- `deps/solidluau` @ `65a8bb7dfd11fdbb0f3c1c4d11efcea31858b7a4` (dirty: yes)
- `deps/wgpu_native_zig` @ `8f1ae3e7561f11e0bf0c6d122f9a53f68991c26d`

Working Tree Notes:
- `deps/solidluau` has local modifications:
```text
 M docs/solidluau-animation.mdx
 M src/animation/index.luau
 M tests/luau/reactivity-memo_invalidation_test.luau
```

## Scope And Exclusions

This audit focuses on **Critical** and **High** severity memory-management issues that could plausibly block or materially risk a product release:
- Memory safety (undefined behavior, misalignment, integer overflow leading to under-allocation)
- Unbounded memory growth (caches, registries)
- Lifetime/ownership bugs across FFI boundaries
- GPU memory/resource leaks that accumulate in normal usage

Excluded by `.gitignore` (not audited):
- `.zig-cache/`, `zig-cache/`, `zig-out/`
- `artifacts/`
- `node_modules/`, `dist/`
- `snapshots/images/`
- `examples/`

## Methodology

Review approach:
- File inventory for the root repo plus each submodule (see Appendix).
- Automated scan for allocator usage and ownership patterns (`ArenaAllocator`, `GeneralPurposeAllocator`, `rawAlloc/rawFree`, `c_allocator`, `page_allocator`, `create/destroy`, `alloc/free`, `deinit/reset`).
- Manual review focus files:
`src/backends/wgpu.zig`  
`src/core/data.zig`  
`src/window/window.zig`  
`src/text/font.zig`  
`src/dvui.zig`  
`src/retained/style/tailwind.zig`  
`src/retained/render/image_loader.zig`  
`src/retained/render/icon_registry.zig`  
`src/accessibility/accesskit.zig`  
`deps/luaz/src/alloc.zig`  

Spot validations performed:
- Confirmed on Zig `0.15.2` that slice-to-slice `@ptrCast` adjusts length by element size ratio.
- Confirmed AccessKit ownership semantics by inspecting the header in Zig's global cache:
`accesskit_tree_update_push_node` takes ownership of the provided node.  
`accesskit_node_set_label` and `accesskit_node_set_description` allow the caller to free `value` immediately after the call.

## Executive Summary

### Critical Findings

1. **WGPU texture uploads violate the required row-stride alignment**
- Impact: texture creation and updates can fail validation or misbehave for most widths; this breaks images, MSDF atlases, and any dynamic texture update path.
- Evidence:
  - `src/backends/wgpu.zig:1118` sets `.bytes_per_row = width * 4` in the texture creation upload.
  - `src/backends/wgpu.zig:513` sets `.bytes_per_row = texture.width * 4` in `textureUpdate`.
- Why this is release-blocking: WebGPU implementations commonly require `bytes_per_row` to be aligned (typically 256 bytes). Many UI textures are not width%64==0, so this is not an edge case.
- Recommended remediation:
  - Pad rows into a staging buffer with aligned `bytes_per_row`, then upload.
  - Ensure both create and update paths share the same padding logic.

2. **Type confusion and misalignment risk in `Data` store**
- Impact: reusing a key with a different type of the same byte length can return misaligned pointers or type-punned access. In ReleaseFast this can be undefined behavior; in safe modes it can trap.
- Evidence:
  - `src/core/data.zig:155` only reallocates ("trashes") when `entry.value_ptr.data.len != len`.
  - `src/core/data.zig:127` and `src/core/data.zig:143` cast stored bytes back to typed pointers via `@alignCast` + `@ptrCast`.
- Why this is release-blocking: `Window.data_store` is central state. ID collisions or accidental reuse can turn into hard-to-debug crashes.
- Recommended remediation:
  - Treat alignment mismatch and debug-type mismatch as a reason to trash/realloc even when lengths match.
  - In Debug, validate stored debug info on every access, not only on realloc.

3. **Potential integer overflow in Lua VM allocator bridge (under-allocation risk)**
- Impact: `header_size + nsize` can overflow `usize`. In ReleaseFast this can wrap to a smaller allocation while returning a pointer that the VM will treat as `nsize` bytes, enabling memory corruption.
- Evidence:
  - `deps/luaz/src/alloc.zig:50` and `deps/luaz/src/alloc.zig:64` compute `new_total = header_size + nsize`.
- Recommended remediation:
  - Use checked addition and return `null` on overflow.

### High Findings

1. **Unbounded retained caches (global, no eviction)**
- Impact: long-running sessions can grow memory without bound if many unique values are observed.
- Evidence:
  - Tailwind spec cache: `src/retained/style/tailwind.zig:27` global `spec_cache` duplicates every unique class string.
  - Image bytes cache: `src/retained/render/image_loader.zig:11` global `image_cache` retains full file bytes (up to 16MB per entry).
  - Icon registry cache: `src/retained/render/icon_registry.zig:33` global `icon_cache` retains vector bytes and raster paths.
- Recommended remediation:
  - Introduce explicit caps (entry count and/or total bytes) and eviction (LRU) for image/icon caches.
  - Add a cache clear API and document expected usage patterns.

2. **FreeType library is initialized but never released**
- Impact: if `Window.init` is invoked multiple times in-process, `FT_Init_FreeType` is repeatedly called with no corresponding `FT_Done_FreeType`. This can leak and potentially destabilize FreeType state.
- Evidence:
  - `src/window/window.zig:322` calls `FT_Init_FreeType(&dvui.ft2lib)`.
  - No `FT_Done_FreeType` call exists in the repo.
- Recommended remediation:
  - Initialize FreeType once per process with a guarded singleton and a matching deinit path.

3. **`dvui.addFont` ownership contract does not match deinit behavior**
- Impact:
  - The public contract says the provided allocator will free both `ttf_bytes` and `name`, but the implementation only frees bytes.
  - This can leak (if `name` is heap-allocated), or encourage unsafe usage (passing non-owned `name` with an allocator expecting it will be freed).
- Evidence:
  - Contract: `src/dvui.zig:491` to `src/dvui.zig:524`.
  - Implementation: `src/text/font.zig:365` to `src/text/font.zig:371` frees only `ttf.bytes`.
- Recommended remediation:
  - Either (A) always dupe `name` when an allocator is provided and free it on deinit, or (B) change contract to state `name` is not freed.

4. **`Window.InitOptions.arena` is a by-value ArenaAllocator (double-free footgun)**
- Impact: copying an `ArenaAllocator` by value is not safe if both the caller and the Window later call `deinit` on the same underlying allocations.
- Evidence:
  - `src/window/window.zig:146` exposes `arena: ?std.heap.ArenaAllocator`.
  - `src/window/window.zig:173` copies it into `self._arena`.
  - `src/window/window.zig:361` always `self._arena.deinit()`.
- Recommended remediation:
  - Accept `*std.heap.ArenaAllocator` (pointer) or remove this option.
  - If ownership transfer is intended, rename/document it as a move-only API and enforce by taking a pointer and nulling the source.

5. **Lua teardown can leave the retained event ring in a degraded steady state**
- Impact: after Lua teardown, retained rendering can continue producing events that are never drained; ring fills and logs warnings repeatedly. This is primarily performance/log growth but also affects counters and fault containment.
- Evidence:
  - `docs/luau-findings/high-event-ring-saturation-after-lua-teardown.md`
- Recommended remediation:
  - When Lua is not ready, pass `null` event ring to retained render, or explicitly discard events each frame.

## Subagent Reports (Directory-Level)

### Subagent: Root Files

Memory-management-relevant root files:
- `build.zig`: uses build allocator correctly with `defer ... free(...)` for env var reads.
- `zig_build_simple.sh`: build wrapper; no runtime memory impact.
- `RELEASE_AUDIT.md`: contains prior cross-cutting release findings; some memory-specific claims should be re-validated against Zig 0.15 slice-cast semantics.

Non-memory files:
- `LICENSE`, `AGENTS.md`, `UI_FEATURES.md`, `retained-architecture.md`, `.github/...`

### Subagent: `assets/`

- `assets/fonts.zig`: embeds multiple fonts via `@embedFile`. This increases binary size and can increase working set depending on how fonts are used.
- No allocator misuse in this directory.

### Subagent: `deepwiki/`

- `deepwiki/parse.ts` reads `pages.json` fully into memory and writes markdown files. This is a dev/doc tool, not runtime.

### Subagent: `docs/`

- `docs/luau-findings/*` already documents multiple **High** severity runtime issues, including event ring saturation (resource growth via log spam) and stale state semantics.

### Subagent: `luau/`

- Luau scripts are GC-managed; the main memory-management risk is unbounded object creation or retained references in reactive graphs.
- Existing findings in `docs/luau-findings` are the highest-signal issues surfaced in this repo.

### Subagent: `src/` (Core)

Allocator model (observed):
- Long-lived state uses `Window.gpa`.
- Per-frame allocations use `Window._arena` and `Window._lifo_arena`, both reset each frame with a shrink policy (`src/window/window.zig:1372` to `src/window/window.zig:1388`).
- Texture and font caches have explicit `reset` and `deinit` paths.

High-risk findings within `src/`:
- Critical: `src/backends/wgpu.zig` row-stride alignment.
- Critical: `src/core/data.zig` type/alignment reuse.
- High: `src/window/window.zig` FreeType init without done; InitOptions arena by-value.
- High: `src/text/font.zig` database deinit does not match `dvui.addFont` contract.

### Subagent: `src/accessibility/`

Ownership boundaries were validated against the AccessKit C header in the Zig cache:
- Strings passed to setters can be freed immediately after calling `accesskit_node_set_*`.
- `accesskit_tree_update_push_node` takes ownership of nodes.

DVUI usage matches these semantics:
- Temporary label/description strings allocated in `Window.arena()` are freed immediately after calling the setter.

### Subagent: `src/retained/`

Primary memory risks are global unbounded caches:
- Tailwind class spec cache (unique class strings accumulate).
- Image/icon registries cache bytes and do not evict.

Other retained allocations:
- Per-frame scratch allocations are done via an `ArenaAllocator` that is `deinit()`ed each render call (`src/retained/render/mod.zig:63` to `src/retained/render/mod.zig:66`).

### Subagent: `src/native_renderer/`

- Renderer uses a `frame_arena` reset per frame (`src/native_renderer/window.zig:243`).
- Renderer shutdown frees retained store and event ring.
- Known high-severity degradation mode: event ring saturation after Lua teardown (see docs).

### Subagent: `tools/`

- Mostly short-lived tooling.
- `src/utils/cache_buster.zig` opens files without explicit `close()` (process-lifetime FD leak in a tool; likely low impact but easy fix).

### Subagent: `vendor/`

- `vendor/stb` is upstream C. Memory management risk is primarily in how DVUI configures allocators.
- For WASM builds, `vendor/stb/stb_*_impl.c` includes `*_libc.c` and relies on externally provided `dvui_c_alloc/free/realloc_sized`. Incorrect host implementations can leak or corrupt memory.

### Subagent: `deps/`

- `deps/luaz`: contains the Lua VM allocator bridge (Critical overflow risk on size computations).
- `deps/solidluau`: Luau sources and require loader; module caching is intentional, but can retain memory for any unique module id loaded.
- `deps/wgpu_native_zig`: C bindings and ref-counted resource wrappers; DVUI must ensure all created objects are released.

## Recommended Release Gate Checklist

1. Fix WGPU `bytes_per_row` alignment for texture create and update.
2. Harden `Data` to avoid type/alignment confusion when lengths match.
3. Add overflow checks to `deps/luaz/src/alloc.zig` allocator bridge.
4. Add eviction/caps for retained caches or provide an explicit policy for production use.
5. Clarify and enforce `dvui.addFont` ownership semantics.
6. Add FreeType global init/deinit strategy.

## Appendix: File Inventory

### Root Repo Tracked Files (`git ls-files`)

```text
.DS_Store
.github/workflows/test.yml
.gitignore
.gitmodules
AGENTS.md
LICENSE
RELEASE_AUDIT.md
RUNTIME_PERFORMANCE_AUDIT.md
UI_FEATURES.md
assets/branding/zig-favicon.png
assets/branding/zig-mark.svg
assets/fonts.zig
assets/fonts/Aleo/Aleo-Italic-VariableFont_wght.ttf
assets/fonts/Aleo/Aleo-VariableFont_wght.ttf
assets/fonts/Aleo/OFL.txt
assets/fonts/Aleo/README.txt
assets/fonts/Aleo/static/Aleo-Black.ttf
assets/fonts/Aleo/static/Aleo-BlackItalic.ttf
assets/fonts/Aleo/static/Aleo-Bold.ttf
assets/fonts/Aleo/static/Aleo-BoldItalic.ttf
assets/fonts/Aleo/static/Aleo-ExtraBold.ttf
assets/fonts/Aleo/static/Aleo-ExtraBoldItalic.ttf
assets/fonts/Aleo/static/Aleo-ExtraLight.ttf
assets/fonts/Aleo/static/Aleo-ExtraLightItalic.ttf
assets/fonts/Aleo/static/Aleo-Italic.ttf
assets/fonts/Aleo/static/Aleo-Light.ttf
assets/fonts/Aleo/static/Aleo-LightItalic.ttf
assets/fonts/Aleo/static/Aleo-Medium.ttf
assets/fonts/Aleo/static/Aleo-MediumItalic.ttf
assets/fonts/Aleo/static/Aleo-Regular.ttf
assets/fonts/Aleo/static/Aleo-SemiBold.ttf
assets/fonts/Aleo/static/Aleo-SemiBoldItalic.ttf
assets/fonts/Aleo/static/Aleo-Thin.ttf
assets/fonts/Aleo/static/Aleo-ThinItalic.ttf
assets/fonts/Consolas/Consolas.TTF
assets/fonts/Inter/Inter-Bold.ttf
assets/fonts/Inter/Inter-Regular.ttf
assets/fonts/NotoSansKR-Regular.ttf
assets/fonts/OpenDyslexic/FONTLOG.txt
assets/fonts/OpenDyslexic/OFL-FAQ.txt
assets/fonts/OpenDyslexic/OFL.txt
assets/fonts/OpenDyslexic/README.md
assets/fonts/OpenDyslexic/compiled/OpenDyslexic-Bold-Italic.otf
assets/fonts/OpenDyslexic/compiled/OpenDyslexic-Bold.otf
assets/fonts/OpenDyslexic/compiled/OpenDyslexic-Italic.otf
assets/fonts/OpenDyslexic/compiled/OpenDyslexic-Regular.otf
assets/fonts/PixelOperator/LICENSE.txt
assets/fonts/PixelOperator/PixelOperator-Bold.ttf
assets/fonts/PixelOperator/PixelOperator.ttf
assets/fonts/PixelOperator/PixelOperator8-Bold.ttf
assets/fonts/PixelOperator/PixelOperator8.ttf
assets/fonts/PixelOperator/PixelOperatorHB.ttf
assets/fonts/PixelOperator/PixelOperatorHB8.ttf
assets/fonts/PixelOperator/PixelOperatorHBSC.ttf
assets/fonts/PixelOperator/PixelOperatorMono-Bold.ttf
assets/fonts/PixelOperator/PixelOperatorMono.ttf
assets/fonts/PixelOperator/PixelOperatorMono8-Bold.ttf
assets/fonts/PixelOperator/PixelOperatorMono8.ttf
assets/fonts/PixelOperator/PixelOperatorMonoHB.ttf
assets/fonts/PixelOperator/PixelOperatorMonoHB8.ttf
assets/fonts/PixelOperator/PixelOperatorSC-Bold.ttf
assets/fonts/PixelOperator/PixelOperatorSC.ttf
assets/fonts/Pixelify_Sans/OFL.txt
assets/fonts/Pixelify_Sans/PixelifySans-VariableFont_wght.ttf
assets/fonts/Pixelify_Sans/README.txt
assets/fonts/Pixelify_Sans/static/PixelifySans-Bold.ttf
assets/fonts/Pixelify_Sans/static/PixelifySans-Medium.ttf
assets/fonts/Pixelify_Sans/static/PixelifySans-Regular.ttf
assets/fonts/Pixelify_Sans/static/PixelifySans-SemiBold.ttf
assets/fonts/Segoe/Segoe-UI-Bold.TTF
assets/fonts/Segoe/Segoe-UI-Italic.TTF
assets/fonts/Segoe/Segoe-UI-Light.TTF
assets/fonts/Segoe/Segoe-UI.TTF
assets/fonts/bitstream-vera/COPYRIGHT.TXT
assets/fonts/bitstream-vera/README.TXT
assets/fonts/bitstream-vera/RELEASENOTES.TXT
assets/fonts/bitstream-vera/Vera.ttf
assets/fonts/bitstream-vera/VeraBI.ttf
assets/fonts/bitstream-vera/VeraBd.ttf
assets/fonts/bitstream-vera/VeraIt.ttf
assets/fonts/bitstream-vera/VeraMoBI.ttf
assets/fonts/bitstream-vera/VeraMoBd.ttf
assets/fonts/bitstream-vera/VeraMoIt.ttf
assets/fonts/bitstream-vera/VeraMono.ttf
assets/fonts/bitstream-vera/VeraSe.ttf
assets/fonts/bitstream-vera/VeraSeBd.ttf
assets/fonts/bitstream-vera/local.conf
assets/fonts/hack/Hack-Bold.ttf
assets/fonts/hack/Hack-BoldItalic.ttf
assets/fonts/hack/Hack-Italic.ttf
assets/fonts/hack/Hack-Regular.ttf
assets/fonts/hack/LICENSE
assets/mod.zig
assets/sprite.png
assets/windows/main.manifest
build.zig
build.zig.zon
deepwiki/pages.json
deepwiki/parse.ts
deps/luaz
deps/msdf_zig/assets/msdf_placeholder_atlas.png
deps/msdf_zig/assets/msdf_placeholder_font.json
deps/msdf_zig/msdf_zig.zig
deps/msdf_zig/src/msdf_zig.zig
deps/msdf_zig/src/shader.zig
deps/msdf_zig/src/shaders/msdf_text_ui.wgsl
deps/msdf_zig/src/shaders/msdf_text_world.wgsl
deps/msdf_zig/src/types.zig
deps/solidluau
deps/wgpu_native_zig
deps/zig-yoga/build.zig
deps/zig-yoga/build.zig.zon
deps/zig-yoga/src/enums.zig
deps/zig-yoga/src/root.zig
docs/LAYOUT_TREE_DUMP.md
docs/RETAINED.md
docs/RETAINED_API.md
docs/UI_PRIMITIVES.md
docs/luau-findings/high-binary-event-payload-contract.md
docs/luau-findings/high-event-ring-saturation-after-lua-teardown.md
docs/luau-findings/high-stale-object-prop-clear-semantics.md
favicon.png
luau/_smoke/checkbox.luau
luau/_smoke/ui_refs.luau
luau/app.luau
luau/components/bar.luau
luau/components/checkbox.luau
luau/components/toggle.luau
luau/index.luau
luau/ui/cn.luau
luau/ui/load_ui.luau
luau/ui/types.luau
luau/ui_features_image_1.png
luau/ui_gen/app_ui.luau
luau/ui_json/app.json
readme-implementation.md
retained-architecture.md
snapshots/app.layout.json
solidluau_embedded.zig
src/accessibility/accesskit.zig
src/accessibility/mod.zig
src/backends/backend.zig
src/backends/common.zig
src/backends/mod.zig
src/backends/pipeline/compute.zig
src/backends/pipeline/depth.zig
src/backends/pipeline/geometry.zig
src/backends/pipeline/main.zig
src/backends/pipeline/render.zig
src/backends/pipeline/swap_chain.zig
src/backends/pipeline/types.zig
src/backends/raylib-zig.zig
src/backends/webgpu.zig
src/backends/webgpu/mod.zig
src/backends/webgpu/platform_macos.zig
src/backends/webgpu/platform_macos_metal_layer.m
src/backends/webgpu/platform_windows.zig
src/backends/wgpu.zig
src/core/color.zig
src/core/data.zig
src/core/enums.zig
src/core/mod.zig
src/core/options.zig
src/core/point.zig
src/core/rect.zig
src/core/size.zig
src/core/vertex.zig
src/dvui.zig
src/layout/easing.zig
src/layout/layout.zig
src/layout/mod.zig
src/layout/scroll_info.zig
src/main.zig
src/native_renderer/commands.zig
src/native_renderer/event_payload.zig
src/native_renderer/lifecycle.zig
src/native_renderer/luau_ui.zig
src/native_renderer/mod.zig
src/native_renderer/profiling.zig
src/native_renderer/types.zig
src/native_renderer/utils.zig
src/native_renderer/window.zig
src/platform/dialogs.zig
src/platform/io_compat.zig
src/platform/mod.zig
src/render/jpg_encoder.zig
src/render/mod.zig
src/render/path.zig
src/render/png_encoder.zig
src/render/render.zig
src/render/texture.zig
src/render/triangles.zig
src/retained/core/SUMMARY.md
src/retained/core/geometry.zig
src/retained/core/layout.zig
src/retained/core/media.zig
src/retained/core/node_store.zig
src/retained/core/types.zig
src/retained/core/visual.zig
src/retained/events/SUMMARY.md
src/retained/events/drag_drop.zig
src/retained/events/focus.zig
src/retained/events/mod.zig
src/retained/hit_test.zig
src/retained/layout/SUMMARY.md
src/retained/layout/flex.zig
src/retained/layout/measure.zig
src/retained/layout/mod.zig
src/retained/layout/text_wrap.zig
src/retained/layout/yoga.zig
src/retained/mod.zig
src/retained/render/cache.zig
src/retained/render/direct.zig
src/retained/render/icon_registry.zig
src/retained/render/image_loader.zig
src/retained/render/internal/derive.zig
src/retained/render/internal/hover.zig
src/retained/render/internal/interaction.zig
src/retained/render/internal/overlay.zig
src/retained/render/internal/renderers.zig
src/retained/render/internal/runtime.zig
src/retained/render/internal/state.zig
src/retained/render/internal/visual_sync.zig
src/retained/render/mod.zig
src/retained/render/transitions.zig
src/retained/style/apply.zig
src/retained/style/colors.zig
src/retained/style/mod.zig
src/retained/style/tailwind.zig
src/retained/style/tailwind/parse.zig
src/retained/style/tailwind/parse_color_typography.zig
src/retained/style/tailwind/parse_layout.zig
src/retained/style/tailwind/types.zig
src/testing/mod.zig
src/text/font.zig
src/text/mod.zig
src/text/selection.zig
src/theming/mod.zig
src/theming/shadcn.zon
src/theming/theme.zig
src/utils/alloc.zig
src/utils/cache_buster.zig
src/utils/mod.zig
src/utils/struct_ui.zig
src/utils/tracking_hash_map.zig
src/widgets/AnimateWidget.zig
src/widgets/BoxWidget.zig
src/widgets/ButtonWidget.zig
src/widgets/FlexBoxWidget.zig
src/widgets/GizmoWidget.zig
src/widgets/IconWidget.zig
src/widgets/LabelWidget.zig
src/widgets/MenuItemWidget.zig
src/widgets/MenuWidget.zig
src/widgets/ScaleWidget.zig
src/widgets/ScrollBarWidget.zig
src/widgets/SelectionWidget.zig
src/widgets/SelectionWidget/drawing.zig
src/widgets/SelectionWidget/events.zig
src/widgets/SelectionWidget/transform.zig
src/widgets/mod.zig
src/widgets/widget.zig
src/widgets/widget_data.zig
src/window/app.zig
src/window/debug.zig
src/window/dragging.zig
src/window/event.zig
src/window/mod.zig
src/window/subwindows.zig
src/window/window.zig
tools/layoutdump_scenes.json
tools/luau_layout_dump_main.zig
tools/luau_smoke.zig
tools/ui_codegen.zig
vendor/stb/stb_image.h
vendor/stb/stb_image_impl.c
vendor/stb/stb_image_libc.c
vendor/stb/stb_image_write.h
vendor/stb/stb_image_write_impl.c
vendor/stb/stb_truetype.h
vendor/stb/stb_truetype_impl.c
vendor/stb/stb_truetype_libc.c
zig_build_simple.sh
```

### Submodule: `deps/luaz` Tracked Files

```text
.claude/agents/general-purpose.md
.claude/commands/changelog.md
.claude/commands/commit.md
.claude/commands/guide.md
.claude/commands/release.md
.claude/commands/update-luau.md
.claude/settings.json
.github/actions/setup-zig/action.yml
.github/actions/setup-zig/install-zig.sh
.github/workflows/ci.yml
.github/workflows/claude.yml
.github/workflows/docs.yml
.gitignore
AGENTS.md
CHANGELOG.md
CONTRIBUTING.md
LICENSE
LUAU_API.md
README.md
build.zig
build.zig.zon
codecov.yml
docs/logo.png
examples/guided_tour.zig
examples/runtime_loop.zig
src/Compiler.zig
src/Debug.zig
src/GC.zig
src/Lua.zig
src/State.zig
src/alloc.zig
src/assert.zig
src/handler.cpp
src/handler.h
src/lib.zig
src/stack.zig
src/userdata.zig
zlint.json
```

### Submodule: `deps/solidluau` Tracked Files

```text
.gitignore
.gitmodules
README.md
TASK.md
ZIG_NATIVE_PLAN.md
build-docs
build.zig
build.zig.zon
docs/solidluau-animation.mdx
docs/solidluau-animationentry.mdx
docs/solidluau-reactivity.mdx
docs/solidluau-scheduler.mdx
docs/solidluau-ui-dsl.mdx
docs/solidluau-ui.mdx
docs/solidluau-uientry.mdx
docs/solidluau.mdx
luau-docs/README.md
luau-docs/index.ts
luau-docs/moonwave-extractor
luaz
scripts/build-docs.sh
solidluau_embed.zig
solidluau_modules.zig
src/ARCHITECTURE_REVIEW.md
src/README.md
src/animation.luau
src/animation/easing.luau
src/animation/engine.luau
src/animation/index.luau
src/animation/spring.luau
src/animation/tween.luau
src/core/reactivity.luau
src/core/scheduler.luau
src/solidluau.luau
src/ui.luau
src/ui/adapter_types.luau
src/ui/adapters/compat_ui.luau
src/ui/dsl.luau
src/ui/hydrate.luau
src/ui/index.luau
src/ui/renderer.luau
src/ui/types.luau
tests/luau/animation-mutableOutput-test.luau
tests/luau/reactivity-memo_invalidation_test.luau
tests/luau/reactivity-scope_unlink_test.luau
tests/luau/ui-dsl_tag_call_test.luau
tests/luau/ui-flat-props_cutover_test.luau
tests/luau/ui-patch_test.luau
vide/.gitignore
vide/OVERVIEW.md
vide/README.md
vide/docs/advanced/dynamic-scopes.md
vide/docs/api/animation.md
vide/docs/api/creation.md
vide/docs/api/reactivity-core.md
vide/docs/api/reactivity-dynamic.md
vide/docs/api/reactivity-utility.md
vide/docs/api/strict-mode.md
vide/docs/crash-course/1-introduction.md
vide/docs/crash-course/10-cleanup.md
vide/docs/crash-course/11-dynamic-scopes.md
vide/docs/crash-course/12-actions.md
vide/docs/crash-course/13-strict-mode.md
vide/docs/crash-course/14-concepts.md
vide/docs/crash-course/2-creation.md
vide/docs/crash-course/3-components.md
vide/docs/crash-course/4-source.md
vide/docs/crash-course/5-effect.md
vide/docs/crash-course/6-scope.md
vide/docs/crash-course/7-reactive-component.md
vide/docs/crash-course/8-implicit-effect.md
vide/docs/crash-course/9-derived-source.md
vide/init.luau
vide/src/action.luau
vide/src/apply.luau
vide/src/batch.luau
vide/src/branch.luau
vide/src/changed.luau
vide/src/cleanup.luau
vide/src/context.luau
vide/src/create.luau
vide/src/defaults.luau
vide/src/derive.luau
vide/src/effect.luau
vide/src/flags.luau
vide/src/graph.luau
vide/src/implicit_effect.luau
vide/src/indexes.luau
vide/src/init.luau
vide/src/lib.luau
vide/src/mount.luau
vide/src/read.luau
vide/src/root.luau
vide/src/show.luau
vide/src/source.luau
vide/src/spring.luau
vide/src/switch.luau
vide/src/timeout.luau
vide/src/untrack.luau
vide/src/values.luau
vide/test/benchmarks.luau
vide/test/create-types.luau
vide/test/mock.luau
vide/test/spring-test.luau
vide/test/stacktrace-test.luau
vide/test/testkit.luau
vide/test/tests.luau
zig/solidluau_embed.zig
zig/solidluau_modules.zig
zig/solidluau_tests.zig
```

### Submodule: `deps/wgpu_native_zig` Tracked Files

```text
.gitignore
LICENSE
README.md
build.zig
build.zig.zon
examples/bmp.zig
examples/output/.gitkeep
examples/triangle/shader.wgsl
examples/triangle/triangle.zig
src/adapter.zig
src/async.zig
src/bind_group.zig
src/buffer.zig
src/chained_struct.zig
src/command_encoder.zig
src/device.zig
src/global.zig
src/instance.zig
src/limits.zig
src/log.zig
src/misc.zig
src/pipeline.zig
src/query_set.zig
src/queue.zig
src/render_bundle.zig
src/root.zig
src/sampler.zig
src/shader.zig
src/surface.zig
src/texture.zig
test-all
tests/compute.wgsl
tests/compute.zig
tests/compute_c.zig
```
