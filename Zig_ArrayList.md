# ArrayList in Zig 0.15 - Quick Reference

## Basic Setup

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

**Key Pattern**: Pass allocator as first parameter to functions that allocate.

---

## Initialization

```zig
// Empty list
var list: std.ArrayList(i32) = .empty;

// With initial capacity
var list = try std.ArrayList(i32).initCapacity(allocator, 100);

// From existing buffer
var buffer: [256]u8 = undefined;
var list = std.ArrayList(u8).initBuffer(buffer[0..]);

// From owned slice
const slice = try allocator.alloc(i32, 100);
var list = std.ArrayList(i32).fromOwnedSlice(slice);
```

---

## Adding Elements

```zig
// Single element - may allocate
try list.append(allocator, 42);

// Slice - may allocate
try list.appendSlice(allocator, &[_]i32{ 1, 2, 3 });

// N times - may allocate
try list.appendNTimes(allocator, 42, 10);

// Get pointer to new element
const ptr = try list.addOne(allocator);
ptr.* = 42;

// Multiple elements as array
const arr: *[4]i32 = try list.addManyAsArray(allocator, 4);
arr[0] = 1;

// Multiple elements as slice
const slice = try list.addManyAsSlice(allocator, 5);
slice[0] = 1;
```

**No-allocation variants** (use when capacity exists):

```zig
list.appendAssumeCapacity(42);
list.appendSliceAssumeCapacity(&[_]i32{ 1, 2, 3 });
list.appendNTimesAssumeCapacity(42, 10);
const ptr = list.addOneAssumeCapacity();
```

**Bounded variants** (fail with error instead of allocating):

```zig
try list.appendBounded(42);
try list.appendSliceBounded(&[_]i32{ 1, 2, 3 });
try list.appendNTimesBounded(42, 10);
const ptr = try list.addOneBounded();
```

---

## Inserting Elements

```zig
// Insert single - may allocate, O(N)
try list.insert(allocator, 0, 99);

// Insert slice - may allocate, O(N)
try list.insertSlice(allocator, 2, &[_]i32{ 10, 11, 12 });

// Add N undefined elements at position - may allocate
const slice = try list.addManyAt(allocator, 1, 3);

// No-allocation versions
list.insertAssumeCapacity(0, 99);
const slice = list.addManyAtAssumeCapacity(1, 3);

// Bounded
try list.insertBounded(0, 99);
const slice = try list.addManyAtBounded(1, 3);
```

---

## Removing Elements

```zig
// Remove and return last element
if (list.pop()) |value| { }

// Remove at index, preserve order - O(N)
const value = list.orderedRemove(2);

// Remove at index, fill gap from end - O(1)
const value = list.swapRemove(2);

// Remove multiple at sorted indices
list.orderedRemoveMany(&.{ 1, 3, 5 });
```

---

## Modifying Ranges

```zig
// Replace items at range - may allocate
try list.replaceRange(allocator, 1, 2, &[_]i32{ 99 });

// No-allocation version
list.replaceRangeAssumeCapacity(1, 2, &[_]i32{ 99 });

// Bounded
try list.replaceRangeBounded(1, 2, &[_]i32{ 99 });
```

---

## Capacity Management

```zig
// Ensure at least N total capacity (may grow more than N)
try list.ensureTotalCapacity(allocator, 100);

// Ensure exactly N capacity
try list.ensureTotalCapacityPrecise(allocator, 100);

// Ensure N additional unused capacity
try list.ensureUnusedCapacity(allocator, 50);

// Set length to N (new elements undefined)
try list.resize(allocator, 50);

// Shrink length only, keep capacity
list.shrinkRetainingCapacity(25);

// Shrink both length and capacity
list.shrinkAndFree(allocator, 25);

// Clear and keep capacity
list.clearRetainingCapacity();

// Clear and free memory
list.clearAndFree(allocator);

// Expand length to match capacity
list.expandToCapacity();
```

---

## Accessing Elements

