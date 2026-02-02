# Embedding SolidLuau in a Zig Host (Luau VM)

This is a high-level guide for integrating SolidLuau into any Zig codebase that embeds a Luau VM. The core idea is: ship SolidLuau’s Luau sources with your binary, install a deterministic `require()` loader, and provide a small host-side UI adapter + event/tick bridge.

## Minimal Touch Points

1) Vendored SolidLuau sources (Luau files)
- Keep SolidLuau as plain `.luau` sources in your repo (any folder layout you want).

2) Embedded module registry (compile-time)
- Create one Zig file that maps module IDs (`require("...")` strings) to embedded source text via `@embedFile`.
- The module IDs must cover:
  - your public entrypoint (`solidluau` or `SolidLuau`)
  - every internal module that SolidLuau `require()`s (`core/reactivity`, `ui/index`, `animation/index`, etc.)
- Aliases are fine if you want to support multiple names for the same module.

3) Host-installed `require()` (runtime)
- Override Luau’s `require()` to load from your embedded registry, with caching.
- Optional: keep a filesystem fallback for app scripts so you can iterate without recompiling.

4) UI adapter exposed to Luau
- Provide a global table (often `ui`) whose functions mutate your retained UI tree / scene graph.
- SolidLuau’s compat adapter calls into this table.

5) Frame tick + event delivery
- Each frame: call into Luau to step animation and let SolidLuau handle input/events.

## Integration Steps

### 1) Build the embedded module registry
Create something like:
- `pub const modules = [_]struct { id: []const u8, source: []const u8 }{ ... }`
- `pub fn get(id: []const u8) ?[]const u8 { ... }`

The important contract:
- `id` matches what Luau calls `require("id")`
- `source` is the full Luau source text for that module

### 2) Install a deterministic `require()`
Implement `require(id)` with this behavior:
1. If `cache[id]` exists, return it.
2. If `embedded.get(id)` exists:
   - compile source to bytecode
   - execute the chunk
   - cache and return the module result (or `true` if it returns `nil`)
3. Otherwise (optional) load `<id>.luau` from disk, compile, execute, cache, return.
4. If nothing matches, raise a Luau error with a clear “module not found” message.

### 3) Provide the host UI adapter surface
Expose a global table that covers the adapter’s needs:
- structural: `create`, `insert`, `remove`, `reset`
- content/state: `set_text`, `set_class`, `set_image`/`set_src`, `set_transform`, `set_visual`, `set_scroll`, `set_anchor`
- events: `listen_kind`
- constants: `EventKind` enum mapping (strings → integers)

Back these functions with your engine’s retained tree operations (node create, reparent, delete, property updates, dirty marking).

### 4) Boot SolidLuau from a small Luau entry file
Have one app-level Luau script that:
- `local SolidLuau = require("solidluau")`
- `SolidLuau.ui.setAdapter(SolidLuau.ui.adapters.compat_ui(ui))`
- defines:
  - `init()` → `SolidLuau.ui.init(App)`
  - `update(dt, input)` → `SolidLuau.animation.step(dt)`
  - `on_event(kind, id, payload)` → `SolidLuau.ui.dispatch_event(kind, id, payload)`

### 5) Drive it from your render loop
Per frame (host-side):
- drain native events and call Luau `on_event(...)` if present
- call Luau `update(dt, input_table)` if present
- render your retained UI tree

## Development Workflow Options

- Fully embedded (single-binary):
  - embed SolidLuau + your app scripts
  - deterministic, no external files required

- Embedded library + disk app scripts:
  - embed SolidLuau modules
  - allow filesystem fallback only for your app scripts
  - iterate quickly without recompiling

## Common Failure Modes

- “module not found” for an internal SolidLuau `require()`:
  - your embedded registry is missing that module ID
  - fix by adding the missing ID → source mapping

- `require()` caches the wrong thing:
  - ensure you cache the module return value (or `true` when the module returns `nil`)
  - ensure each module executes exactly once
