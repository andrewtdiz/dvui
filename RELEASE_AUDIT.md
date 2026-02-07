# DVUI Engine Release Audit

Date: 2026-02-07  
Repo: `dvui` @ `c305d2e1c9142b8ec2e5465f71379a21968a7252`

## Scope

This audit focuses on **critical** and **high severity** issues that could impact a release in:

- Code architecture (coupling, correctness contracts)
- Runtime stability (crashes/hangs, undefined behavior)
- Runtime performance (obvious hot paths, O(N^2) traps, busy waits)
- Memory management (leaks, unbounded caches, allocator misuse)

Major directories reviewed via subagents:

- `src/` (core engine)
- `deps/` (submodules + vendored deps)
- `luau/` (script layer)
- `tools/` (build/test tools)
- `docs/` (public API/behavior contracts)
- `assets/` (embedded/runtime assets)
- `vendor/` (vendored C)
- `.github/` (CI)
- `deepwiki/` (docs generator)
- `artifacts/` and `snapshots/` (layout dumps)

Build sanity check in this environment:

- `./zig_build_simple.sh` exited `0`.

Out of scope / constraints:

- Runtime execution is not validated here.
- Some Zig tests/runs are not practical on WSL per `AGENTS.md`.

## Executive Summary (Release Blockers)

### Critical

1. **WGPU texture uploads violate WebGPU row-stride alignment**
   - Impact: texture creation and updates can fail validation or misbehave for most widths; this can break rendering (including font atlases) in the WGPU backend.
   - Locations:
     - `src/backends/wgpu.zig:1088` (creation path) uses `.bytes_per_row = width * 4`.
     - `src/backends/wgpu.zig:497` (update path) uses `.bytes_per_row = texture.width * 4`.

2. **Type confusion + potential misalignment UB in `Data` store**
   - Impact: requesting a different type (same `len`, different alignment/type) for an existing key can produce misaligned pointers or type-punned access (undefined behavior in ReleaseFast).
   - Location: `src/core/data.zig:146` (`getOrPut` only validates/reallocates when `len` changes).

3. **Synchronous WGPU adapter/device acquisition can spin or hang indefinitely**
   - Impact: startup can hang forever on systems where adapter/device callbacks never complete; passing `0` poll interval can also create a busy-spin.
   - Location: `src/backends/pipeline/swap_chain.zig:43` and `src/backends/pipeline/swap_chain.zig:75` call `requestAdapterSync(..., 0)` / `requestDeviceSync(..., 0)`.

### High

1. **Default WGPU “device lost” handler panics** (dependency behavior)
   - Impact: real-world GPU device loss (driver reset, sleep/resume, TDR) can hard-crash the process unless DVUI overrides the callback.
   - Evidence:
     - `deps/wgpu_native_zig/src/device.zig:80` defines a default callback that panics.
     - DVUI does not set `device_lost_callback_info` in `src/backends/pipeline/swap_chain.zig`.

2. **`.pixelsPMA` “bytes invalidation” hashing likely hashes the wrong byte count**
   - Impact: dynamic textures using `.pixelsPMA` with `.invalidation = .bytes` may fail to invalidate, producing stale textures.
   - Location: `src/render/texture.zig:169` uses `h.update(@ptrCast(pixels.rgba))` instead of `std.mem.sliceAsBytes(pixels.rgba)`.

3. **Unbounded retained caches allocate with `c_allocator` and never evict**
   - Impact: long-running sessions that load many images/icons/classes can grow memory without bound.
   - Locations:
     - `src/retained/render/image_loader.zig:11` global `image_cache`
     - `src/retained/render/icon_registry.zig:33` global `icon_cache`
     - `src/retained/style/tailwind.zig:27` global `spec_cache`

