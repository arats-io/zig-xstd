const std = @import("std");
const builtin = @import("builtin");

const assert = std.debug.assert;

const Self = @This();
pub const Error = error{
    InvalidRange,
} || std.mem.Allocator.Error;

allocator: std.mem.Allocator,

ptr: [*]u8,

cap: usize = 0,
len: usize = 0,
factor: u4,

pub fn initWithFactor(allocator: std.mem.Allocator, factor: u4) Self {
    return Self{
        .ptr = &[_]u8{},
        .allocator = allocator,
        .cap = 0,
        .len = 0,
        .factor = if (factor <= 0) 1 else factor,
    };
}

pub fn init(allocator: std.mem.Allocator) Self {
    return initWithFactor(allocator, 1);
}

pub fn deinit(self: *Self) void {
    self.allocator.free(self.ptr[0..self.cap]);
    self.ptr = &[_]u8{};
    self.len = 0;
    self.cap = 0;
}

pub fn resize(self: *Self, cap: usize) !void {
    const new_source = try self.allocator.realloc(self.ptr[0..self.cap], cap);
    self.ptr = new_source.ptr;
    self.cap = new_source.len;
    if (self.len > cap) {
        self.len = new_source.len;
    }
}

pub fn shrink(self: *Self) !void {
    try self.resize(self.len);
}

pub fn writeByte(self: *Self, byte: u8) !void {
    if (self.len + 1 > self.cap) {
        try self.resize((self.len + 1) * self.factor);
    }

    self.ptr[self.len] = byte;

    self.len += 1;
}

pub fn writeBytes(self: *Self, reader: anytype, max_num: usize) !void {
    for (0..max_num) |_| {
        const byte = try reader.readByte();
        try self.writeByte(byte);
    }
}

pub fn writeAll(self: *Self, array: []const u8) !void {
    _ = try self.write(array);
}

pub fn write(self: *Self, array: []const u8) !usize {
    if (array.len == 0) return 0;

    if (self.len + array.len > self.cap) {
        try self.resize((self.len + array.len) * self.factor);
    }

    var i: usize = 0;
    while (i < array.len) : (i += 1) {
        self.ptr[self.len + i] = array[i];
    }

    self.len += array.len;

    return array.len;
}

pub fn print(self: *Self, comptime format: []const u8, args: anytype) !void {
    const writer = self.writer();
    return std.fmt.format(writer, format, args);
}

pub fn read(self: *Self, dst: []u8) !usize {
    const size = if (self.len < dst.len) self.len else dst.len;
    _copy(u8, dst, self.ptr[0..size]);
    return size;
}

pub fn compare(self: *Self, array: []const u8) bool {
    return std.mem.eql(u8, self.ptr[0..self.len], array.ptr[0..array.len]);
}

pub fn bytes(self: *Self) []const u8 {
    return self.ptr[0..self.len];
}

pub fn byteAt(self: *Self, index: usize) !u8 {
    if (index < self.len) {
        return self.ptr[index];
    }
    return Error.InvalidRange;
}

pub fn rangeBytes(self: *Self, start: usize, end: usize) ![]const u8 {
    if (start < self.len and end <= self.len and start < end) {
        return self.ptr[start..end];
    }
    return Error.InvalidRange;
}

pub fn fromBytes(self: *Self, start: usize) ![]const u8 {
    if (start < self.len) {
        return self.ptr[start..self.len];
    }
    return Error.InvalidRange;
}

pub fn uptoBytes(self: *Self, end: usize) ![]const u8 {
    if (end < self.len) {
        return self.ptr[0..end];
    }
    return Error.InvalidRange;
}

pub fn clone(self: *Self) !Self {
    return self.cloneUsingAllocator(self.allocator);
}

pub fn cloneUsingAllocator(self: *Self, allocator: std.mem.Allocator) !Self {
    var buf = init(allocator);
    errdefer buf.deinit();

    _ = try buf.write(self.ptr[0..self.len]);
    return buf;
}

pub fn copy(self: *Self) ![]u8 {
    return self.copyUsingAllocator(self.allocator);
}

pub fn copyUsingAllocator(self: *Self, allocator: std.mem.Allocator) ![]u8 {
    const new_str = try allocator.alloc(u8, self.len);
    _copy(u8, new_str, self.ptr[0..self.len]);
    return new_str;
}

pub fn repeat(self: *Self, n: usize) !void {
    try self.resize(self.cap * (n + 1));

    var i: usize = 1;
    while (i <= n) : (i += 1) {
        var j: usize = 0;
        while (j < self.len) : (j += 1) {
            self.ptr[((i * self.len) + j)] = self.ptr[j];
        }
    }

    self.len *= (n + 1);
}

pub fn isEmpty(self: *Self) bool {
    return self.len == 0;
}

pub fn clear(self: *Self) void {
    @memset(self.ptr[0..self.len], 0);
    self.len = 0;
}

fn _copy(comptime Type: type, dest: []Type, src: []const Type) void {
    assert(dest.len >= src.len);

    if (@intFromPtr(src.ptr) == @intFromPtr(dest.ptr) or src.len == 0) return;

    const input: []const u8 = std.mem.sliceAsBytes(src);
    const output: []u8 = std.mem.sliceAsBytes(dest);

    assert(input.len > 0);
    assert(output.len > 0);

    const is_input_or_output_overlaping = (@intFromPtr(input.ptr) < @intFromPtr(output.ptr) and
        @intFromPtr(input.ptr) + input.len > @intFromPtr(output.ptr)) or
        (@intFromPtr(output.ptr) < @intFromPtr(input.ptr) and
        @intFromPtr(output.ptr) + output.len > @intFromPtr(input.ptr));

    if (is_input_or_output_overlaping) {
        @memcpy(output, input);
    } else {
        std.mem.copyBackwards(u8, output, input);
    }
}

// Reader and Writer functionality.
pub usingnamespace struct {
    pub const Writer = std.io.Writer(*Self, Error, appendWrite);
    pub const Reader = std.io.GenericReader(*Self, Error, readFn);

    pub fn reader(self: *Self) Reader {
        return .{ .context = self };
    }

    fn readFn(self: *Self, m: []u8) !usize {
        return try self.read(m);
    }

    pub fn writer(self: *Self) Writer {
        return .{ .context = self };
    }

    fn appendWrite(self: *Self, m: []const u8) !usize {
        return try self.write(m);
    }
};

// Iterator support
pub usingnamespace struct {
    pub const Iterator = struct {
        sb: *Self,
        index: usize,

        pub fn next(it: *Iterator) ?[]const u8 {
            if (it.index >= it.sb.len) return null;
            const i = it.index;
            return it.sb.ptr[i..it.index];
        }

        pub fn nextBytes(it: *Iterator, size: usize) ?[]const u8 {
            if ((it.index + size) >= it.sb.len) return null;

            const i = it.index;
            it.index += size;
            return it.sb.ptr[i..it.index];
        }
    };

    pub fn iterator(self: *Self) Iterator {
        return Iterator{
            .sb = self,
            .index = 0,
        };
    }
};
