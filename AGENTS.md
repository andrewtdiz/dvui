# DVUI

See ARCHITECTURE.md for high-level project context.

## CRITICAL RULES (Always Follow)

1. **NO COMMENTS** - Code must be self-documenting through clear names
2. **NO CLASSES** - Use plain functions, not OOP patterns unless explicitly asked
3. **NO PREMATURE ABSTRACTION** - Write clear, minimal and functional code on first pass. Respect existing architecture boundaries.
4. **BE CONCISE**
5. **NEVER GIT PUSH or REVERT LOCAL CHANGES** - NEVER push to git history or revert local changes. ONLY add and commit changes.

**IMPORTANT: ASK BEFORE MODIFYING DEPENDENCIES** - You must ask the user first before making a change in deps/
**IMPORTANT: NO PREMATURE OPTIMIZATION** – If a request seems to violate this, ask for clarification before proceeding.
**IMPORTANT: CORE-FIRST TASKS** – Expand work from the core of the most important, value-adding functionality. Ship verifiable functionality as early as possible, then layer on features to extend the core. Recommend performance/memory/organization tasks only when needed.

After changing Zig code, verify compilation from WSL (runs on Windows) by running `./zig_build_simple.sh`.
Use raw `zigwin build --summary failures` output for deep debugging.
- Example: `zigwin build --summary failures`. Supported `--summary` values: `all`, `new`, `failures`, `none`.

You won't be able to start the runtime or test with `zig build run` or `zig test`, it won't work on WSL.

---

## Critical Zig APIs

### Use `const` for immutabile variables

If a variable's value is not set again after initialization, you MUST declare it as `const` or Zig will throw a compiler error.

### Variable shadowing

In Zig, function arguments and local variables cannot shadow outer-scope global variables.

### Pointer dereferencing

Use `&someRef` to dereference a pointer NOT `someRef.ptr`, that is invalid in Zig

### `@min` and `@max` for math

Unlike some other languages, `std.math.min` and `std.math.max` are not functions in Zig `std.math` library.
Instead, use the built-in functions `@min` and `@max`.

### You don't need pass a type T for @ casts

In Zig, `@intCast` and `@bitCast` infers the target type from context. These builtins have the signature:
`@intCast(value: anytype) anytype`
`@bitCast(value: anytype) anytype`

The return type is determined by how the result is assigned or used. Here are the correct patterns:

**✓ CORRECT - Type inferred from assignment:**

```zig
const color_index: usize = @intCast(colorInt);  // returns usize
const my_i32: i32 = @bitCast(@as(u32, 0x12345678));  // returns i32 from u32 bits
```

### Type Coercion to Float: Use `@float`

Unlike some other languages, there is no `std.math.float` function; use the built-in `@float` for integer to float coercion.

### ArrayList syntax

For detailed `std.ArrayList` usage, see `@agents/Zig_ArrayList.md`.

```zig
const std = @import("std");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var list: std.ArrayList(i32) = .empty;
    defer list.deinit(allocator);

    try list.append(allocator, 42);
}
```

## Verify Zig APIs with `zigdoc`

Zig's standard library APIs change frequently. Do not rely on prior knowledge. **Use the `zigdoc` CLI to verify Zig APIs.**

### `zigdoc` Usage

`zigdoc` provides documentation for Zig standard library `std`.

```
zigdoc [options] <symbol>
```

Examples:

```
zigdoc std.ArrayList
zigdoc std.mem.Allocator
zigdoc std.http.Server
zigdoc std.fs.Dir.readFileAlloc
```

