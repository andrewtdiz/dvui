# Retained Loaders (`loaders/`)

## Responsibility
Loads external representations of UI into a retained `NodeStore`. Currently this directory provides a JSON snapshot loader for a Clay-style `ui.json` schema.

## Public Surface
- `ui_json.setSnapshotFromUiJsonValue(store, ring, ui_value, root_w, root_h)` loads a retained snapshot from parsed JSON.

## High-Level Architecture
- Entry: `setSnapshotFromUiJsonValue(store, ring, ui_value, root_w, root_h)` (`ui_json.zig`).
- Resets the `NodeStore` (recreates root id `0`) and clears the optional `EventRing`.
- Walks `ui_value.object["elements"]` recursively; each element allocates a new id, creates/inserts a retained node, generates a Tailwind-like `class_name` (absolute layout + metadata tokens), applies optional fields (`color`, `src`, `value`), then recurses into `"children"`.
- Text elements are represented as an element (`tag="p"`) plus a child text node.

## Core Data Model
- Expected JSON shape: root object containing `"elements"` (object map). Element objects may contain `"type"`, `"size"`, `"position"`, `"anchor"`, `"color"`, `"text"`, `"src"`, `"value"`, `"children"`, and font fields.
- Retained snapshot encoding: element ids are assigned monotonically (`u32`), text child id is `0x80000000 | element_id`, and `class_name` carries layout metadata (`absolute left-[x] top-[y] w-[w] h-[h]`, `ui-key-*`, `ui-path-*`, plus optional font tokens).

## Critical Assumptions
- `root_w`/`root_h` must be finite and > 0.
- Unknown `"type"` values fall back to `"div"`. `"text"` is special-cased to create a `p` element plus a text node.
- Position values can be numeric or strings ending in `px` or `%`; invalid values resolve to 0.
- Colors are expected as RGBA channels (0-255) packed as `r<<24 | g<<16 | b<<8 | a`.