4. **Documentation contradicts implementation for retained features and event payloads**
   - Impact: users will write handlers/markup based on docs that do not match real behavior.
   - Examples:
     - `docs/RETAINED_API.md:194` says scroll is “not applied” (appears accurate in code), but `docs/RETAINED.md:67` claims scroll offsets shift child coordinate space (not implemented).
     - `docs/RETAINED_API.md:207` claims anchor “not applied”, but code does apply anchor placement.
     - `docs/RETAINED.md:5` claims `on_event(kind_int, id, payload_bytes)` but native renderer passes a structured table for pointer/drag payloads.

5. **CI workflow appears out of sync with this repo’s build**
   - Impact: false confidence; critical regressions won’t be caught.
   - Examples:
     - `/.github/workflows/test.yml:7` uses `branches: [$default-branch]` (likely never triggers on push).
     - `/.github/workflows/test.yml:28` uses `zig build -Dbackend=testing`, but this repo’s `build.zig` does not define `-Dbackend`.
     - `/.github/workflows/test.yml:23` does not checkout submodules.

6. **Luau UI loaders are DoS/code-execution risks if fed untrusted input**
   - Impact: stack overflow / memory exhaustion / executing arbitrary module code (depending on embedding policy).
   - Locations:
     - `luau/ui/load_ui.luau` unbounded recursion and `require(module_id)`
     - `luau/ui/cn.luau` recursive traversal without cycle detection

## Detailed Findings

### 1) Memory Safety / Undefined Behavior

#### 1.1 `Data.getOrPut` can reuse storage across type/alignment changes (UB)

- Location: `src/core/data.zig:146`
- Mechanism:
  - `getOrPut` only re-trashes/reallocates when `entry.value_ptr.data.len != len` (`should_trash` at `src/core/data.zig:155`).
  - If the same key is later used with a different type/slice element type that has the **same byte length** but different alignment or interpretation, `getOrPutT` / `getOrPutSliceT` will still `@alignCast` and `@ptrCast` the existing allocation.
- Impact:
  - In Debug/ReleaseSafe, `@alignCast` can trap.
  - In ReleaseFast, misalignment and type confusion can become undefined behavior.
- Why this matters for release:
  - `Window.data_store` is a fundamental state mechanism (`src/window/window.zig:100`). A single accidental key reuse across widgets/types can become a hard-to-debug crash.
- Suggested fix direction (minimal):
  - Treat `alignment` and debug info mismatch as “must trash/realloc”, not only length mismatch.
  - Update stored `alignment`/`debug` when overwriting existing entries.

### 2) WGPU Backend Correctness / Stability

#### 2.1 WebGPU `bytes_per_row` alignment is wrong for texture uploads

- Locations:
  - `src/backends/wgpu.zig:1118` (`createTextureResourceKind`)
  - `src/backends/wgpu.zig:511` (`textureUpdate`)
- Mechanism:
  - `.bytes_per_row = width * 4` for RGBA8.
- Impact:
  - WebGPU requires `bytes_per_row` to be a multiple of 256 bytes (common enforcement in native wgpu). Any width not divisible by 64 will violate this.
  - This affects core rendering paths: font atlas uploads, image textures, UI textures.
- Suggested fix direction:
  - Allocate a temporary staging buffer with padded rows:
    - `aligned_bpr = alignForward(width * 4, 256)`
    - Copy each row into the padded buffer
    - Upload with `bytes_per_row = aligned_bpr`
  - Alternatively use `copyBufferToTexture` with proper alignment.

#### 2.2 `requestAdapterSync(..., 0)` / `requestDeviceSync(..., 0)` risks busy-spin or hang

- Location: `src/backends/pipeline/swap_chain.zig:43` and `src/backends/pipeline/swap_chain.zig:75`
- Impact:
  - No timeout/cancel path.
  - Poll interval of `0` risks a tight loop depending on dep implementation.
- Suggested fix direction:
  - Provide a non-zero polling interval and a bounded timeout.
  - Prefer async request path and surface a failure to the caller.

#### 2.3 Device lost handling defaults to panic unless overridden

