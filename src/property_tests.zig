const std = @import("std");
const RoaringBitmap = @import("bitmap.zig").RoaringBitmap;
const FrozenBitmap = @import("frozen.zig").FrozenBitmap;

/// Property-based tests verifying set algebra axioms.
/// Uses random bitmaps and checks algebraic identities.
fn randomBitmap(allocator: std.mem.Allocator, rng: std.Random, max_values: usize) !RoaringBitmap {
    var bm = try RoaringBitmap.init(allocator);
    errdefer bm.deinit();

    const num_values = rng.intRangeAtMost(usize, 1, max_values);
    for (0..num_values) |_| {
        const value = rng.int(u32);
        _ = try bm.add(value);
    }
    return bm;
}

fn expectBitmapEqual(a: *const RoaringBitmap, b: *const RoaringBitmap) !void {
    if (!a.equals(b)) {
        return error.BitmapsNotEqual;
    }
}

fn denseBitmapFromRange(allocator: std.mem.Allocator, lo: u32, hi: u32) !RoaringBitmap {
    std.debug.assert(lo <= hi);
    const len: usize = @intCast(hi - lo + 1);
    const values = try allocator.alloc(u32, len);
    defer allocator.free(values);

    for (values, 0..) |*slot, i| {
        slot.* = lo + @as(u32, @intCast(i));
    }

    return RoaringBitmap.fromSorted(allocator, values);
}

fn randomShapedBitmap(allocator: std.mem.Allocator, rng: std.Random) !RoaringBitmap {
    switch (rng.uintLessThan(u8, 4)) {
        0 => return randomBitmap(allocator, rng, 200),
        1 => {
            const hi_start = std.math.maxInt(u32) - 7000;
            const lo = rng.intRangeAtMost(u32, 0, hi_start);
            const len = rng.intRangeAtMost(u32, 4500, 7000);
            return denseBitmapFromRange(allocator, lo, lo + len);
        },
        2 => {
            var bm = try RoaringBitmap.init(allocator);
            errdefer bm.deinit();

            const base = @as(u32, rng.intRangeLessThan(u16, 0, std.math.maxInt(u16))) << 16;
            const run_count = rng.intRangeAtMost(u8, 1, 5);
            for (0..run_count) |_| {
                const start = rng.intRangeAtMost(u16, 0, 65000);
                const len = rng.intRangeAtMost(u16, 1, 400);
                const end = @min(@as(u32, start) + len, @as(u32, std.math.maxInt(u16)));
                _ = try bm.addRange(base + start, base + end);
            }
            _ = try bm.runOptimize();
            return bm;
        },
        else => {
            var bm = try randomBitmap(allocator, rng, 120);
            errdefer bm.deinit();

            const hi_start = std.math.maxInt(u32) - 5000;
            const lo = rng.intRangeAtMost(u32, 0, hi_start);
            _ = try bm.addRange(lo, lo + rng.intRangeAtMost(u32, 256, 5000));
            if (rng.boolean()) {
                _ = try bm.runOptimize();
            }
            return bm;
        },
    }
}

// ============================================================================
// Set Algebra Property Tests
// ============================================================================

test "commutativity: A ∪ B = B ∪ A" {
    const allocator = std.testing.allocator;
    var prng = std.Random.DefaultPrng.init(12345);
    const rng = prng.random();

    for (0..50) |_| {
        var a = try randomBitmap(allocator, rng, 100);
        defer a.deinit();
        var b = try randomBitmap(allocator, rng, 100);
        defer b.deinit();

        var ab = try a.bitwiseOr(allocator, &b);
        defer ab.deinit();
        var ba = try b.bitwiseOr(allocator, &a);
        defer ba.deinit();

        try expectBitmapEqual(&ab, &ba);
    }
}

test "commutativity: A ∩ B = B ∩ A" {
    const allocator = std.testing.allocator;
    var prng = std.Random.DefaultPrng.init(12346);
    const rng = prng.random();

    for (0..50) |_| {
        var a = try randomBitmap(allocator, rng, 100);
        defer a.deinit();
        var b = try randomBitmap(allocator, rng, 100);
        defer b.deinit();

        var ab = try a.bitwiseAnd(allocator, &b);
        defer ab.deinit();
        var ba = try b.bitwiseAnd(allocator, &a);
        defer ba.deinit();

        try expectBitmapEqual(&ab, &ba);
    }
}

