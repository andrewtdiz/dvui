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