```zig
// By index
const value = list.items[0];

// Iterate
for (list.items) |item| { }

// Enumerate
for (list.items, 0..) |item, i| { }

// Last element
const last = list.getLast();  // Asserts not empty
if (list.getLastOrNull()) |last| { }

// Properties
const len = list.items.len;         // Current size
const cap = list.capacity;          // Total allocated
const all = list.allocatedSlice();  // All allocated memory
const unused = list.unusedCapacitySlice();  // Empty space
```

---

## Memory Transfer

```zig
// Convert to owned slice - list becomes empty
const slice = try list.toOwnedSlice(allocator);
defer allocator.free(slice);

// Convert with null sentinel
const sentinel_slice = try list.toOwnedSliceSentinel(allocator, 0);
defer allocator.free(sentinel_slice);

// Clone to new list
var cloned = try list.clone(allocator);
defer cloned.deinit(allocator);

// Convert between managed/unmanaged
var unmanaged: std.ArrayList(i32) = .empty;
var managed = unmanaged.toManaged(allocator);
var back_to_unmanaged = managed.moveToUnmanaged();
```

---

## Writing (u8 only)

```zig
var buffer: std.ArrayList(u8) = .empty;
defer buffer.deinit(allocator);

// May allocate
try buffer.print(allocator, "Hello {}\n", .{42});

// No allocation
buffer.printAssumeCapacity("Value: {}", .{x});

// Bounded
try buffer.printBounded("Value: {}", .{x});
```

---

## Pointer Invalidation

Functions that **may reallocate** (invalidate all pointers):

- `append`, `appendSlice`, `insert`, `insertSlice`, `addManyAt`
- `replaceRange`, `resize`, `ensureTotalCapacity`, `ensureUnusedCapacity`

Functions that **only invalidate affected elements**:

- `appendAssumeCapacity`, `insertAssumeCapacity`, `orderedRemove`

Functions that **never invalidate pointers**:

- `appendSliceAssumeCapacity`, `appendNTimesAssumeCapacity`, `replaceRangeAssumeCapacity`

```zig
try list.append(allocator, 1);
const ptr = &list.items[0];
try list.append(allocator, 2);  // May reallocate - ptr is INVALID now
```

---

## Aligned Allocation

```zig
var list: std.ArrayList.Aligned(i32, .@"16") = .empty;
defer list.deinit(allocator);

// Elements aligned to 16-byte boundary
try list.append(allocator, 42);
```

---

## Performance Pattern: Pre-allocate

```zig
var list: std.ArrayList(i32) = .empty;
defer list.deinit(allocator);

// Pre-allocate if you know size
try list.ensureUnusedCapacity(allocator, 1000);

// Now append won't reallocate
for (0..1000) |i| {
    list.appendAssumeCapacity(@intCast(i));
}
```

---

## Zero-Sized Types

```zig
// No allocation needed, capacity = maxInt(usize)
var list: std.ArrayList(u0) = .empty;
try list.append(allocator, 0);  // No actual allocation
```

---

## Common Patterns

**Collect into list, then own the slice**:

```zig
var list: std.ArrayList(u8) = .empty;
defer list.deinit(allocator);

try list.appendSlice(allocator, data1);
try list.appendSlice(allocator, data2);

const result = try list.toOwnedSlice(allocator);
defer allocator.free(result);
```

**Iterate and remove**:

```zig
var i: usize = 0;
while (i < list.items.len) {
    if (should_remove(list.items[i])) {
        _ = list.orderedRemove(i);
    } else {
        i += 1;
    }
}
```

**Fast removal (order doesn't matter)**:

```zig
while (list.items.len > 0) {
    const item = list.swapRemove(0);  // O(1), not O(N)
    process(item);
}
```

---

## Always Remember

- Call `defer list.deinit(allocator)`
- Pass allocator as first parameter to allocating functions
- Use `AssignCapacity` variants only when you've pre-allocated
- Check pointer invalidation before using saved pointers
- Use `try` to handle `OutOfMemory` errors
