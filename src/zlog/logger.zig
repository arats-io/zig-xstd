const std = @import("std");

const Buffer = @import("../bytes/mod.zig").Buffer;
const Utf8Buffer = @import("../bytes/mod.zig").Utf8Buffer;

const Time = @import("../time/mod.zig").Time;
const Local = @import("../time/mod.zig").zoneinfo.Local;
const Measure = @import("../time/mod.zig").Measure;

const TimeFormating = @import("common.zig").TimeFormating;
const Format = @import("common.zig").Format;
const Level = @import("common.zig").Level;
const InternalFailure = @import("common.zig").InternalFailure;

const default_caller_marshal_fn = struct {
    fn handler(src: std.builtin.SourceLocation) []const u8 {
        var buf: [10 * 1024]u8 = undefined;
        const data = std.fmt.bufPrint(&buf, "{s}:{}", .{ src.file, src.line }) catch "";
        return data[0..];
    }
}.handler;

const _ = Local.Get();

pub const Options = struct {
    level: Level = Level.Info,
    level_field_name: []const u8 = "level",

    format: Format = Format.simple,

    time_enabled: bool = false,
    time_field_name: []const u8 = "time",
    time_measure: Measure = Measure.seconds,
    time_formating: TimeFormating = TimeFormating.timestamp,
    time_pattern: []const u8 = "DD/MM/YYYY'T'HH:mm:ss",

    message_field_name: []const u8 = "message",
    error_field_name: []const u8 = "error",

    internal_failure: InternalFailure = InternalFailure.nothing,

    caller_enabled: bool = false,
    caller_field_name: []const u8 = "caller",
    caller_marshal_fn: *const fn (std.builtin.SourceLocation) []const u8 = default_caller_marshal_fn,
};

pub const Logger = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    options: Options,

    pub fn init(allocator: std.mem.Allocator, options: Options) Self {
        return Self{
            .allocator = allocator,
            .options = options,
        };
    }

    inline fn entry(self: Self, comptime op: Level) Entry {
        return Entry.init(
            self.allocator,
            if (@intFromEnum(self.options.level) > @intFromEnum(op) or self.options.level == .Disabled) null else self.options,
            op,
        );
    }

    pub fn Trace(self: Self) Entry {
        return self.entry(Level.Trace);
    }
    pub fn Debug(self: Self) Entry {
        return self.entry(Level.Debug);
    }
    pub fn Info(self: Self) Entry {
        return self.entry(Level.Info);
    }
    pub fn Warn(self: Self) Entry {
        return self.entry(Level.Warn);
    }
    pub fn Error(self: Self) Entry {
        return self.entry(Level.Error);
    }
    pub fn Fatal(self: Self) Entry {
        return self.entry(Level.Fatal);
    }
    pub fn Disabled(self: Self) Entry {
        return self.entry(Level.Disabled);
    }
};

const Elem = struct {
    key: Utf8Buffer,
    value: Utf8Buffer,
};

