const std = @import("std");
const xstd = @import("xstd");

const StringBuilder = xstd.bytes.StringBuilder;
const Utf8Buffer = xstd.bytes.Utf8Buffer;
const Buffer = xstd.bytes.Buffer;

const zlog = xstd.zlog;

const Time = xstd.time.Time;

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

    const logger = try zlog.Logger.init(arena.allocator(), .{
        .level = zlog.Level.ParseString("trace"),
        .format = zlog.Format.text,
        .caller_enabled = true,
        .caller_field_name = "caller",
        .time_enabled = true,
        .time_measure = .nanos,
        .time_formating = .pattern,
        .time_pattern = "YYYY MMM Do ddd HH:mm:ss.SSS UTCZZZ - Qo",
    });
    defer logger.deinit();

    const max = std.math.maxInt(u18);
    var m: i128 = 0;
    const start = std.time.nanoTimestamp();
    const value_database = "mydb";
    for (0..max) |idx| {
        var startTime = std.time.nanoTimestamp();
        logger.Trace(
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
        logger.Debug(
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
        logger.Info(
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
        logger.Warn(
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
        logger.Error(
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
