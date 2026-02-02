• Entry Points / Call Flow (Zig → Luau → retained)

  - src/native_renderer/lifecycle.zig loads luau/ui_features_decl.luau, installs dvui_dofile and a Zig-provided global require(), calls global init() once, then marks lua_ready.
  - Each frame in src/native_renderer/window.zig:
      - Drain retained events → Luau (drainLuaEvents() calls on_event(kind_int, id, payload_bytes)) before Luau update().
      - Call Luau update(dt, input_table) (if present).
      - Render retained tree: retained.render(event_ring, store, true).

  Luau “Declarative UI” Rendering Model

  - luau/ui_features_decl.luau is a tiny entrypoint:
      - Loads SolidLuau via require("solidluau") (modules embedded in Zig).
      - Installs the compat adapter: SolidLuau.ui.adapters.compat_ui(ui).
      - init(): SolidLuau.ui.init(App)
      - update(dt): SolidLuau.animation.step(dt)
      - on_event(kind,id,payload): SolidLuau.ui.dispatch_event(kind,id,payload)
  - SolidLuau is responsible for:
      - Reactive graph + scheduling (core/reactivity/*)
      - DSL (ui/dsl) and renderer (ui/renderer) that issues ui.* mutations
      - Control-flow nodes (For, Show) and event handler wiring via ui.listen_kind + dispatch_event

  Zig Binding Layer (Luau ui.* → retained.NodeStore)

  - src/native_renderer/luau_ui.zig registers the global ui table, with methods mapping almost 1:1 to retained.NodeStore operations.
  - Structural ops:
      - ui.create(...) → NodeStore.setTextNode / NodeStore.upsertSlot / NodeStore.upsertElement, then NodeStore.insert(parent, id, before).
      - ui.insert(...) → NodeStore.insert(parent, id, before) (detach + reattach).
      - ui.remove(id) → NodeStore.remove(id) (recursive delete).
  - State updates mark dirty:
      - Layout-affecting: set_class, set_text, set_scroll, set_anchor, set_src (currently treated as layout-affecting), and any structural ops call NodeStore.markNodeChanged().
      - Paint-only: set_transform, set_image tint/opacity paths call NodeStore.markNodePaintChanged().

  retained/ Data Model

  - src/retained/core/node_store.zig is the core model:
      - NodeStore: AutoHashMap(u32, SolidNode) + a global monotonic versions counter.
      - SolidNode fields you hit from Luau:
          - Tree: parent:?u32, children:ArrayList(u32)
          - Identity: id, kind (root|element|text|slot), tag (element only)
          - Content: text, class_name, image_src
          - Styling:
              - class_spec (tailwind parse cache per-node)
              - visual_props (intended “explicit” style inputs) and visual (derived/effective each render)
              - transform (scale/rotation/translation/anchor)
              - scroll (enabled, offsets, canvas, computed content size)
              - Anchoring: anchor_id/side/align/offset
          - Caches:
              - layout: LayoutCache (rects + intrinsic/text caches)
              - paint: PaintCache (cached vertices/indices, painted bounds)
          - Interaction bookkeeping: listener_mask, interactive_self, total_interactive, hovered, focus/roving/modal flags, etc.

  retained/ Layout: Calculations & Flow

  - Frame entry: retained.render() calls retained.updateLayouts() (src/retained/render/mod.zig → src/retained/layout/mod.zig:updateLayouts()).
  - Dirty detection:
      - Screen size or natural scale change invalidates the entire layout subtree (invalidateLayoutSubtree()).
      - Otherwise, layout recompute is driven by SolidNode.layout_subtree_version vs layout.version, plus “missing layout” and “active layout animations”.
  - Core layout primitive: computeNodeLayout(store, node, parent_rect) (src/retained/layout/mod.zig):
      - Uses tailwind spec (node.prepareClassSpec() + hover application) as the layout contract.
      - Maintains a layout scaling chain: node.layout.layout_scale = parent_layout_scale * (spec.scale orelse 1.0).
      - Computes node.layout.rect in physical/pixel space:
          - Absolute positioning: honors left/right/top/bottom, explicit w/h, plus layout_anchor (e.g. “anchor-center” behaves like positioning by an anchor fraction of the node rect).
          - In-flow positioning: applies margin → sets rect; then later padding+border → sets child_rect.
          - Intrinsic sizing:
              - text nodes: measureTextCached() (font pulled from the parent spec).
              - other nodes: measureNodeSize() which can sum children sizes (including flex direction + gap), and special-case “combined text” measurement for p/h1/h2/h3.
      - Scroll:
          - Layout pass shifts the coordinate space for children by scroll.offset_x/y and expands the “layout rect” to the canvas/content size when allowed.
          - Post-pass computes scroll.content_width/height, optionally via auto-canvas bounds scanning.
      - Flex layout:
          - spec.is_flex → layout/flex.zig:layoutFlexChildren() measures each child (skipping hidden, absolute, and “empty anchor text”), then places them along the main axis with gap + justify/
            align rules.
          - Absolute children of a flex container are laid out afterwards relative to the container’s area.
      - Anchored placement (second pass):
          - After the full tree layout, applyAnchoredPlacement() offsets any node with anchor_id using dvui.placeAnchoredOnScreen(...) and applies the delta to the whole subtree
            (offsetLayoutSubtree()).

  retained/ Rendering: State & Flow

  - src/retained/render/mod.zig:render() orchestrates:
      - Focus begin/end (retained/events/focus.zig), drag-drop, overlay/portal discovery.
      - Pointer picking + hover path maintenance; hover can invalidate layout when hover variants affect margin/padding (tailwind.hasHoverLayout()).
      - Paint caching: if layout changed or NodeStore.currentVersion() advanced, render/cache.zig:updatePaintCache() walks the tree and regenerates cached geometry for nodes that need it.
      - Final draw: ordered child rendering + overlay subwindow rendering, using render/internal/renderers.zig.
  - Effective styling application happens per render via render/internal/derive.zig:apply():
      - Starts from node.visual_props, derives node.visual, then applies class-spec and hover, and forces clip_children when scrolling.


What made it difficult in this codebase
  
- Two render pipelines: DVUI widgets vs direct draw, with different coordinate handling and partial overlap in responsibilities.
- Multiple coordinate spaces (layout rect, context rect, painted_rect) without a single enforced contract.
- Paint cache lives in a different module and is computed in layout space, so it’s easy to misuse as screen‑space.
- Paragraphs special‑case text rendering (combined text, custom wrapping) and bypass normal widget alignment logic.

How to improve significantly

Here’s the same guidance with file references and no debug overlay suggestion:

- Unify render‑space contract: document and enforce “all draw code consumes context‑space rects” in src/retained/render/internal/state.zig and update callers in src/retained/render/internal/renderers.zig and src/retained/render/cache.zig.
- Reduce dual pipelines: consolidate text rendering so h1/p go through one path (either DVUI or direct) by refactoring src/retained/render/internal/renderers.zig and src/retained/render/direct.zig.
- Tighten paint‑cache usage: limit painted_rect to cache/dirty logic only, and avoid using it for placement decisions in src/retained/render/cache.zig and src/retained/render/internal/renderers.zig.
- Add a render regression: a small test scene covering scale + h1/p in a container, referenced in luau/app.luau (or a dedicated sample scene file if you prefer).
- Write invariants: add a brief “text rendering invariants” section in ARCHITECTURE.md explaining layout rect vs context rect vs painted rect, and which modules may use each.
