# Animation (Decl Runtime)

This runtime exposes time-based reactive helpers via `scripts/ui_features_decl/animation.luau`.

## Frame stepping

`animation.step(dt)` must be called every frame. The single-file entrypoint `scripts/ui_features_decl.luau` calls it from `update(dt, input)`.

## easing

`animation.easing` is a table of easing functions ported from `src/layout/easing.zig`.

## spring

`spring(sourceFn, period?, dampingRatio?) -> (value: Source<T>, config)`

- `T` is `number` or `{number}`.
- `spring(...)` must be called inside a reactive root scope.
- `value()` reads the animated value.
- `value(v)` sets the current position and resets velocity.

`config({ position?, velocity?, impulse? })` updates spring state and schedules stepping.

## tween

`tween(sourceFn, duration, easingFn?) -> (value: Source<T>, config)`

- `T` is `number` or `{number}`.
- `tween(...)` must be called inside a reactive root scope.
- `value()` reads the animated value.
- `value(v)` snaps to `v` and cancels the tween.

`config({ position?, duration?, easing? })` updates tween settings.

## Example

```luau
local anim = require("scripts/ui_features_decl/animation")
local reactivity = require("scripts/ui_features_decl/reactivity")

local source = reactivity.source

local target = source({ 0, 0 })
local pos = anim.spring(target, 0.6, 1)

local function onHover()
  target({ 10, 0 })
end

local function readX()
  return pos()[1]
end
```
