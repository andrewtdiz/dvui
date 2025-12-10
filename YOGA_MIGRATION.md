## Yoga Migration Plan

Goal: integrate `deps/zig-yoga` so layout is computed by Yoga and DVUI only paints/handles input. This removes hard-coded layout in `solid_renderer` and `TextLayoutWidget`.

### Architecture

- Build a Yoga tree from Solid `NodeStore` each frame (or reuse handles with dirty flags). Run `calculateLayout` with viewport size.
- Store computed rects on Solid nodes (e.g. `layout: dvui.Rect`) for both border-box and content-box.
- Render using those rects: set `options.rect = node.layout` and `options.expand = .none`; skip DVUI flex/box sizing.

### Tailwind → Yoga mapping

- Flex: direction, wrap, grow/shrink/basis, justify/align, gap (`setGap`), padding/margin, width/height/min/max, position (absolute/relative), display (`hidden` → `Display.None`), overflow.
- Add `tailwind_yoga.zig` adapter that consumes `tailwind.ClassSpec` and applies Yoga setters.

### Renderer changes

- In `renderElementBody`, if a node has a Yoga layout:
  - Do not create `dvui.flexbox`/`dvui.box` for sizing; only optional box for background/border with fixed `rect`.
  - Render children in tree order; layout already decided by Yoga.
- Remove spacer-based gaps once Yoga gap is used.
- Keep cache/dirty logic: mark Yoga node dirty when Solid node or class list changes; `markLayoutSeen` after render.

### Text integration

- Extract a pure measurement helper from `TextLayoutWidget` (no selection/cursor side effects): `measure(text, opts, max_width) -> Size`.
- Use that helper as Yoga `measureFunc` for text-like nodes (`text`, `p`, `h1-3`).
- `TextLayoutWidget` should accept a provided rect (`options.rect`) and avoid re-wrapping when width is fixed; keep current interactive behavior.

### Leaf measurement

- Text: use the extracted helper (wrap rules match current `addTextEx`).
- Button: measure caption via font metrics + padding from tailwind.
- Input: measure using `TextEntryWidget` defaults (font height + padding).
- Image: intrinsic size from `image_loader`.
- Other leaves: fallback to min content size rules.

### Minimal POC: FlexBoxWidget

- Goal: demonstrate Yoga driving layout for existing DVUI widgets without changing higher-level renderer yet.
- Steps:
  1. In `src/widgets/FlexBoxWidget.zig`, add an optional path that:
     - Builds a Yoga node for the container and one per child during `rectFor`/`minSizeForChild`.
     - Applies current `InitOptions` to Yoga (`direction` → `setFlexDirection`, `justify_content` → `setJustifyContent`, `align_items` → `setAlignItems`, `align_content` → `setAlignContent`).
     - Feeds child `min_size` into Yoga via `setMeasureFunc` on child nodes that lack their own Yoga info; otherwise use provided sizes.
     - Calls `calculateLayout` once per frame with container size (use min-size fallback when zero like today).
  2. In `rectFor`, if Yoga is enabled, return the Yoga-computed child rects instead of manual flex math; keep the current logic as fallback.
  3. In `minSizeForChild`, when Yoga is enabled, update the Yoga child’s measured size and let Yoga determine row/column placement (no spacer math).
  4. Keep background drawing and DVUI registration the same; only the placement math is swapped.
  5. Put this behind a debug flag/env to compare layouts; log diffs to validate.
- This POC proves Yoga interop without touching `solid_renderer` yet; once stable, the same pattern can be used for Solid elements.

### Staging

1. Build Yoga tree and log/overlay rects (no render changes).
2. Enable Yoga rects for simple tags (`div`, `p`, `h1-3`) behind a flag.
3. Migrate buttons/inputs/images and remove spacer gaps.
4. Make Yoga the default; keep DVUI layout as fallback if Yoga disabled.

### Build wiring

- Add `zig-yoga` dependency in `build.zig` (ensure headers path).
- Introduce `src/layout/yoga_builder.zig` owning Yoga nodes and the Tailwind adapter.

### Touch points

- `src/solid_renderer.zig`: respect `node.layout`, bypass DVUI flex/box sizing, stop inserting gap spacers.
- `src/widgets/TextLayoutWidget.zig`: factor out measurement helper; honor fixed rect.
- `deps/zig-yoga`: used via the adapter; no upstream changes expected.
