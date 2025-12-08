# Zig Application Architecture: State and Memory Design

## Global Access Pattern

Large Zig applications often use **global or module-level pointers** for accessing core subsystems such as configuration, assets, or application state.
This approach enables **cross-module communication** without requiring allocators or context objects to be passed through every function call.

### Guidelines

- Initialize global references at startup and clean them up explicitly at shutdown.
- Keep globals minimal—only expose stable, long-lived systems.
- Avoid hidden dependencies by documenting which modules rely on global state.

## Layered Allocator Strategy

Zig gives fine-grained control over memory. A **multi-tiered allocator design** helps manage different allocation patterns efficiently.

### 1. Application Allocator (Primary)

- Use a general-purpose allocator for most long-lived structures.
- Choose between debugging and performance allocators depending on build mode

### 2. Temporary or Frame Allocators

- Use `ArenaAllocator` or similar for short-lived data such as UI buffers or temporary calculations.
- Reset arenas periodically (e.g., every frame or operation) with `.retain_capacity` to reuse memory efficiently.

### 3. Independent Subsystem Allocators

- Allow independent modules (e.g., asset management, networking, etc.) to maintain their own allocator when they manage large or isolated memory domains.
- This separation makes tracking, profiling, and cleanup more predictable.

---

## Lifecycle and Ownership

### Explicit Initialization and Cleanup

- Each struct should define clear `init()` and `deinit()` functions.
- Use explicit ownership — the struct that allocates memory must also free it.
- No automatic RAII: memory and resource lifetimes must be manually managed.

### Nested Resource Ownership

- Parent structs are responsible for deinitializing all nested resources.
- Follow a top-down cleanup order to prevent leaks and dangling pointers.

---

## Key Architectural Principles

1. **Explicit State** – Global pointers simplify access but require discipline and documentation.
2. **Allocator Specialization** – Match allocator type to the lifetime and frequency of allocations.
3. **Manual Resource Control** – Always define and follow `init()`/`deinit()` lifecycles for core-logic structs.
4. **Debug Safety** – Use debug allocators and leak detection during development.
5. **Subsystem Independence** – Isolate allocators and data lifecycles for modular, testable components.

## Clay Engine Programming Guide

Provide concise, clear, data-oriented, and decoupled code architecture for any new features.
No boiler plate or syntax sugar, ONLY the minimal core functionality needed.

If on WSL, don't try to `zig build` or `zig test`, it won't work. I will verify your work myself.

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

For detailed `std.ArrayList` usage, see `Zig_ArrayList.md`.

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
