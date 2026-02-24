const std = @import("std");
const c = @cImport(@cInclude("croaring_wrapper.h"));

const allocator = std.heap.c_allocator;

const CompareCtx = struct {
    other: *const c.roaring_bitmap_t,
    ok: bool = true,
};

fn containsCallback(value: u32, param: ?*anyopaque) callconv(.c) bool {
    const ctx: *CompareCtx = @ptrCast(@alignCast(param.?));
    if (!c.roaring_bitmap_contains(ctx.other, value)) {
        ctx.ok = false;
        return false;
    }
    return true;
}

fn equalBitmaps(a: *const c.roaring_bitmap_t, b: *const c.roaring_bitmap_t) bool {
    if (c.roaring_bitmap_get_cardinality(a) != c.roaring_bitmap_get_cardinality(b)) {
        return false;
    }

    var ctx = CompareCtx{ .other = b };
    if (!c.roaring_iterate(a, containsCallback, &ctx)) {
        return false;
    }
    return ctx.ok;
}

fn serializeCR(bitmap: *const c.roaring_bitmap_t) ![]u8 {
    const size = c.roaring_bitmap_portable_size_in_bytes(bitmap);
    const out = try allocator.alloc(u8, size);
    errdefer allocator.free(out);
    _ = c.roaring_bitmap_portable_serialize(bitmap, @ptrCast(out.ptr));
    return out;
}

fn runNode(args: []const []const u8) !void {
    var child = std.process.Child.init(args, allocator);
    child.stdin_behavior = .Ignore;
    child.stdout_behavior = .Inherit;
    child.stderr_behavior = .Inherit;

    try child.spawn();
    const term = try child.wait();
    switch (term) {
        .Exited => |code| if (code != 0) return error.NodeScriptFailed,
        else => return error.NodeScriptFailed,
    }
}

fn writeFile(path: []const u8, bytes: []const u8) !void {
    var file = try std.fs.cwd().createFile(path, .{ .truncate = true });
    defer file.close();
    try file.writeAll(bytes);
}

fn readFile(path: []const u8) ![]u8 {
    return std.fs.cwd().readFileAlloc(allocator, path, 8 * 1024 * 1024);
}

fn buildFixtureCR(bitmap: *c.roaring_bitmap_t) void {
    c.roaring_bitmap_add_range(bitmap, 0, 4096);
    c.roaring_bitmap_add_range(bitmap, 65536 + 120, 65536 + 513);

    var i: u32 = 0;
    while (i < 2048) : (i += 1) {
        c.roaring_bitmap_add(bitmap, 131072 + i * 3);
    }

    c.roaring_bitmap_add(bitmap, 0xFFFF_FFFF);
    c.roaring_bitmap_add(bitmap, 0x7FFF_0001);
    c.roaring_bitmap_add(bitmap, 0x0001_0001);
    _ = c.roaring_bitmap_run_optimize(bitmap);
}

fn buildNativeInputCR(bitmap: *c.roaring_bitmap_t) void {
    c.roaring_bitmap_add_range(bitmap, 10, 1000);
    c.roaring_bitmap_add_range(bitmap, 70000, 71000);

    var i: u32 = 0;
    while (i < 3000) : (i += 1) {
        c.roaring_bitmap_add(bitmap, 200000 + i * 11);
    }

    c.roaring_bitmap_add(bitmap, 0x8000_0000);
    c.roaring_bitmap_add(bitmap, 0xFFFF_FFFE);
    _ = c.roaring_bitmap_run_optimize(bitmap);
}

pub fn main() !void {
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len != 2) {
        std.debug.print("usage: validate_wasm_interop <wasm-module-path>\n", .{});
        return error.InvalidArguments;
    }

    const wasm_path = args[1];
    const fixture_path = ".zig-cache/rawr_wasm_fixture.bin";
    const native_input_path = ".zig-cache/rawr_native_input.bin";
    const roundtrip_path = ".zig-cache/rawr_wasm_roundtrip.bin";

    // A) rawr(wasm) bytes -> CRoaring(native) parse/validate
    try runNode(&.{ "node", "scripts/wasm_interop_runner.mjs", wasm_path, "fixture", fixture_path });

    const wasm_fixture_bytes = try readFile(fixture_path);
    defer allocator.free(wasm_fixture_bytes);

    const cr_from_wasm = c.roaring_bitmap_portable_deserialize_safe(@ptrCast(wasm_fixture_bytes.ptr), wasm_fixture_bytes.len) orelse {
        return error.CRoaringFailedToParseWasmBytes;
    };
    defer c.roaring_bitmap_free(cr_from_wasm);

    const expected_fixture = c.roaring_bitmap_create() orelse return error.CRoaringAllocFailed;
    defer c.roaring_bitmap_free(expected_fixture);
    buildFixtureCR(expected_fixture);

    if (!equalBitmaps(cr_from_wasm, expected_fixture)) {
        return error.WasmToCRoaringMismatch;
    }

    // B) CRoaring(native) bytes -> rawr(wasm) parse/validate
    const native_input = c.roaring_bitmap_create() orelse return error.CRoaringAllocFailed;
    defer c.roaring_bitmap_free(native_input);
    buildNativeInputCR(native_input);

    const native_input_bytes = try serializeCR(native_input);
    defer allocator.free(native_input_bytes);
    try writeFile(native_input_path, native_input_bytes);

    try runNode(&.{ "node", "scripts/wasm_interop_runner.mjs", wasm_path, "roundtrip", native_input_path, roundtrip_path });

    const wasm_roundtrip_bytes = try readFile(roundtrip_path);
    defer allocator.free(wasm_roundtrip_bytes);

    const cr_after_wasm = c.roaring_bitmap_portable_deserialize_safe(@ptrCast(wasm_roundtrip_bytes.ptr), wasm_roundtrip_bytes.len) orelse {
        return error.CRoaringFailedToParseWasmRoundtripBytes;
    };
    defer c.roaring_bitmap_free(cr_after_wasm);

    if (!equalBitmaps(native_input, cr_after_wasm)) {
        return error.CRoaringToWasmMismatch;
    }

    std.debug.print("PASS: wasm/native rawr<->CRoaring interop\n", .{});
    std.debug.print("  A) wasm rawr -> CRoaring validated\n", .{});
    std.debug.print("  B) CRoaring -> wasm rawr validated\n", .{});
}
