const std = @import("std");
const mem = std.mem;

pub inline fn toHexBytes(comptime T: type, case: std.fmt.Case, src: T) [@divExact(@typeInfo(T).Int.bits, 8) * 2]u8 {
    var srcBytes: [@divExact(@typeInfo(T).Int.bits, 8)]u8 = undefined;
    @as(*align(1) T, @ptrCast(&srcBytes)).* = src;
    return std.fmt.bytesToHex(srcBytes, case);
}

pub inline fn fromHexBytes(comptime R: type, endian: std.builtin.Endian, input: []const u8) !R {
    var srcBytes: [@divExact(@typeInfo(R).Int.bits, 8)]u8 = undefined;
    const result = try std.fmt.hexToBytes(&srcBytes, input);

    var s = std.io.fixedBufferStream(result);
    return s.reader().readInt(R, endian);
}

pub inline fn toBytes(comptime T: type, value: T, endian: std.builtin.Endian) []const u8 {
    var bytes: [@divExact(@typeInfo(T).Int.bits, 8)]u8 = undefined;
    mem.writeInt(T, &bytes, value, endian);
    return bytes;
}