- Evidence:
  - `deps/wgpu_native_zig/src/device.zig:89` default device-lost callback panics.
  - DVUI does not set `.device_lost_callback_info` in the device descriptor (`src/backends/pipeline/swap_chain.zig:75`).
- Impact:
  - GPU device loss becomes a process crash.
- Suggested fix direction:
  - Set a device lost callback that triggers a controlled teardown/reinit path.

#### 2.4 WGPU integration/packaging risks (deps)

- Evidence (dependency build notes):
  - `deps/wgpu_native_zig/build.zig` indicates DLL/dylib copying is unreliable for dependents and some paths are “guesswork”.
- Impact:
  - Releases can run on dev machines but ship missing runtime libraries.
- Suggested mitigation:
  - Add explicit packaging steps per target (Windows DLL, macOS dylib rpath/install_name handling).

### 3) Memory Growth / Cache Management

#### 3.1 Retained image cache is global, unbounded, and uses `c_allocator`

- Location: `src/retained/render/image_loader.zig:11`
- Impact:
  - Every unique image path duplicates file bytes into heap memory and is never evicted.
  - `deinit()` frees, but long-running sessions can grow without bound.
- Suggested fix direction:
  - Add an eviction policy (LRU) or a size cap (total bytes).
  - Consider using the engine’s allocator rather than `c_allocator`.

#### 3.2 Retained icon registry cache is global, unbounded, and uses `c_allocator`

- Location: `src/retained/render/icon_registry.zig:33`
- Impact:
  - SVG/TVG/icon bytes are duplicated and retained indefinitely.
- Suggested fix direction:
  - Same as image cache: cap and/or eviction; use controlled allocator.

#### 3.3 Tailwind spec cache is global and grows without bound

- Location: `src/retained/style/tailwind.zig:27`
- Impact:
  - If class strings are dynamic (generated at runtime), memory will grow indefinitely.
- Suggested fix direction:
  - Cap entries, expose a cache clear API, or restrict caching to interned/static class strings.

#### 3.4 Embedded fonts materially increase artifact size

- Evidence:
  - `assets/fonts.zig` embeds multiple fonts, including a ~6MB Noto Sans KR and ~3.3MB Segoe set.
  - `src/text/font.zig:273` loads builtins into the font database.
  - `src/window/window.zig:191` notes a TODO to opt out of builtin fonts.
- Impact:
  - Larger binaries and potentially larger working sets.
- Suggested mitigation:
  - Provide build option to exclude builtins.
  - Move large fonts to runtime-loading for products that don’t need them.

### 4) Runtime Performance

#### 4.1 Per-frame text aggregation allocs can be expensive on large retained trees

- Location: `src/retained/render/internal/renderers.zig:1820`
- Notes:
  - Uses an arena allocator per frame (`src/retained/render/mod.zig:63`), so this does not leak across frames.
  - However, repeated subtree concatenation per widget can become expensive with deep or broad trees.
- Mitigation:
  - Cache aggregated text per node/subtree and invalidate based on subtree version.
  - Pre-size the `ArrayList(u8)` when building to reduce copies.

#### 4.2 Adapter/device sync request can consume CPU

- Location: `src/backends/pipeline/swap_chain.zig:43`
- Mitigation:
  - Use non-zero poll interval and timeout.

### 5) Documentation / Contract Issues

#### 5.1 `ARCHITECTURE.md` is referenced but missing

- Evidence:
  - `AGENTS.md:3` references `ARCHITECTURE.md`.
  - `docs/RETAINED.md:104` also references it.
- Impact:
  - Missing canonical architecture contract increases risk of regressions and misuses.

#### 5.2 Retained anchor docs contradict implementation

- Docs claim:
  - `docs/RETAINED_API.md:207` says anchored placement is not applied.
- Code reality:
  - `src/retained/layout/mod.zig:70` calls `applyAnchoredPlacement`.
  - `src/retained/layout/mod.zig:354` implements anchored placement.
