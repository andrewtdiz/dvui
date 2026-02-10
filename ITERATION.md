Core idea: use artifacts/*.layout.json as the primary, deterministic gate for layout correctness (positions/sizes/flow), and use artifacts/screenshot-*.png as the secondary gate for things the dump can’t prove (borders/rounding/clip, text rendering, z-order).

Workflow

1. Add one scene per layout feature cluster (simple, intermediate, advanced) to tools/layoutdump_scenes.json.
2. In each scene, give every important node a stable identity via `key = "..."` so `ui-path-*` and `keyPath` are stable across tree edits.
3. Run layout verification:

    ./zig-out/bin/luau-layout-dump.exe --list-scenes
    ./zig-out/bin/luau-layout-dump.exe <scene>
    This writes artifacts/<scene>.layout.json and compares to snapshots/<scene>.layout.json (nonzero exit + diff summary on mismatch).
4. Run visual verification when needed:
    - zigwin build luau-screenshot (writes artifacts/screenshot-N.png; you can correlate with artifacts/<scene>.layout.json by keyPath/class).

What to assert in artifacts/*.layout.json

- Always assert by keyPath (not numeric id).
- Geometry is in pixel space (meta.pixelWidth/meta.pixelHeight), so compare rects against those, not meta.width/meta.height.
- For each node you care about:
    - rect matches expected [x,y,w,h] (within the dump precision, see meta.decimals).
    - childRect shrinks correctly for padding + border (inner content box contract).
    - Containment: children are within parent childRect unless the child is absolute.
    - Sanity: w >= 0, h >= 0, finite numbers, no missing rect for visible nodes.

Coverage tiers (scenes to build)

- Simple (exact numbers, minimal nesting)
    - Absolute positioning + insets: absolute, left-*/top-*/right-*/bottom-*, bracket values (left-[12]) and percent (left-[50%]).
    - Layout anchors: anchor-* tokens (verify anchor math by checking rect origin changes with constant w/h).
    - Sizing: w-*, h-*, w-full, h-full, w-screen, h-screen.
    - Basic typography layout: p with text-left|center|right, text-nowrap, break-words (dump checks rect; screenshot checks wrapping visuals).
- Intermediate (nesting + mixed rules)
    - Flex layouts: flex, flex-row|flex-col, gap-*, justify-*, items-* with 3–6 children (assert relative order and spacing).
    - Margin/padding interactions: m-* + p-* on containers and children (assert rect placement + childRect shrink).
    - Borders/rounding: border-*, rounded-* (dump confirms geometry; screenshot confirms border width/color and rounding).
    - Clipping: overflow-hidden container with a child that extends past bounds (dump confirms sizes; screenshot confirms clip behavior).
- Advanced (multi-pass behavior, transforms, layering)
    - Mixed in-flow + absolute inside flex (assert that absolute children don’t affect flex sizing/placement).
    - Scale semantics:
        - Tailwind scale-* is layout scale (should change rect sizes in the dump).
        - transform.scale* is render-only (should not change layout rects; screenshot should change visuals).
    - Z-index + opacity overlays: z-*, opacity-* (screenshot-driven; dump is mainly for ensuring nodes exist and geometry is correct).
    - Hover variants that affect layout: hover:m-*, hover:p-*
        - Needs deterministic input injection (pointer over/out) so you can capture two dumps and assert the rect delta when hovered, and stability when not.

“Parsed but not wired” checks (keep honest)

- overflow-scroll/overflow-x-scroll/overflow-y-scroll and Luau scroll props are accepted but not currently applied.
- Luau anchor props are accepted but not currently applied.
  Create a small scene that sets these and assert “no crash, no unexpected geometry changes” so the runtime behavior stays aligned with the docs until those features are implemented.
