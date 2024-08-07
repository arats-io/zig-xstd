const std = @import("std");
const zuffy = @import("zuffy");
const build_options = @import("build_options");

const Utf8Buffer = zuffy.bytes.Utf8Buffer;
const Buffer = zuffy.bytes.Buffer;
const GenericPool = zuffy.pool.Generic;

const zlog = zuffy.zlog;

const Error = error{OutOfMemoryClient};

const Element = struct {
    int: i32,
    string: []const u8,
    elem: ?*const Element = null,
};

const NewUtf8Buffer = struct {
    fn f(allocator: std.mem.Allocator) Utf8Buffer {
        return Utf8Buffer.init(allocator);
    }
}.f;

pub fn main() !void {
    std.debug.print("Starting application.\n", .{});

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const pool = GenericPool(Utf8Buffer).init(arena.allocator(), NewUtf8Buffer);
    defer pool.deinit();
    errdefer pool.deinit();

    const logger = zlog.initWithPool(arena.allocator(), &pool, .{
        .level = zlog.Level.ParseString("trace"),
        .format = .json,
        .caller_enabled = true,
        .caller_field_name = "caller",
        .time_enabled = true,
        .time_measure = .nanos,
        .time_formating = .pattern,
        .time_pattern = "YYYY MMM Do ddd HH:mm:ss.SSS UTCZZZ - Qo",
        .escape_enabled = true,
        .stacktrace_enabled = true,
    });
    errdefer logger.deinit();
    defer logger.deinit();

    try logger.With(.{
        zlog.Field(std.SemanticVersion, "version", build_options.semver),
    });

    const cache_logger = try logger.Scope(.cache);
    errdefer cache_logger.deinit();
    defer cache_logger.deinit();

    const max = std.math.maxInt(u18);
    var m: i128 = 0;
    const start = std.time.nanoTimestamp();

    const value_database = "my\"db";
    for (0..max) |idx| {
        var startTime = std.time.nanoTimestamp();

        try logger.Trace(
            "Initial\"ization...",
            .{
                zlog.Source(@src()),
                zlog.Field([]const u8, "database", value_database),
                zlog.Field(usize, "counter", idx),
                zlog.Field(?[]const u8, "attribute-null", null),
                zlog.Field([4]i32, "array", [_]i32{ 1, 2, 3, 4 }),
                zlog.Field([2]Element, "array_elements", [_]Element{
                    Element{ .int = 32, .string = "Eleme\"nt1" },
                    Element{ .int = 32, .string = "Eleme\"nt2" },
                }),
                zlog.Field([3]?[]const u8, "array_strings", [_]?[]const u8{
                    "eleme\"nt 1",
                    "eleme\"nt 2",
                    null,
                }),
                zlog.Field(Element, "element1", Element{ .int = 32, .string = "Eleme\"nt1" }),
            },
        );

        m += (std.time.nanoTimestamp() - startTime);

        startTime = std.time.nanoTimestamp();
        try logger.Debug(
            "Initialization...",
            .{
                zlog.Source(@src()),
                zlog.Field([]const u8, "database", value_database),
                zlog.Field(usize, "counter", idx),
                zlog.Field(?[]const u8, "attribute-null", null),
                zlog.Field(Element, "element1", Element{ .int = 32, .string = "Element1" }),
            },
        );
        m += (std.time.nanoTimestamp() - startTime);

        startTime = std.time.nanoTimestamp();
        try logger.Info(
            "Initialization...",
            .{
                zlog.Source(@src()),
                zlog.Field([]const u8, "database", value_database),
                zlog.Field(usize, "counter", idx),
                zlog.Field(?[]const u8, "attribute-null", null),
                zlog.Field(Element, "element1", Element{ .int = 32, .string = "Element1" }),
            },
        );
        m += (std.time.nanoTimestamp() - startTime);

        startTime = std.time.nanoTimestamp();
        try logger.Warn(
            "Initialization...",
            .{
                zlog.Source(@src()),
                zlog.Field([]const u8, "database", value_database),
                zlog.Field(usize, "counter", idx),
                zlog.Field(?[]const u8, "attribute-null", null),
                zlog.Field(Element, "element1", Element{ .int = 32, .string = "Element1" }),
            },
        );
        m += (std.time.nanoTimestamp() - startTime);

        startTime = std.time.nanoTimestamp();
        try logger.Error(
            "Initialization...",
            Error.OutOfMemoryClient,
            .{
                zlog.Source(@src()),
                zlog.Field([]const u8, "database", value_database),
                zlog.Field(usize, "counter", idx),
                zlog.Field(?[]const u8, "attribute-null", null),
                zlog.Field(Element, "element1", Element{ .int = 32, .string = "Element1" }),
            },
        );
        m += (std.time.nanoTimestamp() - startTime);

        startTime = std.time.nanoTimestamp();
        try cache_logger.Error(
            "Initialization...",
            Error.OutOfMemoryClient,
            .{
                zlog.Source(@src()),
                zlog.Field([]const u8, "database", value_database),
                zlog.Field(usize, "counter", idx),
                zlog.Field(?[]const u8, "attribute-null", null),
                zlog.Field(Element, "element1", Element{ .int = 32, .string = "Element1" }),
            },
        );
        m += (std.time.nanoTimestamp() - startTime);
    }

    std.debug.print("\n----------------------------------------------------------------------------", .{});
    const total = max * 6;
    std.debug.print("\n\nProcessed {} records in {} micro; Average time spent on log report is {} micro.\n\n", .{ total, (std.time.nanoTimestamp() - start), @divFloor(m, total) });
}