test "commutativity: A ⊕ B = B ⊕ A" {
    const allocator = std.testing.allocator;
    var prng = std.Random.DefaultPrng.init(12347);
    const rng = prng.random();

    for (0..50) |_| {
        var a = try randomBitmap(allocator, rng, 100);
        defer a.deinit();
        var b = try randomBitmap(allocator, rng, 100);
        defer b.deinit();

        var ab = try a.bitwiseXor(allocator, &b);
        defer ab.deinit();
        var ba = try b.bitwiseXor(allocator, &a);
        defer ba.deinit();

        try expectBitmapEqual(&ab, &ba);
    }
}

test "associativity: (A ∪ B) ∪ C = A ∪ (B ∪ C)" {
    const allocator = std.testing.allocator;
    var prng = std.Random.DefaultPrng.init(12348);
    const rng = prng.random();

    for (0..30) |_| {
        var a = try randomBitmap(allocator, rng, 50);
        defer a.deinit();
        var b = try randomBitmap(allocator, rng, 50);
        defer b.deinit();
        var c = try randomBitmap(allocator, rng, 50);
        defer c.deinit();

        // (A ∪ B) ∪ C
        var ab = try a.bitwiseOr(allocator, &b);
        defer ab.deinit();
        var ab_c = try ab.bitwiseOr(allocator, &c);
        defer ab_c.deinit();

        // A ∪ (B ∪ C)
        var bc = try b.bitwiseOr(allocator, &c);
        defer bc.deinit();
        var a_bc = try a.bitwiseOr(allocator, &bc);
        defer a_bc.deinit();

        try expectBitmapEqual(&ab_c, &a_bc);
    }
}

test "associativity: (A ∩ B) ∩ C = A ∩ (B ∩ C)" {
    const allocator = std.testing.allocator;
    var prng = std.Random.DefaultPrng.init(12349);
    const rng = prng.random();

    for (0..30) |_| {
        var a = try randomBitmap(allocator, rng, 50);
        defer a.deinit();
        var b = try randomBitmap(allocator, rng, 50);
        defer b.deinit();
        var c = try randomBitmap(allocator, rng, 50);
        defer c.deinit();

        // (A ∩ B) ∩ C
        var ab = try a.bitwiseAnd(allocator, &b);
        defer ab.deinit();
        var ab_c = try ab.bitwiseAnd(allocator, &c);
        defer ab_c.deinit();

        // A ∩ (B ∩ C)
        var bc = try b.bitwiseAnd(allocator, &c);
        defer bc.deinit();
        var a_bc = try a.bitwiseAnd(allocator, &bc);
        defer a_bc.deinit();

        try expectBitmapEqual(&ab_c, &a_bc);
    }
}

test "distributivity: A ∩ (B ∪ C) = (A ∩ B) ∪ (A ∩ C)" {
    const allocator = std.testing.allocator;
    var prng = std.Random.DefaultPrng.init(12350);
    const rng = prng.random();

    for (0..30) |_| {
        var a = try randomBitmap(allocator, rng, 50);
        defer a.deinit();
        var b = try randomBitmap(allocator, rng, 50);
        defer b.deinit();
        var c = try randomBitmap(allocator, rng, 50);
        defer c.deinit();

        // A ∩ (B ∪ C)
        var bc = try b.bitwiseOr(allocator, &c);
        defer bc.deinit();
        var lhs = try a.bitwiseAnd(allocator, &bc);
        defer lhs.deinit();

        // (A ∩ B) ∪ (A ∩ C)
        var ab = try a.bitwiseAnd(allocator, &b);
        defer ab.deinit();
        var ac = try a.bitwiseAnd(allocator, &c);
        defer ac.deinit();
        var rhs = try ab.bitwiseOr(allocator, &ac);
        defer rhs.deinit();

        try expectBitmapEqual(&lhs, &rhs);
    }
}

