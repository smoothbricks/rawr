const std = @import("std");
const ArrayContainer = @import("array_container.zig").ArrayContainer;
const BitsetContainer = @import("bitset_container.zig").BitsetContainer;
const RunContainer = @import("run_container.zig").RunContainer;

/// Tagged pointer encoding for containers.
/// Low 2 bits encode the container type (pointers are at least 4-byte aligned).
pub const TaggedPtr = struct {
    raw: usize,

    const TAG_BITS: usize = 2;
    const TAG_MASK: usize = (1 << TAG_BITS) - 1;

    pub const ContainerType = enum(u2) {
        array = 0b00,
        bitset = 0b01,
        run = 0b10,
        reserved = 0b11,
    };

    pub fn initArray(ptr: *ArrayContainer) TaggedPtr {
        return init(ptr, .array);
    }

    pub fn initBitset(ptr: *BitsetContainer) TaggedPtr {
        return init(ptr, .bitset);
    }

    pub fn initRun(ptr: *RunContainer) TaggedPtr {
        return init(ptr, .run);
    }

    fn init(ptr: anytype, tag: ContainerType) TaggedPtr {
        const ptr_bits = @intFromPtr(ptr);
        std.debug.assert((ptr_bits & TAG_MASK) == 0);
        return .{ .raw = ptr_bits | @intFromEnum(tag) };
    }

    pub fn getArray(self: TaggedPtr) *ArrayContainer {
        std.debug.assert(self.getType() == .array);
        return @ptrFromInt(self.ptrBits());
    }

    pub fn getBitset(self: TaggedPtr) *BitsetContainer {
        std.debug.assert(self.getType() == .bitset);
        return @ptrFromInt(self.ptrBits());
    }

    pub fn getRun(self: TaggedPtr) *RunContainer {
        std.debug.assert(self.getType() == .run);
        return @ptrFromInt(self.ptrBits());
    }

    pub fn getType(self: TaggedPtr) ContainerType {
        return @enumFromInt(@as(u2, @truncate(self.raw & TAG_MASK)));
    }

    pub fn eql(a: TaggedPtr, b: TaggedPtr) bool {
        return a.raw == b.raw;
    }

    fn ptrBits(self: TaggedPtr) usize {
        return self.raw & ~TAG_MASK;
    }
};

/// Unified container handle for polymorphic operations.
pub const Container = union(TaggedPtr.ContainerType) {
    array: *ArrayContainer,
    bitset: *BitsetContainer,
    run: *RunContainer,
    reserved: void,

    const Self = @This();

    /// Create from a tagged pointer.
    pub fn fromTagged(tp: TaggedPtr) Self {
        return switch (tp.getType()) {
            .array => .{ .array = tp.getArray() },
            .bitset => .{ .bitset = tp.getBitset() },
            .run => .{ .run = tp.getRun() },
            .reserved => .{ .reserved = {} },
        };
    }

    /// Convert to a tagged pointer.
    pub fn toTagged(self: Self) TaggedPtr {
        return switch (self) {
            .array => |c| TaggedPtr.initArray(c),
            .bitset => |c| TaggedPtr.initBitset(c),
            .run => |c| TaggedPtr.initRun(c),
            .reserved => unreachable,
        };
    }

    /// Check if a value is present.
    pub fn contains(self: Self, value: u16) bool {
        return switch (self) {
            .array => |c| c.contains(value),
            .bitset => |c| c.contains(value),
            .run => |c| c.contains(value),
            .reserved => false,
        };
    }

    /// Get cardinality.
    pub fn getCardinality(self: Self) u32 {
        return switch (self) {
            .array => |c| c.getCardinality(),
            .bitset => |c| c.getCardinality(),
            .run => |c| c.getCardinality(),
            .reserved => 0,
        };
    }

    /// Free the container.
    pub fn deinit(self: Self, allocator: std.mem.Allocator) void {
        switch (self) {
            .array => |c| c.deinit(allocator),
            .bitset => |c| c.deinit(allocator),
            .run => |c| c.deinit(allocator),
            .reserved => {},
        }
    }

    /// Create a deep copy.
    pub fn clone(self: Self, allocator: std.mem.Allocator) !Self {
        return switch (self) {
            .array => |c| .{ .array = try c.clone(allocator) },
            .bitset => |c| .{ .bitset = try c.clone(allocator) },
            .run => |c| .{ .run = try c.clone(allocator) },
            .reserved => .{ .reserved = {} },
        };
    }
};