- Impact:
  - Users will avoid or misuse the feature.

#### 5.3 Retained scroll docs overstate implementation

- Docs claim:
  - `docs/RETAINED.md:67` states scrolling shifts child coordinate space and is wired into layout/render.
- Code reality:
  - `ScrollState.offset_x/offset_y` are never updated (no writes found).
  - Scrollbars renderer exists but is unused (`src/retained/render/internal/interaction.zig:282` has no call sites).
- Impact:
  - Feature appears incomplete; docs are misleading.

#### 5.4 Event payload contract docs are inconsistent

- Evidence:
  - `docs/RETAINED.md:5` claims raw `payload_bytes` always.
  - Native renderer decodes pointer/drag payload to a Lua table: `src/native_renderer/window.zig:184`.
  - `docs/luau-findings/high-binary-event-payload-contract.md` claims current behavior is raw bytes, which appears outdated.

### 6) CI / Release Process Risk

- Location: `/.github/workflows/test.yml`
- High issues:
  - Push trigger likely incorrect: `/.github/workflows/test.yml:7` (`$default-branch` is not a GitHub Actions variable).
  - Build flags don’t match this repo: `/.github/workflows/test.yml:28` uses `-Dbackend=testing`, but `build.zig` does not define it.
  - Submodules aren’t checked out: `/.github/workflows/test.yml:23` and `/.github/workflows/test.yml:54`.
  - No macOS coverage; only compile-only for most backends.

### 7) Luau Scripting Risks (Context-Dependent)

If any of these functions can consume untrusted input (e.g., user-provided JSON/UI specs or module IDs), the risks are high:

- `luau/ui/load_ui.luau`
  - Unbounded recursion building nodes.
  - `from_json` calls `require(module_id)` directly.
- `luau/ui/cn.luau`
  - Recursive traversal without cycle detection.

If all inputs are trusted/static, these downgrade to low.

### 8) Repo Hygiene / Misc

- Tracked macOS metadata file: `.DS_Store` is committed (`git ls-files` includes it) and not ignored.
- `deepwiki/pages.json` is empty (0 bytes), so DeepWiki content generation is currently a no-op.

## Prioritized Fix Plan (Release-Oriented)

1. Fix WGPU texture upload alignment in `src/backends/wgpu.zig` (creation + update).  
2. Add timeout/non-zero polling to adapter/device acquisition and expose failures cleanly (`src/backends/pipeline/swap_chain.zig`).  
3. Override WGPU device-lost callback with a non-panicking handler; plan for recovery.  
4. Fix `.pixelsPMA` invalidation hashing (`src/render/texture.zig`).  
5. Fix `Data.getOrPut` type/alignment reuse hazard (`src/core/data.zig`).  
6. Decide policy for retained caches: caps/eviction + allocator ownership (`src/retained/render/image_loader.zig`, `src/retained/render/icon_registry.zig`, `src/retained/style/tailwind.zig`).  
7. Align docs with implementation (or implement missing parts), especially retained scroll/anchor and event payload shapes.
8. Repair CI so it actually exercises this repo’s build, and checks out submodules.

## Appendix A: Submodules

`git submodule status --recursive` (as of this audit):

- `deps/luaz` @ `479d5dcf907ceef5aafc224f8ed735561ca19e6a` (heads/mainline)
- `deps/solidluau` @ `65a8bb7dfd11fdbb0f3c1c4d11efcea31858b7a4` (heads/mainline)
  - nested `deps/solidluau/luaz` is not initialized in this workspace
- `deps/wgpu_native_zig` @ `8f1ae3e7561f11e0bf0c6d122f9a53f68991c26d`

## Appendix B: Largest Assets

Largest items under `assets/` (approximate):

