const std = @import("std");
const zuffy = @import("zuffy");

const Allocator = std.mem.Allocator;
const AllocatorError = std.mem.Allocator.Error;

const Utf8Buffer = zuffy.bytes.Utf8Buffer;

const GenericPool = zuffy.pool.Generic;

const assert = std.debug.assert;

pub fn main() !void {
    std.debug.print("Starting application.\n", .{});

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const NewUtf8Buffer = struct {
        fn f(allocator: std.mem.Allocator) Utf8Buffer {
            return Utf8Buffer.init(allocator);
        }
    }.f;

    const utf8BufferPool = GenericPool(Utf8Buffer).initFixed(arena.allocator(), NewUtf8Buffer);
    defer utf8BufferPool.deinit();

    {
        var sb10 = utf8BufferPool.pop();
        assert(sb10.rawLength() == 0);

        try sb10.append("💯Hello💯");
        assert(sb10.compare("💯Hello💯"));

        try utf8BufferPool.push(&sb10);
    }

    var sb11 = utf8BufferPool.pop();
    assert(sb11.compare("💯Hello💯"));

    var sb21 = utf8BufferPool.pop();
    try sb21.append("💯Hello2💯");
    assert(sb21.compare("💯Hello2💯"));

    try utf8BufferPool.push(&sb21);
    try utf8BufferPool.push(&sb11);

    {
        var sb12 = utf8BufferPool.pop();
        assert(sb12.compare("💯Hello💯"));
    }

    {
        var sb22 = utf8BufferPool.pop();
        assert(sb22.compare("💯Hello2💯"));
    }
}
