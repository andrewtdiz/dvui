# Reactive APIs (Decl Runtime)

## untrack(fn)

`untrack(fn)` runs `fn` without recording reactive dependencies. It returns `fn()`'s return value.

## List primitive: `For{ ... }`

DVUI's declarative runtime uses the existing `For{ each, key, children }` node and upgrades it instead of adding `indexes()`/`values()`.

### API shape

`For{
  each = () -> {T},
  key = (item: T, i: number) -> any,
  children = (item: T, i: number, value: Source<T>, index: Source<number>, key: any) -> Node
}`

`children` is only called on first mount per key. When the backing list changes, existing children are reused and their `value` and `index` Sources are updated.

`children(...)` runs untracked and inside the mounted child scope, so any reactive primitives created there (effects, springs, etc.) are owned per-item and are cleaned up when the item is removed.

### Identity and duplicates

- Item identity is determined by `key(item, i)`.
- If `key(...)` returns `nil`, the key defaults to `i` (index-based identity).
- Keys must be unique within a single `each()` result; duplicates throw `duplicate For key`.

### Internal state (renderer)

- `by_key[key] -> child record`
- `value_by_key[key] -> Source<T>` (updated with the latest item for that key)
- `index_by_key[key] -> Source<number>` (updated with the current index for that key)
- `order -> {key}` (latest key order for stable re-insertion)
