const std = @import("std");
const zuffy = @import("zuffy");

const StringBuilder = zuffy.bytes.StringBuilder;
const Utf8Buffer = zuffy.bytes.Utf8Buffer;
const Buffer = zuffy.bytes.Buffer;

const zlog = zuffy.zlog;

const Time = zuffy.time.Time;

const Error = error{OutOfMemoryClient};

const Element = struct {
    int: i32,
    string: []const u8,
    elem: ?*const Element = null,
};

pub fn main() !void {
    std.debug.print("Starting application.\n", .{});

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const logger = zlog.init(arena.allocator(), .{
        .level = zlog.Level.ParseString("trace"),
        .format = .text,
        .caller_enabled = true,
        .caller_field_name = "caller",
        .time_enabled = true,
        .time_measure = .nanos,
        .time_formating = .pattern,
        .time_pattern = "YYYY MMM Do ddd HH:mm:ss.SSS UTCZZZ - Qo",
        .escape_enabled = true,
        .stacktrace_enabled = true,
    });
    defer logger.deinit();

    const max = std.math.maxInt(u18);
    var m: i128 = 0;
    const start = std.time.nanoTimestamp();
    const value_database = "my\"db";
    for (0..max) |idx| {
        var startTime = std.time.nanoTimestamp();
        try logger.Trace(
            "Initia\"ization...",
            .{
                zlog.Source(@src()),
                zlog.Field([]const u8, "database", value_database),
                zlog.Field(usize, "counter", idx),
                zlog.Field(?[]const u8, "attribute-null", null),
                zlog.Field([4]i32, "array", [_]i32{ 1, 2, 3, 4 }),
                zlog.Field([2]Element, "array_elements", [_]Element{
                    Element{ .int = 32, .string = "Elem\"ent1" },
                    Element{ .int = 32, .string = "Elem\"ent2" },
                }),
                zlog.Field([2][]const u8, "array_strings", [_][]const u8{
                    "eleme\"nt 1",
                    "eleme\"nt 2",
                }),
                zlog.Field(Element, "element1", Element{ .int = 32, .string = "Ele\"ent1" }),
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
    }

    std.debug.print("\n----------------------------------------------------------------------------", .{});
    const total = max * 5;
    std.debug.print("\n\nProcessed {} records in {} micro; Average time spent on log report is {} micro.\n\n", .{ total, (std.time.nanoTimestamp() - start), @divFloor(m, total) });
}
