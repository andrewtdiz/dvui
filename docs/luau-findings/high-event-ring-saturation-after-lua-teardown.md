# High: Event Ring Saturation After Lua Teardown

## Severity

- High
- Category: Runtime performance and fault containment

## Summary

If Lua tears down during frame processing, retained rendering continues to enqueue UI events, but event draining stops because it is gated behind `lua_ready`. The event ring fills, starts dropping events, and emits repeated warning logs.

After this point, the app can remain in a degraded steady state for the rest of the process lifetime.

## Why this matters

The retained renderer and reactive runtime are tightly coupled for interaction. When one side fails, the current behavior keeps generating work that has no consumer:

- unnecessary per-frame event push attempts
- warning log spam on full ring
- persistent dropped-event counters

This is high severity because it turns one Lua fault into an ongoing performance issue.

## Primary code locations

- `src/native_renderer/window.zig:262` (drain events only when `renderer.lua_ready`)
- `src/native_renderer/window.zig:272` (Lua `update` only when `renderer.lua_ready`)
- `src/native_renderer/window.zig:351` (`retained.render(...)` always called with event ring pointer)
- `src/native_renderer/window.zig:184` and `src/native_renderer/window.zig:332` (Lua error paths call `teardownLua`)
- `src/native_renderer/lifecycle.zig:946` (`teardownLua`)
- `src/retained/events/mod.zig:101` (`EventRing.push`)
- `src/retained/events/mod.zig:105` (ring full warning log)

## Current frame behavior

Normal path:

1. Drain retained events into Lua handlers (`on_event`).
2. Run Lua `update`.
3. Render retained tree, which may enqueue new events for next frame.

Failure path:

1. Lua call fails.
2. `teardownLua` sets `lua_ready = false` and destroys Lua state.
3. Later frames skip drain/update due to `lua_ready` guards.
4. Retained render still receives ring pointer and continues pushing events.
5. Ring reaches capacity and repeatedly logs full-buffer warnings.

## Observable impact

- Event processing cost remains non-zero despite no Lua consumer.
- Log output can grow significantly under active input.
- Interaction event telemetry becomes noisy (`dropped_events`, `dropped_details`).

## Reproduction approach

1. Introduce a deliberate runtime error in `on_event` or `update` in `luau/index.luau`.
2. Run the native renderer.
3. Trigger pointer/input events continuously.
4. Confirm:
   - Lua is torn down.
   - retained frame loop keeps running.
   - ring full warnings appear repeatedly.

## Resolution options

### Option A (recommended): disable event production when Lua is unavailable

In `renderFrame`, pass `null` for `event_ring` when `lua_ready` is false.

Benefits:

- Stops unnecessary event generation at source.
- No ring saturation or warning spam.
- Minimal change in hot path.

### Option B: keep rendering with ring but actively drain/discard

When `lua_ready` is false, advance read head to write head each frame.

Benefits:

- Prevents long-term backlog.

Limitations:

- Still pays event push cost every frame.
- Still mixes production with guaranteed discard.

### Option C: auto-reinitialize Lua after teardown

This can be useful, but it is larger in scope and should be a separate reliability feature, not the first fix for saturation.

## Implementation checklist

1. In `src/native_renderer/window.zig`, gate `retained.render` event ring argument by Lua availability.
2. Keep rendering UI even if Lua is down.
3. Ensure no code path logs ring full when Lua has been torn down.
4. Add an integration smoke case that forces Lua teardown and verifies no ring growth/log spam behavior.

## Acceptance criteria

- After Lua teardown, event ring does not grow.
- No repeated `EventRing full` warnings in steady state.
- Rendering continues without Lua.
- Existing successful Lua path behavior is unchanged.

## Validation commands

- `zigwin build luau-smoke --summary failures`
- `./zig_build_simple.sh`

## Risks and notes

- Ensure this change does not suppress events while Lua is healthy.
- Keep error reporting for the initial Lua failure intact.
- If auto-restart is added later, re-enable event ring only after Lua is fully ready.
