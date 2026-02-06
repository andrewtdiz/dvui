# Layout/Tree Dump: Agentic UI Verification Contract

## Goal

Enable an LLM (Codex) to iteratively implement UI elements and verify rendering and layout with a deterministic, machine-checkable artifact.

The core artifact is a **layout/tree dump**: a canonical JSON representation of the retained UI tree after layout has been computed.

## Why A Layout/Tree Dump (Not Just Screenshots)

Screenshots are useful for visual review but brittle for automation (fonts, GPU differences, anti-aliasing, timing).

A layout/tree dump is:

- Deterministic and diff-friendly (when canonicalized).
- Cheap to compute and easy to assert on.
- Expressive enough to validate layout invariants: size, position, alignment, overflow, hierarchy.

## What “Dump” Means In This Repo

DVUI’s Luau UI pipeline builds a `retained.NodeStore`, then `retained.render(...)` computes layout and paints.

The dump should be captured **after layout is available**:

- Source of truth for geometry: `SolidNode.layout.rect` and `SolidNode.layout.child_rect`.
- Node data is stored in `retained.NodeStore.nodes` (`std.AutoHashMap(u32, SolidNode)`).

The dump is not a “widget call log” and not “draw commands”. It is the computed tree state that drives rendering.

## Verifiable Deliverable (The Contract)

Deliver one command that:

1. Runs the app (or scene) deterministically.
2. Produces a canonical `layout.json`.
3. Exits `0` if it matches a checked-in baseline, otherwise exits nonzero and prints a minimal diff summary.

Example contract:

```bash
./zig-out/bin/luau-layout-dump.exe \
  --lua-entry luau/index.luau \
  --width 1280 --height 720 \
  --frames 2 --dt 0 \
  --out artifacts/app.layout.json \
  --baseline snapshots/app.layout.json
```

Success criteria:

- The command is stable across runs on the same machine.
- The JSON is stable across trivial changes (ordering, float noise) due to canonicalization.
- Failures are actionable: diff output points to which node and which field changed.

This is the minimum needed to run Codex in a loop:

- Codex edits UI code/spec.
- The runner produces `layout.json`.
- The verifier compares to baseline and reports failures.
- Codex uses failures to adjust layout/rendering until the check passes.

## Dump Schema (v1)

Write a single JSON object:

- `meta`: run context for debugging and replay.
- `nodes`: a list of nodes, sorted by stable key (see Identity).

Recommended v1:

```json
{
  "meta": {
    "scene": "luau/index.luau",
    "width": 1280,
    "height": 720,
    "pixelWidth": 1280,
    "pixelHeight": 720,
    "frame": 2,
    "dt": 0.0
  },
  "nodes": [
    {
      "id": 0,
      "parent": null,
      "kind": "root",
      "tag": "",
      "class": "",
      "keyPath": "root",
      "rect": [0, 0, 1280, 720],
      "childRect": [0, 0, 1280, 720]
    }
  ]
}
```

Field guidance:

- `rect` uses `[x,y,w,h]` from `SolidNode.layout.rect` (rounded).
- `childRect` uses `[x,y,w,h]` from `SolidNode.layout.child_rect` (rounded) when present, otherwise null.
- `class` is the stored class string (`SolidNode.class_name`).
- `tag` is empty for non-element kinds.
- Prefer small strings over deeply nested objects for diff readability.

## Canonicalization Rules (Required)

Without canonicalization, the dump will be noisy and not suitable for automation.

1. Stable ordering
   - `std.AutoHashMap` iteration order is not stable.
   - Sort `nodes` before writing.

2. Float rounding
   - Round layout floats to a fixed precision (example: 0.01) before writing.
   - Do not emit full-precision floats.

3. Optional field suppression
   - If `rect` is null, emit `"rect": null` (not missing key) to keep schema stable.
   - If `tag` is empty, keep it empty (don’t omit) so diffs stay uniform.

4. Text handling
   - Text diffs are useful, but long strings can make diffs unreadable.
   - Emit either `text` truncated to N chars or `textHash` (or both).

## Stable Identity (The Hard Part)

SolidLuau assigns numeric ids sequentially during mount. Adding a node can renumber many later nodes, making diffs unhelpful.

The dump must include a stable identity field used for sorting and diff alignment.

Recommended identity: `keyPath`

- If UI originates from JSON wrappers, a key-path is naturally stable (example: `root.card.button`).
- Use it as the primary sort key and as the diff “join key”.

Practical way to carry `keyPath` through the pipeline without modifying dependencies:

- Append an ignored token to `class`, for example `__key=root.card.button`.
- Tailwind parsing ignores unknown tokens, so it won’t affect layout.
- The Zig dumper extracts `__key=` from `SolidNode.class_name` and emits it as `keyPath`.

Fallback if no stable key exists:

- Emit `path` derived from hierarchy: `div[0]/div[1]/p[0]`.
- Expect diffs to be noisy when sibling order changes.

## Minimal Assertions The Verifier Should Support

Even before golden baselines, the verifier can validate invariants:

- No missing layout: every visible node must have `rect`.
- Rect sanity: `w >= 0`, `h >= 0`, finite floats.
- Containment: child `rect` should be within parent `childRect` unless `absolute`.
- Key coverage: required nodes exist by `keyPath`.

These are “first line” checks that make failures more specific than a baseline diff.

## Codex Loop: How This Enables Agentic UI Development

The loop is simple and fully verifiable:

1. Input: a UI spec change (Luau code or JSON UI tree).
2. Execute: run the deterministic layout dump command.
3. Observe: parse `layout.json` and compare to baseline and invariants.
4. Decide: Codex modifies UI code/spec to satisfy the checks.
5. Repeat until exit code is `0`.

Artifacts per iteration:

- `artifacts/<run>/layout.json`
- `artifacts/<run>/runner.log` (native logs)
- Optional: `artifacts/<run>/screenshot.png` for visual inspection, not as the primary gate.

## Implementation Notes (Repo-Specific Pointers)

Where to read the data:

- `retained.NodeStore.nodes` in `src/retained/core/node_store.zig`
- Layout rects in `src/retained/core/layout.zig` (`LayoutCache.rect`, `LayoutCache.child_rect`)

Where to place the dump hook:

- After `retained.render(...)` in `src/native_renderer/window.zig`, when layout has been computed.

Where to implement the CLI:

- Add a new executable target (recommended) or extend `luau-native-runner`.
- Ensure deterministic run controls: fixed window size, fixed dt, fixed number of frames, predictable exit.