pub const Entry = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    options: ?Options = null,
    opLevel: Level = .Disabled,

    data: Utf8Buffer,

    fn init(
        allocator: std.mem.Allocator,
        options: ?Options,
        opLevel: Level,
    ) Self {
        var self = Self{
            .allocator = allocator,
            .options = options,
            .opLevel = opLevel,
            .data = Utf8Buffer.init(allocator),
        };
        if (options) |opts| {
            self.data.append("{") catch |err| {
                failureFn(opts.internal_failure, "Failed to include the datainto the log buffer; {}", .{err});
            };
            switch (opts.format) {
                inline .simple => {
                    if (opts.time_enabled) {
                        const t = Time.new(opts.time_measure);
                        switch (opts.time_formating) {
                            .timestamp => {
                                self.data.appendf("{}", .{t.value}) catch |err| {
                                    failureFn(opts.internal_failure, "Failed to include the datainto the log buffer; {}", .{err});
                                };
                            },
                            .pattern => {
                                var buffer: [512]u8 = undefined;
                                const len = t.format(allocator, opts.time_pattern, &buffer) catch |err| blk: {
                                    failureFn(opts.internal_failure, "Failed to include the datainto the log buffer; {}", .{err});
                                    break :blk 0;
                                };
                                self.data.appendf("{s}", .{buffer[0..len]}) catch |err| {
                                    failureFn(opts.internal_failure, "Failed to include the datainto the log buffer; {}", .{err});
                                };
                            },
                        }
                    }
                    self.data.appendf(" {s}", .{opLevel.String().ptr[0..4]}) catch |err| {
                        failureFn(opts.internal_failure, "Failed to insert and unicode code \u{0022}; {}", .{err});
                    };
                },
                inline .json => {
                    if (opts.time_enabled) {
                        const t = Time.new(opts.time_measure);

                        switch (opts.time_formating) {
                            .timestamp => {
                                self.data.appendf("\u{0022}{s}\u{0022}:{}, ", .{ opts.time_field_name, t.value }) catch |err| {
                                    failureFn(opts.internal_failure, "Failed to include the datainto the log buffer; {}", .{err});
                                };
                            },
                            .pattern => {
                                var buffer: [1024]u8 = undefined;
                                const len = t.format(allocator, opts.time_pattern, &buffer) catch |err| blk: {
                                    failureFn(opts.internal_failure, "Failed to include the datainto the log buffer; {}", .{err});
                                    break :blk 0;
                                };
                                self.data.appendf("\u{0022}{s}\u{0022}: \u{0022}{s}\u{0022}, ", .{ opts.time_field_name, buffer[0..len] }) catch |err| {
                                    failureFn(opts.internal_failure, "Failed to include the datainto the log buffer; {}", .{err});
                                };
                            },
                        }
                    }
                    self.data.appendf("\u{0022}{s}\u{0022}: \u{0022}{s}\u{0022}", .{ opts.level_field_name, opLevel.String() }) catch |err| {
                        failureFn(opts.internal_failure, "Failed to include the datainto the log buffer; {}", .{err});
                    };
                },
            }
        }
        return self;
    }

    pub fn Attr(self: *Self, key: []const u8, comptime V: type, value: V) *Self {
        if (self.options) |options| {
            switch (options.format) {
                inline .simple => {
                    switch (@TypeOf(value)) {
                        []const u8 => self.data.appendf(" {s}=\u{0022}{s}\u{0022}", .{ key, value }) catch |err| {
                            failureFn(options.internal_failure, "Failed to consider attribute {s}:{s}; {}", .{ key, value, err });
                        },
                        else => self.data.appendf(" {s}=\u{0022}{}\u{0022}", .{ key, value }) catch |err| {
                            failureFn(options.internal_failure, "Failed to consider attribute {s}:{}; {}", .{ key, value, err });
                        },
                    }
                },
                inline .json => {
                    switch (@TypeOf(value)) {
                        []const u8 => self.data.appendf(", \u{0022}{s}\u{0022}: \u{0022}{s}\u{0022}", .{ key, value }) catch |err| {
                            failureFn(options.internal_failure, "Failed to consider attribute {s}:{s}; {}", .{ key, value, err });
                        },
                        else => self.data.appendf(", \u{0022}{s}\u{0022}: \u{0022}{}\u{0022}", .{ key, value }) catch |err| {
                            failureFn(options.internal_failure, "Failed to consider attribute {s}:{}; {}", .{ key, value, err });
                        },
                    }
                },
            }
        }

        return self;
    }

    pub fn Error(self: *Self, value: anyerror) *Self {
        if (self.options) |options| {
            _ = self.Attr(options.error_field_name, []const u8, @errorName(value));
        }
        return self;
    }

    pub fn Source(self: *Self, src: std.builtin.SourceLocation) *Self {
        if (self.options) |options| {
            if (options.caller_enabled) {
                const data = options.caller_marshal_fn(src);
                return self.Attr(options.caller_field_name[0..], []const u8, data);
            }
        }

        return self;
    }

    pub fn Message(self: *Self, message: []const u8) *Self {
        if (self.options) |options| {
            _ = self.Attr(options.message_field_name, []const u8, message);
        }
        return self;
    }

    pub fn SendWriter(self: *Self, writer: anytype) !void {
        var data = self.data;

        defer data.deinit();
        errdefer data.deinit();

        if (self.options) |options| {
            switch (options.format) {
                inline .simple => {
                    try data.append("\n");
                },
                inline .json => {
                    try data.append("}\n");
                },
            }

            _ = try writer.write(data.bytes());

            if (self.opLevel == .Fatal) {
                @panic("logger on fatal");
            }
        }
    }

    pub fn Send(self: *Self) !void {
        try self.SendStdOut();
    }

    pub fn SendStdOut(self: *Self) !void {
        try self.SendWriter(std.io.getStdOut().writer());
    }

    pub fn SendStdErr(self: *Self) !void {
        try self.SendWriter(std.io.getStdErr().writer());
    }

    pub fn SendStdIn(self: *Self) !void {
        try self.SendWriter(std.io.getStdIn().writer());
    }

    fn failureFn(on: InternalFailure, comptime format: []const u8, args: anytype) void {
        switch (on) {
            inline .panic => std.debug.panic(format, args),
            inline .print => std.debug.print(format, args),
            else => {},
        }
    }
};