- `assets/fonts/NotoSansKR-Regular.ttf`: ~6.0MB
- `assets/fonts/Segoe/Segoe-UI.TTF`: ~956KB
- `assets/fonts/Segoe/Segoe-UI-Bold.TTF`: ~944KB
- `assets/fonts/Segoe/Segoe-UI-Light.TTF`: ~904KB
- `assets/fonts/Segoe/Segoe-UI-Italic.TTF`: ~520KB

Total `assets/` size: ~16MB.

## Appendix C: File Inventory (excluding `.git/`, `.zig-cache/`, `zig-out/`)

```text
.DS_Store
.github/workflows/test.yml
.gitignore
.gitmodules
AGENTS.md
LICENSE
RELEASE_AUDIT.md
UI_FEATURES.md
artifacts/app.layout.json
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
deps/luaz/.claude/agents/general-purpose.md
deps/luaz/.claude/commands/changelog.md
deps/luaz/.claude/commands/commit.md
deps/luaz/.claude/commands/guide.md
deps/luaz/.claude/commands/release.md
deps/luaz/.claude/commands/update-luau.md
deps/luaz/.claude/settings.json
deps/luaz/.git
deps/luaz/.github/actions/setup-zig/action.yml
deps/luaz/.github/actions/setup-zig/install-zig.sh
deps/luaz/.github/workflows/ci.yml
deps/luaz/.github/workflows/claude.yml
deps/luaz/.github/workflows/docs.yml
deps/luaz/.gitignore
deps/luaz/.zig-cache/h/9588b69c8bd200e4dd31b37597038e70.txt
deps/luaz/.zig-cache/h/timestamp
deps/luaz/.zig-cache/o/b73f8f8d266a149a6f728a6178927426/dependencies.zig
deps/luaz/.zig-cache/tmp/1e82bb8041bc07db/build
deps/luaz/.zig-cache/tmp/3499da70192454ac/build
deps/luaz/.zig-cache/tmp/456b4c0cca8a11dd/build
deps/luaz/.zig-cache/tmp/715b00f6d888175f/build
deps/luaz/.zig-cache/tmp/8f73286486943ee9/build
deps/luaz/.zig-cache/tmp/a46e15fcfe9a6845/build
deps/luaz/.zig-cache/tmp/ff26d57fca2adee9/build
deps/luaz/.zig-cache/z/04b73e187d959132551ecfabd7b16559
deps/luaz/.zig-cache/z/0f5bec242ffa3fc05507684c91e54e94
deps/luaz/.zig-cache/z/3156d258ec3fcf3b1ad3bcd3ffd30d6e
deps/luaz/.zig-cache/z/842fd77e65570656c07b8bd3ee53c244
deps/luaz/AGENTS.md
deps/luaz/CHANGELOG.md
deps/luaz/CONTRIBUTING.md
deps/luaz/LICENSE
deps/luaz/LUAU_API.md
deps/luaz/README.md
deps/luaz/build.zig
deps/luaz/build.zig.zon
deps/luaz/codecov.yml
deps/luaz/docs/logo.png
deps/luaz/examples/guided_tour.zig
deps/luaz/examples/runtime_loop.zig
deps/luaz/src/Compiler.zig
deps/luaz/src/Debug.zig
deps/luaz/src/GC.zig
deps/luaz/src/Lua.zig
deps/luaz/src/State.zig
deps/luaz/src/alloc.zig
deps/luaz/src/assert.zig
deps/luaz/src/handler.cpp
deps/luaz/src/handler.h
deps/luaz/src/lib.zig
deps/luaz/src/stack.zig
deps/luaz/src/userdata.zig
deps/luaz/zlint.json
deps/msdf_zig/assets/msdf_placeholder_atlas.png
deps/msdf_zig/assets/msdf_placeholder_font.json
deps/msdf_zig/msdf_zig.zig
deps/msdf_zig/src/msdf_zig.zig
deps/msdf_zig/src/shader.zig
deps/msdf_zig/src/shaders/msdf_text_ui.wgsl
deps/msdf_zig/src/shaders/msdf_text_world.wgsl
deps/msdf_zig/src/types.zig
deps/solidluau/.git
deps/solidluau/.gitignore
deps/solidluau/.gitmodules
deps/solidluau/README.md
deps/solidluau/TASK.md
deps/solidluau/ZIG_NATIVE_PLAN.md
deps/solidluau/build-docs
deps/solidluau/build.zig
deps/solidluau/build.zig.zon
deps/solidluau/docs/solidluau-animation.mdx
deps/solidluau/docs/solidluau-animationentry.mdx
deps/solidluau/docs/solidluau-reactivity.mdx
deps/solidluau/docs/solidluau-scheduler.mdx
deps/solidluau/docs/solidluau-ui-dsl.mdx
deps/solidluau/docs/solidluau-ui.mdx
deps/solidluau/docs/solidluau-uientry.mdx
deps/solidluau/docs/solidluau.mdx
deps/solidluau/luau-docs/README.md
deps/solidluau/luau-docs/index.ts
deps/solidluau/luau-docs/moonwave-extractor
deps/solidluau/scripts/build-docs.sh
deps/solidluau/solidluau_embed.zig
deps/solidluau/solidluau_modules.zig
deps/solidluau/src/ARCHITECTURE_REVIEW.md
deps/solidluau/src/README.md
deps/solidluau/src/animation.luau
deps/solidluau/src/animation/easing.luau
deps/solidluau/src/animation/engine.luau
deps/solidluau/src/animation/index.luau
deps/solidluau/src/animation/spring.luau
deps/solidluau/src/animation/tween.luau
deps/solidluau/src/core/reactivity.luau
deps/solidluau/src/core/scheduler.luau
deps/solidluau/src/solidluau.luau
deps/solidluau/src/ui.luau
deps/solidluau/src/ui/adapter_types.luau
deps/solidluau/src/ui/adapters/compat_ui.luau
deps/solidluau/src/ui/dsl.luau
deps/solidluau/src/ui/hydrate.luau
deps/solidluau/src/ui/index.luau
deps/solidluau/src/ui/renderer.luau
deps/solidluau/src/ui/types.luau
deps/solidluau/tests/luau/animation-mutableOutput-test.luau
deps/solidluau/tests/luau/reactivity-memo_invalidation_test.luau
deps/solidluau/tests/luau/reactivity-scope_unlink_test.luau
deps/solidluau/tests/luau/ui-dsl_tag_call_test.luau
deps/solidluau/tests/luau/ui-flat-props_cutover_test.luau
deps/solidluau/tests/luau/ui-patch_test.luau
deps/solidluau/vide/.gitignore
deps/solidluau/vide/OVERVIEW.md
deps/solidluau/vide/README.md
deps/solidluau/vide/docs/advanced/dynamic-scopes.md
deps/solidluau/vide/docs/api/animation.md
deps/solidluau/vide/docs/api/creation.md
deps/solidluau/vide/docs/api/reactivity-core.md
deps/solidluau/vide/docs/api/reactivity-dynamic.md
deps/solidluau/vide/docs/api/reactivity-utility.md
deps/solidluau/vide/docs/api/strict-mode.md
deps/solidluau/vide/docs/crash-course/1-introduction.md
deps/solidluau/vide/docs/crash-course/10-cleanup.md
deps/solidluau/vide/docs/crash-course/11-dynamic-scopes.md
deps/solidluau/vide/docs/crash-course/12-actions.md
deps/solidluau/vide/docs/crash-course/13-strict-mode.md
deps/solidluau/vide/docs/crash-course/14-concepts.md
deps/solidluau/vide/docs/crash-course/2-creation.md
deps/solidluau/vide/docs/crash-course/3-components.md
deps/solidluau/vide/docs/crash-course/4-source.md
deps/solidluau/vide/docs/crash-course/5-effect.md
deps/solidluau/vide/docs/crash-course/6-scope.md
deps/solidluau/vide/docs/crash-course/7-reactive-component.md
deps/solidluau/vide/docs/crash-course/8-implicit-effect.md
deps/solidluau/vide/docs/crash-course/9-derived-source.md
deps/solidluau/vide/init.luau
deps/solidluau/vide/src/action.luau
deps/solidluau/vide/src/apply.luau
deps/solidluau/vide/src/batch.luau
deps/solidluau/vide/src/branch.luau
deps/solidluau/vide/src/changed.luau
deps/solidluau/vide/src/cleanup.luau
deps/solidluau/vide/src/context.luau
deps/solidluau/vide/src/create.luau
deps/solidluau/vide/src/defaults.luau
deps/solidluau/vide/src/derive.luau
deps/solidluau/vide/src/effect.luau
deps/solidluau/vide/src/flags.luau
deps/solidluau/vide/src/graph.luau
deps/solidluau/vide/src/implicit_effect.luau
deps/solidluau/vide/src/indexes.luau
deps/solidluau/vide/src/init.luau
deps/solidluau/vide/src/lib.luau
deps/solidluau/vide/src/mount.luau
deps/solidluau/vide/src/read.luau
deps/solidluau/vide/src/root.luau
deps/solidluau/vide/src/show.luau
deps/solidluau/vide/src/source.luau
deps/solidluau/vide/src/spring.luau
deps/solidluau/vide/src/switch.luau
deps/solidluau/vide/src/timeout.luau
deps/solidluau/vide/src/untrack.luau
deps/solidluau/vide/src/values.luau
deps/solidluau/vide/test/benchmarks.luau
deps/solidluau/vide/test/create-types.luau
deps/solidluau/vide/test/mock.luau
deps/solidluau/vide/test/spring-test.luau
deps/solidluau/vide/test/stacktrace-test.luau
deps/solidluau/vide/test/testkit.luau
deps/solidluau/vide/test/tests.luau
deps/solidluau/zig/solidluau_embed.zig
deps/solidluau/zig/solidluau_modules.zig
deps/solidluau/zig/solidluau_tests.zig
deps/wgpu_native_zig/.git
deps/wgpu_native_zig/.gitignore
deps/wgpu_native_zig/LICENSE
deps/wgpu_native_zig/README.md
deps/wgpu_native_zig/build.zig
deps/wgpu_native_zig/build.zig.zon
deps/wgpu_native_zig/examples/bmp.zig
deps/wgpu_native_zig/examples/output/.gitkeep
deps/wgpu_native_zig/examples/triangle/shader.wgsl
deps/wgpu_native_zig/examples/triangle/triangle.zig
deps/wgpu_native_zig/src/adapter.zig
deps/wgpu_native_zig/src/async.zig
deps/wgpu_native_zig/src/bind_group.zig
deps/wgpu_native_zig/src/buffer.zig
deps/wgpu_native_zig/src/chained_struct.zig
deps/wgpu_native_zig/src/command_encoder.zig
deps/wgpu_native_zig/src/device.zig
deps/wgpu_native_zig/src/global.zig
deps/wgpu_native_zig/src/instance.zig
deps/wgpu_native_zig/src/limits.zig
deps/wgpu_native_zig/src/log.zig
deps/wgpu_native_zig/src/misc.zig
deps/wgpu_native_zig/src/pipeline.zig
deps/wgpu_native_zig/src/query_set.zig
deps/wgpu_native_zig/src/queue.zig
deps/wgpu_native_zig/src/render_bundle.zig
deps/wgpu_native_zig/src/root.zig
deps/wgpu_native_zig/src/sampler.zig
deps/wgpu_native_zig/src/shader.zig
deps/wgpu_native_zig/src/surface.zig
deps/wgpu_native_zig/src/texture.zig
deps/wgpu_native_zig/test-all
deps/wgpu_native_zig/tests/compute.wgsl
deps/wgpu_native_zig/tests/compute.zig
deps/wgpu_native_zig/tests/compute_c.zig
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
