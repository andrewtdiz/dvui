# High: Opaque Binary Event Payloads at Luau Handler Boundary

## Severity

- High
- Category: API architecture and developer ergonomics

## Summary

Pointer/drag payloads are pushed from Zig as packed binary bytes and forwarded into Luau handlers unchanged. The public handler API therefore exposes low-level transport encoding details instead of structured event objects.

This is a high-severity API design issue for a declarative reactive UI layer because it leaks ABI details into application code.

## Why this matters

The project goal is a clear, concise declarative reactive API. Raw binary payloads create the opposite experience:

- handlers must know byte layouts and decode manually
- event contract is tied to struct packing/endianness assumptions
- payload shape is inconsistent across event kinds

This blocks productive onboarding for contributors unfamiliar with low-level bridge details.

## Primary code locations

- `src/retained/render/internal/renderers.zig:92` and `src/retained/render/internal/renderers.zig:100` (pointer payload bytes)
- `src/retained/events/drag_drop.zig:164` and `src/retained/events/drag_drop.zig:172` (drag/pointer payload bytes)
- `src/native_renderer/window.zig:182` (Lua callback receives `detail` bytes directly)
- `luau/index.luau:15` and `luau/index.luau:16` (payload forwarded directly to SolidLuau)
- `deps/solidluau/src/ui/renderer.luau:1063` (handler called with raw payload)
- `docs/RETAINED_API.md:230` and `docs/RETAINED_API.md:233` (documents raw-byte contract)

## Current payload shapes

- `input` / `enter`: UTF-8 string
- `click` / `focus` / `blur` / hover events: empty string
- `pointer*` and drag events: raw bytes of packed structs

This mixed contract forces each handler author to special-case parsing by event kind.

## Root cause

Bridge code currently treats event detail as an opaque `[]const u8` and does not decode it into typed Lua values before invoking `on_event`.

## Resolution strategy

Move transport decoding into Zig bridge and expose structured Lua payloads.

Recommended target contract:

- `pointerdown`/`pointermove`/`pointerup`/drag events:
  - `{ x: number, y: number, button: number, modifiers: { shift: boolean, ctrl: boolean, alt: boolean, cmd: boolean } }`
- `scroll`:
  - `{ x: number, y: number, viewportW: number, viewportH: number, contentW: number, contentH: number }`
- text events:
  - `{ value: string }` or plain string, but choose one and standardize
- no-data events:
  - `nil` or `{}` consistently

## Implementation checklist

1. In `src/native_renderer/window.zig` `drainLuaEvents`, decode `entry.kind` payloads before Lua call.
2. Add helper decode functions for `PointerPayload` and `ScrollPayload`.
3. Pass typed Lua tables to `on_event` instead of raw byte slices.
4. Update `docs/RETAINED_API.md` to reflect structured payload contract.
5. Add smoke coverage for pointer and input event handler payload shapes.

## Backward compatibility plan

If existing user code depends on raw bytes, stage migration:

1. Temporary dual payload support:
   - structured payload as main argument
   - raw bytes under `payload.__raw` for transition
2. Deprecate raw-byte usage in docs
3. Remove raw fallback in a follow-up release

## Acceptance criteria

- Application handlers can consume pointer/drag/scroll data without manual byte decoding.
- Event payload shape is documented and consistent.
- Cross-platform payload behavior does not rely on host ABI details.
- `luau-smoke` and native build remain green.

## Validation commands

- `zigwin build luau-smoke --summary failures`
- `./zig_build_simple.sh`

## Risks and notes

- This is a user-facing API change; coordinate migration messaging.
- Keep decoding cost minimal in frame hot paths.
- Prefer a single canonical payload shape per event kind to avoid long-term ambiguity.
