# High: Stale Native State When Dynamic Object Props Resolve to `nil`

## Severity

- High
- Category: Architecture correctness and declarative behavior

## Summary

Dynamic object props (`visual`, `transform`, `scroll`, `anchor`, `image`) can resolve to `nil` in Luau, but the Zig patch bridge treats `nil` as “skip” rather than “clear”. This leaves previous native state active, producing stale UI behavior that contradicts declarative expectations.

## Status (Current)

- `src/native_renderer/luau_ui.zig` implements explicit clear behavior for object props: when a prop key appears in a patch with `nil`, the bridge calls `clearTransform/clearVisual/clearScroll/clearAnchor/clearImage`.
- This document is kept as a record of the hazard and the desired contract; verify any future changes preserve the clear semantics.

## Why this matters

For a declarative reactive API, the rendered state should match current reactive values. If a reactive prop becomes `nil`, developers expect the previous override to disappear. Current behavior keeps old values alive.

This causes hard-to-debug mismatches where UI appears “stuck” even though reactive source state changed.

## Primary code locations

- `deps/solidluau/src/ui/renderer.luau:492` (dynamic patch arg assembly)
- `deps/solidluau/src/ui/renderer.luau:500` to `deps/solidluau/src/ui/renderer.luau:535` (object props pushed into patch call)
- `deps/solidluau/src/ui/renderer.luau:538` (`ui.patch(...)`)
- `src/native_renderer/luau_ui.zig:217` (`Transform`: `nil` branch `continue`)
- `src/native_renderer/luau_ui.zig:226` (`Visual`: `nil` branch `continue`)
- `src/native_renderer/luau_ui.zig:235` (`Scroll`: `nil` branch `continue`)
- `src/native_renderer/luau_ui.zig:244` (`Anchor`: `nil` branch `continue`)
- `src/native_renderer/luau_ui.zig:253` (`Image`: `nil` branch `continue`)
- `src/native_renderer/luau_ui.zig:348`, `src/native_renderer/luau_ui.zig:406`, `src/native_renderer/luau_ui.zig:463`, `src/native_renderer/luau_ui.zig:508` (setters update only present fields)

## Example failure mode

```luau
hydrate(node){
  visual = function()
    if hovered() then
      return { opacity = 0.5 }
    end
    return nil
  end,
}
```

When `hovered()` flips from `true` to `false`, `visual` resolves to `nil`. The bridge skips update, so opacity remains `0.5` instead of clearing.

## Root cause

The patch protocol currently has no explicit clear semantics for object-valued props:

- Lua side includes property key in patch even when value is `nil`.
- Zig side interprets `nil` as no-op.
- Setters are additive and field-selective, so previous values persist.

## Resolution strategy

Define and implement explicit clear behavior.

Recommended contract:

- If a prop key appears in a patch with `nil`, clear that prop bucket to defaults.
- If a prop key appears with a table, apply partial updates as today.
- If a prop key is omitted, leave current state unchanged.

## Implementation checklist

1. In `src/native_renderer/luau_ui.zig`, update `applyPatch` `nil` branches for object props to call clear/reset functions instead of `continue`.
2. Add clear/reset methods in `NodeStore`/`SolidNode` for:
   - `visual`
   - `transform`
   - `scroll`
   - `anchor`
   - `image`
3. Define default reset values explicitly and document them.
4. Keep scalar props (`text`, `class`, `src`) behavior unchanged unless intentionally redesigned.
5. Add smoke coverage for reactive toggling from table → `nil` and verify state actually resets.

## Acceptance criteria

- Table → `nil` transitions clear prior overrides.
- Omitted key does not clear existing state.
- Partial table patches still work.
- Reactive UI no longer exhibits stale visual/transform/anchor/image/scroll state.

## Suggested tests

- Add a Luau smoke case with each object prop toggling between table and `nil`.
- Verify output through retained node state inspection or behavior-level assertions.
- Re-run:
  - `zigwin build luau-smoke --summary failures`
  - `./zig_build_simple.sh`

## Risks and migration notes

- This may change behavior for code that relied on `nil` as no-op.
- If backward compatibility is required, introduce a temporary feature flag or explicit clear sentinel.
- Document final contract in `docs/RETAINED_API.md` once implemented.
