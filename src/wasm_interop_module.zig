const std = @import("std");
const rawr = @import("roaring.zig");

const RoaringBitmap = rawr.RoaringBitmap;

const WORK_HEAP_BYTES = 4 * 1024 * 1024;
const OUTPUT_CAPACITY = 512 * 1024;
const INPUT_CAPACITY = 512 * 1024;

var work_heap: [WORK_HEAP_BYTES]u8 align(16) = undefined;
var output_buf: [OUTPUT_CAPACITY]u8 align(16) = undefined;
var input_buf: [INPUT_CAPACITY]u8 align(16) = undefined;
var fba = std.heap.FixedBufferAllocator.init(work_heap[0..]);

fn freshAllocator() std.mem.Allocator {
    fba = std.heap.FixedBufferAllocator.init(work_heap[0..]);
    return fba.allocator();
}

fn buildFixtureBitmap(bm: *RoaringBitmap) !void {
    _ = try bm.addRange(0, 4095);
    _ = try bm.addRange(65536 + 120, 65536 + 512);

    var i: u32 = 0;
    while (i < 2048) : (i += 1) {
        _ = try bm.add(131072 + i * 3);
    }

    _ = try bm.add(0xFFFF_FFFF);
    _ = try bm.add(0x7FFF_0001);
    _ = try bm.add(0x0001_0001);
    _ = try bm.runOptimize();
}

fn serializeIntoOutput(bm: *const RoaringBitmap) !u32 {
    const out_len = try bm.serializeIntoBuffer(output_buf[0..]);
    return @intCast(out_len);
}

pub export fn rawr_input_ptr() u32 {
    return @intCast(@intFromPtr(&input_buf[0]));
}

pub export fn rawr_input_capacity() u32 {
    return INPUT_CAPACITY;
}

pub export fn rawr_output_ptr() u32 {
    return @intCast(@intFromPtr(&output_buf[0]));
}

pub export fn rawr_output_capacity() u32 {
    return OUTPUT_CAPACITY;
}

pub export fn rawr_fixture_serialize() u32 {
    const allocator = freshAllocator();

    var bm = RoaringBitmap.init(allocator) catch return 0;
    defer bm.deinit();

    buildFixtureBitmap(&bm) catch return 0;
    return serializeIntoOutput(&bm) catch 0;
}

pub export fn rawr_roundtrip_input(input_len: u32) u32 {
    if (input_len > INPUT_CAPACITY) return 0;

    const allocator = freshAllocator();
    var bm = RoaringBitmap.deserialize(allocator, input_buf[0..input_len]) catch return 0;
    defer bm.deinit();

    return serializeIntoOutput(&bm) catch 0;
}
