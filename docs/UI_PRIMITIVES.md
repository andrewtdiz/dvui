Rendering Primitives

- sprite (atlas sub-rect, flip, tint/opacity, rotate, optional 9-slice + tiling)
- panel / nine_slice (windows, frames, dialog boxes that scale cleanly)
- text upgrades (outline + drop shadow, alignment, truncation/ellipsis)
- shape primitives (rect/line/circle) for cheap bars, dividers, highlights

Layout / Composition

- stack (v/h) and grid (inventory, loadout, settings lists)
- safe_area + consistent UI scaling (resolution independence, pixel-snapping rules)
- scroll_view (useful for inventories/settings; can stay minimal)

Interaction / State

- button plus explicit disabled + selected state styling
- toggle (checkbox/radio as variants)
- list/grid selection model (focus, roving selection, gamepad/D-pad navigation)
- slider and input (already good for settings/chat/console)

Game-Centric Widgets

- progress_bar and radial_progress (health, stamina, cooldowns)
- render_texture / viewport (minimap, character portrait, camera feed)