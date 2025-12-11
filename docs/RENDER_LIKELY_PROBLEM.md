# Likely Root Cause of “Button Starts Outside Parent Until Resize”

## Observed Symptom
- The Solid-rendered `button` draws at an incorrect position on the first stable run.
- The position only becomes correct after a window resize (which forces a full layout invalidation).
- Caption rendering is now correct; the remaining bug is positional.

## Key Architectural Facts (from `SOLID_ARCHITECTURE.md`)
- **Non‑interactive elements are always drawn directly** (no DVUI widgets created for them).
- **Interactive elements use DVUI widgets** to preserve focus/input.
- Layout rects in `NodeStore` are **absolute window coordinates** (computed in `src/integrations/solid/layout/`).

## What the Code Currently Does

### 1. Layout produces absolute rects
`src/integrations/solid/layout/mod.zig` and `flex.zig` compute `node.layout.rect` in screen space:
- Parent passes an absolute `child_rect` to children.
- Flex layout sets child `x/y` as absolute positions within the window.

### 2. Non‑interactive parents never create a DVUI coordinate scope
`src/integrations/solid/render/mod.zig`:
- `div`, `p`, `h*`, etc. that are not interactive go through `renderNonInteractiveDirect`.
- That path **draws backgrounds/text directly** and **does not call `dvui.box` or any widget**.
- So for most trees, **there is no DVUI parent stack matching the Solid DOM hierarchy**.

### 3. `renderButton` converts absolute → parent‑relative anyway
`src/integrations/solid/render/mod.zig` (`renderButton`):
- Builds `options.rect` from `node.layout.rect` (absolute).
- Then **subtracts `parent.layout.rect.x/y`**:
  ```zig
  options.rect.?.x -= parent_rect.x;
  options.rect.?.y -= parent_rect.y;
  ```
- This assumes DVUI is currently inside a widget representing the parent.

### 4. Other interactive widgets *don’t* do this
`src/integrations/solid/render/mod.zig` (`renderInput`):
- Uses `applyTransformToOptions`, which sets `options.rect` from `node.layout.rect` **without parent subtraction**.
- I.e. inputs are rendered in absolute coordinates.

## Likely Problem

**Coordinate‑space mismatch for interactive nodes.**

Because non‑interactive ancestors are rendered directly, DVUI is usually operating at the **window/root coordinate space** when a `button` is created. In that context:
- DVUI expects `options.rect` to be **absolute window coordinates**.
- `renderButton` instead feeds **parent‑relative coordinates**, by subtracting the parent’s absolute rect.

Result:
- The button is offset by `‑parent_rect.x/y`, so it appears shifted toward the top‑left (often “outside” its parent).
- A resize forces a full layout invalidation; depending on the tree, this can incidentally change parent offsets or rebuild DVUI state so the error becomes hidden, but the underlying space mismatch remains.

The inconsistency between `renderButton` and `renderInput` strongly suggests the button path is the odd one out for the current architecture.

## Secondary Issue to Watch

If/when you *do* introduce DVUI boxes for non‑interactive containers to build a real widget hierarchy:
- Layout already places children in the **parent’s padded content rect**.
- Tailwind `padding` is also applied to DVUI options.
- Subtracting the parent’s *outer* rect (not content origin) would double‑apply padding.  
So any future “relative” conversion should subtract **parent content origin** (`parent_rect + padding`), not raw `parent_rect`.

## How to Confirm Quickly

1. Use the existing debug log in `renderButton`:
   - If you see `parent_rect` non‑zero and `options_rect` near `(0,0)` while `rect_opt` is far from `(0,0)`, that’s the mismatch.
2. Temporarily remove the parent subtraction in `renderButton` (or gate it behind a “parent has DVUI scope” check):
   - If the button is correct on first paint without needing resize, this is confirmed.

## Direction for Fix (not implemented here)
- **Short term:** Make `renderButton` behave like `renderInput` (use absolute rects unless you are inside a DVUI parent scope).
- **Long term:** Either
  - Create DVUI “scope” boxes for all containers (even if backgrounds are still drawn directly), **then** use parent‑relative rects consistently, or
  - Keep the mixed direct/DVUI renderer but treat all DVUI widgets as absolute‑positioned.