test "identity: A ∪ ∅ = A" {
    const allocator = std.testing.allocator;
    var prng = std.Random.DefaultPrng.init(12351);
    const rng = prng.random();

    for (0..50) |_| {
        var a = try randomBitmap(allocator, rng, 100);
        defer a.deinit();
        var empty = try RoaringBitmap.init(allocator);
        defer empty.deinit();

        var result = try a.bitwiseOr(allocator, &empty);
        defer result.deinit();

        try expectBitmapEqual(&a, &result);
    }
}

test "idempotence: A ∪ A = A" {
    const allocator = std.testing.allocator;
    var prng = std.Random.DefaultPrng.init(12352);
    const rng = prng.random();

    for (0..50) |_| {
        var a = try randomBitmap(allocator, rng, 100);
        defer a.deinit();

        var result = try a.bitwiseOr(allocator, &a);
        defer result.deinit();

        try expectBitmapEqual(&a, &result);
    }
}

test "idempotence: A ∩ A = A" {
    const allocator = std.testing.allocator;
    var prng = std.Random.DefaultPrng.init(12353);
    const rng = prng.random();

    for (0..50) |_| {
        var a = try randomBitmap(allocator, rng, 100);
        defer a.deinit();

        var result = try a.bitwiseAnd(allocator, &a);
        defer result.deinit();

        try expectBitmapEqual(&a, &result);
    }
}

test "complement: A − A = ∅" {
    const allocator = std.testing.allocator;
    var prng = std.Random.DefaultPrng.init(12354);
    const rng = prng.random();

    for (0..50) |_| {
        var a = try randomBitmap(allocator, rng, 100);
        defer a.deinit();

        var result = try a.bitwiseDifference(allocator, &a);
        defer result.deinit();

        try std.testing.expect(result.isEmpty());
    }
}

test "self xor: A ⊕ A = ∅" {
    const allocator = std.testing.allocator;
    var prng = std.Random.DefaultPrng.init(12355);
    const rng = prng.random();

    for (0..50) |_| {
        var a = try randomBitmap(allocator, rng, 100);
        defer a.deinit();

        var result = try a.bitwiseXor(allocator, &a);
        defer result.deinit();

        try std.testing.expect(result.isEmpty());
    }
}

test "cardinality: |A ∪ B| + |A ∩ B| = |A| + |B|" {
    const allocator = std.testing.allocator;
    var prng = std.Random.DefaultPrng.init(12356);
    const rng = prng.random();

    for (0..50) |_| {
        var a = try randomBitmap(allocator, rng, 100);
        defer a.deinit();
        var b = try randomBitmap(allocator, rng, 100);
        defer b.deinit();

        var union_ab = try a.bitwiseOr(allocator, &b);
        defer union_ab.deinit();
        var intersect_ab = try a.bitwiseAnd(allocator, &b);
        defer intersect_ab.deinit();

        const lhs = union_ab.cardinality() + intersect_ab.cardinality();
        const rhs = a.cardinality() + b.cardinality();

        try std.testing.expectEqual(lhs, rhs);
    }
}

test "subset transitivity: (A ∩ B) ⊆ A and (A ∩ B) ⊆ B" {
    const allocator = std.testing.allocator;
    var prng = std.Random.DefaultPrng.init(12357);
    const rng = prng.random();

    for (0..50) |_| {
        var a = try randomBitmap(allocator, rng, 100);
        defer a.deinit();
        var b = try randomBitmap(allocator, rng, 100);
        defer b.deinit();

        var ab = try a.bitwiseAnd(allocator, &b);
        defer ab.deinit();

        try std.testing.expect(ab.isSubsetOf(&a));
        try std.testing.expect(ab.isSubsetOf(&b));
    }
}

test "difference subset: (A − B) ⊆ A" {
    const allocator = std.testing.allocator;
    var prng = std.Random.DefaultPrng.init(12358);
    const rng = prng.random();

    for (0..50) |_| {
        var a = try randomBitmap(allocator, rng, 100);
        defer a.deinit();
        var b = try randomBitmap(allocator, rng, 100);
        defer b.deinit();

        var diff = try a.bitwiseDifference(allocator, &b);
        defer diff.deinit();

        try std.testing.expect(diff.isSubsetOf(&a));
    }
}

