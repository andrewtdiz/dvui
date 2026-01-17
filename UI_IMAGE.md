Implement “ImageFrame image object” support in dvui_retained (Zig) so Clay Engine can drive images with src, tint, and opacity separately from background.

Context

- An downstream repo uses dvui ops (deps/dvui/src/retained/render/mod.zig).
- Current rendering path for "image" nodes calls dvui.image(@src(), .{ .source = image_source }, options) in deps/dvui/src/retained/render/mod.zig:renderImage.
- applyVisualToOptions currently applies opacity by multiplying alpha into both background/text colors. This does not tint images and does not provide “image opacity” as a separate
  concept.
- dvui.render/render.zig supports TextureOptions.colormod: Color and multiplies it into the triangles, so tinting should be possible by setting colormod for image render.

Goal
Add a first-class “image” object to retained nodes and ops, with these fields:

- src: string (existing semantics)
- tint: u32 packed RGBA 0xRRGGBBAA (or separate r/g/b/a, but prefer packed u32 for retained parity)
- opacity: f32 0..1 (multiplies final image alpha; distinct from background alpha)
- (optional, if easy) rotation: f32 radians, scaleX: f32, scaleY: f32 for image-only transform, if you prefer not to reuse existing Transform

Concrete changes requested

1. Data model (retained core)

- In deps/dvui/src/retained/core/types.zig:
    - Add to SolidNode:
        - image_tint: ?PackedColor = null (or ?u32)
        - image_opacity: f32 = 1.0
    - Add methods:
        - setImageTint(self: *SolidNode, value: u32) void (marks paint dirty + node changed)
        - setImageOpacity(self: *SolidNode, value: f32) void (clamp 0..1; marks paint dirty + node changed)
    - Add store methods on NodeStore:
        - setImageTint(id: u32, value: u32) !void
        - setImageOpacity(id: u32, value: f32) !void

2. JSON snapshot parsing

- In deps/dvui/src/retained/mod.zig:
    - Extend SolidSnapshotNode with an optional image object:
        - image: ?struct { src?: []const u8, tint?: u32, opacity?: f32 } = null
    - Backward compat:
        - If image is present, prefer image.src over legacy src.
        - Continue supporting legacy src for older snapshots.
    - Apply snapshot:
        - After node creation, apply src as today.
        - If image.tint present => set image tint.
        - If image.opacity present => set image opacity.

3. Incremental ops parsing

- In deps/dvui/src/retained/mod.zig:
    - Extend SolidOp to accept image object too:
        - image: ?struct { src?: []const u8, tint?: u32, opacity?: f32 } = null
    - Add op(s):
        - Either:
            - New op name "set_image" that updates any provided image fields, OR
            - Support "set" with name: "image" and value containing JSON for the object.
        - Prefer "set_image" since other domains already use "set_visual", "set_transform", etc.
    - Ensure applying image fields calls store setters and markNodeChanged.

4. Rendering (tint + opacity)

- In deps/dvui/src/retained/render/mod.zig, inside renderImage:
    - Keep current options pipeline (class spec, fonts, transforms, accessibility).
    - Before calling dvui.image, apply image tint + image opacity:
        - Use dvui.render.renderImage(source, rs, TextureOptions{ .colormod = tintColorWithOpacity, .rotation = ... }) if that’s a better entry point than dvui.image.
        - Or, if sticking to dvui.image, modify dvui.image or its internal RenderTextureOptions usage so the underlying TextureOptions.colormod is set from retained node fields.
    - Tint behavior:
        - Default tint = white (no change).
        - If image_tint is set, multiply image by that color.
    - Opacity behavior:
        - Final alpha should be (global dvui alpha) * (node.visual.opacity?) * (image_opacity) * (tint alpha).
        - Important: this should affect the image only, not the node’s background.
        - This implies image opacity should not be implemented by changing options.color_fill etc.

Acceptance criteria

- A retained "image" node with image: { src: "path.png", tint: 0xFF0000FF, opacity: 0.5 } renders:
    - correct source
    - tinted red
    - at 50% alpha, without changing any background fill behavior
- Existing snapshots that only set legacy src continue to render as before.
- Ops can update tint/opacity without requiring a full snapshot.

Notes

- Please keep changes scoped to deps/dvui retained system; downstream libraries can send the image object from its UI JSON later.
- If you’d rather represent tint as { r,g,b,a } instead of packed u32, say so; can match either, but packed is simpler given existing PackedColor usage.