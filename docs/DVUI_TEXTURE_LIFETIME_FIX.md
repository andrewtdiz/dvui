# DVUI Texture Lifetime: Root Cause and Required Engine Fix

## Symptom (what you’re seeing)
- When a game object (e.g. the breakout ball) loads an image and calls `setTexture(...)`, Solid/DVUI UI layout starts behaving incorrectly.
- If you comment out the texture assignment, layout/rendering is stable again.

## Root Cause (DVUI texture cache semantics)
DVUI maintains an **internal per‑frame texture cache**.

- At the start of every frame (`Window.begin`), DVUI calls `texture_cache.reset(...)`.
- Any cached texture that was **not accessed (“touched”) in the previous frame** is destroyed.
- Therefore, a `dvui.Texture` handle **is only valid if the cache is re‑accessed every frame**.

Relevant code:
- Cache reset each frame: `src/window/window.zig` in `Window.begin` (look for `texture_cache.reset(self.backend)`).
- Cache contract warning: `src/dvui.zig` docs for `textureGetCached`.
- ImageSource caching path: `src/render/texture.zig` → `ImageSource.getTexture()`.

## Why storing a Texture handle breaks things
Most engine code patterns do this:
1. Load image once.
2. Create a DVUI texture once (`ImageSource.getTexture()` or `textureAddToCache`).
3. Store the returned `dvui.Texture` on the object (`ball.setTexture(tex)`).
4. On later frames, render using that stored handle **without touching the cache**.

Because the cache is GC’d each frame, the stored handle becomes a **dangling GPU pointer** after one frame. Using it causes undefined backend behavior (bad clipping/transforms, layout drift, “fixes itself” on resize).

## Required Fix (what needs to be implemented)
You must **stop holding raw `dvui.Texture` handles across frames** unless you keep them alive.

### Option A (recommended): Store ImageSource or cache key, reacquire every frame
**Engine change:**
- Change your texture fields / `setTexture` API to store either:
  - a stable `dvui.ImageSource` (usually `.imageFile { bytes, name, ... }`), or
  - a stable cache key + enough data to rebuild an ImageSource.

**Render‑time rule:**
- Every frame, right before drawing a textured object:
  1. Call `image_source.getTexture()` (or `dvui.textureGetCached(key)` fallback).
  2. Use the returned `dvui.Texture` for this frame’s draw.

This both:
- re‑touches the cache so DVUI won’t destroy it, and
- safely recreates the texture if DVUI GC’d it earlier.

**Minimal example (Zig pseudo‑pattern):**
```zig
// stored long-term on your mesh/sprite
const TextureHandle = struct {
    source: dvui.ImageSource, // or your own wrapper around bytes/path

    pub fn textureForFrame(self: *const TextureHandle) !dvui.Texture {
        return try self.source.getTexture();
    }
};

// in your per-frame render loop
const tex = try mesh.texture_handle.textureForFrame();
dvui.renderTexture(tex, rs, opts) catch {};
```

### Option B: Use ImageSource `.texture` and manage lifetime yourself
If your engine wants full manual control:
- Create textures via backend directly (`dvui.textureCreate`, etc.).
- Store them in an ImageSource `.texture = tex`.
- **Do not rely on DVUI’s cache.**
- Explicitly destroy them when the engine unloads the asset.

This avoids cache GC, but shifts responsibility to the engine.

### Critical requirement: image bytes must be long‑lived
DVUI’s default invalidation strategy for `.imageFile` is `.ptr`.
That means the cache key depends on the bytes pointer.

So:
- Ensure the image bytes are allocated from a long‑lived allocator (GPA / c_allocator / asset manager), not a per‑frame arena.
- If you must mutate/replace bytes in place, set invalidation to `.bytes` or `.always`.

## Implementation Checklist
1. **Locate where textures are stored long‑term.**
   - e.g. `Mesh`, `Sprite`, `Ball`, etc.
2. **Change storage type:**
   - Replace stored `dvui.Texture` with stored `dvui.ImageSource` (or your own `TextureHandle`).
3. **Update `setTexture(...)`:**
   - It should set the stored ImageSource/handle, not call `getTexture` once and store the result.
4. **Update render loop:**
   - Right before any textured draw, reacquire with `getTexture()`.
5. **Ensure asset bytes live long enough** and are not frame‑allocator owned.

After these changes, adding a texture will no longer destabilize layout/rendering.