test "xor decomposition: A ⊕ B = (A − B) ∪ (B − A)" {
    const allocator = std.testing.allocator;
    var prng = std.Random.DefaultPrng.init(12359);
    const rng = prng.random();

    for (0..30) |_| {
        var a = try randomBitmap(allocator, rng, 50);
        defer a.deinit();
        var b = try randomBitmap(allocator, rng, 50);
        defer b.deinit();

        // A ⊕ B
        var xor_ab = try a.bitwiseXor(allocator, &b);
        defer xor_ab.deinit();

        // (A − B) ∪ (B − A)
        var a_minus_b = try a.bitwiseDifference(allocator, &b);
        defer a_minus_b.deinit();
        var b_minus_a = try b.bitwiseDifference(allocator, &a);
        defer b_minus_a.deinit();
        var union_diff = try a_minus_b.bitwiseOr(allocator, &b_minus_a);
        defer union_diff.deinit();

        try expectBitmapEqual(&xor_ab, &union_diff);
    }
}

test "absorption: A ∪ (A ∩ B) = A" {
    const allocator = std.testing.allocator;
    var prng = std.Random.DefaultPrng.init(12360);
    const rng = prng.random();

    for (0..50) |_| {
        var a = try randomBitmap(allocator, rng, 100);
        defer a.deinit();
        var b = try randomBitmap(allocator, rng, 100);
        defer b.deinit();

        var ab = try a.bitwiseAnd(allocator, &b);
        defer ab.deinit();
        var result = try a.bitwiseOr(allocator, &ab);
        defer result.deinit();

        try expectBitmapEqual(&a, &result);
    }
}

test "frozen intersection parity: randomized live vs serialized" {
    const allocator = std.testing.allocator;
    var prng = std.Random.DefaultPrng.init(12361);
    const rng = prng.random();

    for (0..80) |_| {
        var a = try randomShapedBitmap(allocator, rng);
        defer a.deinit();
        var b = try randomShapedBitmap(allocator, rng);
        defer b.deinit();

        const live_card = a.andCardinality(&b);
        const live_intersects = a.intersects(&b);

        var live_and = try a.bitwiseAnd(allocator, &b);
        defer live_and.deinit();
        try std.testing.expectEqual(live_card, live_and.cardinality());
        try std.testing.expectEqual(live_intersects, !live_and.isEmpty());

        const sa = try a.serialize(allocator);
        defer allocator.free(sa);
        const sb = try b.serialize(allocator);
        defer allocator.free(sb);

        const fa = try FrozenBitmap.init(sa);
        const fb = try FrozenBitmap.init(sb);

        try std.testing.expectEqual(live_card, fa.andCardinality(&fb));
        try std.testing.expectEqual(live_card, fb.andCardinality(&fa));
        try std.testing.expectEqual(live_intersects, fa.intersects(&fb));
        try std.testing.expectEqual(live_intersects, fb.intersects(&fa));
    }
}

test "frozen intersection parity: same-word run masks stay exact" {
    const allocator = std.testing.allocator;
    var prng = std.Random.DefaultPrng.init(12362);
    const rng = prng.random();

    for (0..80) |_| {
        var bitset = try denseBitmapFromRange(allocator, 0, 5000);
        defer bitset.deinit();

        var run = try RoaringBitmap.init(allocator);
        defer run.deinit();

        const start = rng.intRangeAtMost(u16, 0, 4999);
        const len = rng.intRangeAtMost(u16, 0, @min(@as(u16, 63), @as(u16, 5000 - start)));
        _ = try run.addRange(start, start + len);
        _ = try run.runOptimize();

        const live_card = bitset.andCardinality(&run);
        const live_intersects = bitset.intersects(&run);

        const s_bitset = try bitset.serialize(allocator);
        defer allocator.free(s_bitset);
        const s_run = try run.serialize(allocator);
        defer allocator.free(s_run);

        const f_bitset = try FrozenBitmap.init(s_bitset);
        const f_run = try FrozenBitmap.init(s_run);

        try std.testing.expectEqual(live_card, f_bitset.andCardinality(&f_run));
        try std.testing.expectEqual(live_intersects, f_bitset.intersects(&f_run));
    }
}