// ============================================================================
// Tests
// ============================================================================

test "TaggedPtr round-trip array" {
    const allocator = std.testing.allocator;
    const ac = try ArrayContainer.init(allocator, 0);
    defer ac.deinit(allocator);

    _ = try ac.add(allocator, 42);

    const tp = TaggedPtr.initArray(ac);
    try std.testing.expectEqual(TaggedPtr.ContainerType.array, tp.getType());

    const retrieved = tp.getArray();
    try std.testing.expect(retrieved.contains(42));
}

test "TaggedPtr round-trip bitset" {
    const allocator = std.testing.allocator;
    const bc = try BitsetContainer.init(allocator);
    defer bc.deinit(allocator);

    _ = bc.add(1000);

    const tp = TaggedPtr.initBitset(bc);
    try std.testing.expectEqual(TaggedPtr.ContainerType.bitset, tp.getType());

    const retrieved = tp.getBitset();
    try std.testing.expect(retrieved.contains(1000));
}

test "TaggedPtr round-trip run" {
    const allocator = std.testing.allocator;
    const rc = try RunContainer.init(allocator, 0);
    defer rc.deinit(allocator);

    _ = try rc.add(allocator, 500);

    const tp = TaggedPtr.initRun(rc);
    try std.testing.expectEqual(TaggedPtr.ContainerType.run, tp.getType());

    const retrieved = tp.getRun();
    try std.testing.expect(retrieved.contains(500));
}

test "Container polymorphic contains" {
    const allocator = std.testing.allocator;

    const ac = try ArrayContainer.init(allocator, 0);
    defer ac.deinit(allocator);
    _ = try ac.add(allocator, 10);

    const bc = try BitsetContainer.init(allocator);
    defer bc.deinit(allocator);
    _ = bc.add(20);

    const rc = try RunContainer.init(allocator, 0);
    defer rc.deinit(allocator);
    _ = try rc.add(allocator, 30);

    const containers = [_]Container{
        .{ .array = ac },
        .{ .bitset = bc },
        .{ .run = rc },
    };

    try std.testing.expect(containers[0].contains(10));
    try std.testing.expect(!containers[0].contains(20));

    try std.testing.expect(containers[1].contains(20));
    try std.testing.expect(!containers[1].contains(10));

    try std.testing.expect(containers[2].contains(30));
    try std.testing.expect(!containers[2].contains(10));
}

test "Container polymorphic cardinality" {
    const allocator = std.testing.allocator;

    const ac = try ArrayContainer.init(allocator, 0);
    defer ac.deinit(allocator);
    _ = try ac.add(allocator, 1);
    _ = try ac.add(allocator, 2);
    _ = try ac.add(allocator, 3);

    const bc = try BitsetContainer.init(allocator);
    defer bc.deinit(allocator);
    for (0..100) |i| {
        _ = bc.add(@intCast(i));
    }

    const rc = try RunContainer.init(allocator, 0);
    defer rc.deinit(allocator);
    _ = try rc.add(allocator, 0);
    _ = try rc.add(allocator, 1);
    _ = try rc.add(allocator, 2);
    _ = try rc.add(allocator, 3);
    _ = try rc.add(allocator, 4);

    const c_array: Container = .{ .array = ac };
    const c_bitset: Container = .{ .bitset = bc };
    const c_run: Container = .{ .run = rc };

    try std.testing.expectEqual(@as(u32, 3), c_array.getCardinality());
    try std.testing.expectEqual(@as(u32, 100), c_bitset.getCardinality());
    try std.testing.expectEqual(@as(u32, 5), c_run.getCardinality());
}

test "Container fromTagged toTagged round-trip" {
    const allocator = std.testing.allocator;
    const ac = try ArrayContainer.init(allocator, 0);
    defer ac.deinit(allocator);
    _ = try ac.add(allocator, 99);

    const original: Container = .{ .array = ac };
    const tagged = original.toTagged();
    const restored = Container.fromTagged(tagged);

    try std.testing.expect(restored.contains(99));
    try std.testing.expectEqual(@as(u32, 1), restored.getCardinality());
}
