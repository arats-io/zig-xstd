const std = @import("std");

const GenericPool = @import("../pool/mod.zig").Generic;
const Utf8Buffer = @import("../bytes/mod.zig").Utf8Buffer;

const Time = @import("../time/mod.zig").Time;
const Local = @import("../time/mod.zig").zoneinfo.Local;
const Measure = @import("../time/mod.zig").Measure;

const local = Local.Get();
const default_caller_marshal_fn = struct {
    fn handler(src: std.builtin.SourceLocation) []const u8 {
        var buf: [10 * 1024]u8 = undefined;
        const data = std.fmt.bufPrint(&buf, "{s}:{}", .{ src.file, src.line }) catch "";
        return data[0..];
    }
}.handler;

pub const InternalFailure = enum {
    nothing,
    panic,
    print,
};

pub const TimeFormating = enum(u4) {
    timestamp = 0,
    pattern = 1,
};

pub const Format = enum(u4) {
    simple = 0,
    json = 1,
};

pub const Level = enum(u4) {
    Trace = 0x0,
    Debug = 0x1,
    Info = 0x2,
    Warn = 0x3,
    Error = 0x4,
    Fatal = 0x5,
    Disabled = 0xF,

    pub fn String(self: Level) []const u8 {
        return switch (self) {
            .Trace => "trace",
            .Debug => "debug",
            .Info => "info",
            .Warn => "warn",
            .Error => "error",
            .Fatal => "fatal",
            .Disabled => "disabled",
        };
    }
    pub fn ParseString(val: []const u8) Level {
        var buffer: [8]u8 = undefined;
        const lVal = std.ascii.lowerString(&buffer, val);

        if (std.mem.eql(u8, "trace", lVal)) return .Trace;
        if (std.mem.eql(u8, "debug", lVal)) return .Debug;
        if (std.mem.eql(u8, "info", lVal)) return .Info;
        if (std.mem.eql(u8, "warn", lVal)) return .Warn;
        if (std.mem.eql(u8, "error", lVal)) return .Error;
        if (std.mem.eql(u8, "fatal", lVal)) return .Fatal;
        if (std.mem.eql(u8, "disabled", lVal)) return .Disabled;
        return .Disabled;
    }
};

/// Logger configuration options
pub const Options = struct {
    /// log level, possible values (Trace | Debug | Info | Warn | Error | Fatal | Disabled)
    level: Level = Level.Info,
    /// field name for the log level
    level_field_name: []const u8 = "level",

    /// format for writing logs, possible values (json | simple)
    format: Format = Format.json,

    /// time related configuration options
    /// flag enabling/disabling the time  for each log record
    time_enabled: bool = false,
    /// field name for the time
    time_field_name: []const u8 = "time",
    /// time measumerent, possible values (seconds | millis | micros, nanos)
    time_measure: Measure = Measure.seconds,
    /// time formating, possible values (timestamp | pattern)
    time_formating: TimeFormating = TimeFormating.timestamp,
    /// petttern of time representation, applicable when .time_formating is sen on .pattern
    time_pattern: []const u8 = "DD/MM/YYYY'T'HH:mm:ss",

    /// field name for the message
    message_field_name: []const u8 = "message",
    /// field name for the error
    error_field_name: []const u8 = "error",

    /// indicator what to do in case is there is a error occuring inside of logger, possible values as doing (nothing | panic | print)
    internal_failure: InternalFailure = InternalFailure.nothing,

    /// caller related configuration options
    /// flag enabling/disabling the caller reporting in the log
    caller_enabled: bool = false,
    /// field name for the caller source
    caller_field_name: []const u8 = "caller",
    /// handler processing the source object data
    caller_marshal_fn: *const fn (std.builtin.SourceLocation) []const u8 = default_caller_marshal_fn,

    /// struct marchalling to string options
    struct_union: StructUnionOptions = StructUnionOptions{},
};

/// struct marchalling to string options
pub const StructUnionOptions = struct {
    // flag enabling/disabling the escapping for marchalled structs
    // searching for \" and replacing with \\\" as per default values
    escape_enabled: bool = false,
    src_escape_characters: []const u8 = "\"",
    dst_escape_characters: []const u8 = "\\\"",
};

pub const Logger = struct {
    allocator: std.mem.Allocator,
    buffer_pool: ?*const GenericPool(Utf8Buffer),
    options: Options,

    pub fn init(allocator: std.mem.Allocator, options: Options) !Logger {
        return .{
            .allocator = allocator,
            .buffer_pool = null,
            .options = options,
        };
    }

    pub fn initWithPool(allocator: std.mem.Allocator, buffer_pool: *const GenericPool(Utf8Buffer), options: Options) !Logger {
        return .{
            .allocator = allocator,
            .buffer_pool = buffer_pool,
            .options = options,
        };
    }

    inline fn entry(self: Logger, comptime op: Level) Entry {
        return Entry.init(
            self.allocator,
            if (self.buffer_pool) |pool| pool else null,
            op,
            if (@intFromEnum(self.options.level) > @intFromEnum(op)) null else self.options,
        );
    }

    pub fn Trace(self: Logger) Entry {
        return self.entry(Level.Trace);
    }
    pub fn Debug(self: Logger) Entry {
        return self.entry(Level.Debug);
    }
    pub fn Info(self: Logger) Entry {
        return self.entry(Level.Info);
    }
    pub fn Warn(self: Logger) Entry {
        return self.entry(Level.Warn);
    }
    pub fn Error(self: Logger) Entry {
        return self.entry(Level.Error);
    }
    pub fn Fatal(self: Logger) Entry {
        return self.entry(Level.Fatal);
    }

    pub const Entry = struct {
        const Self = @This();

        allocator: std.mem.Allocator,
        options: ?Options = null,
        opLevel: Level = .Disabled,

        pool: ?*const GenericPool(Utf8Buffer),
        data: Utf8Buffer,

        fn init(allocator: std.mem.Allocator, pool: ?*const GenericPool(Utf8Buffer), opLevel: Level, options: ?Options) Self {
            var data = if (pool) |p| p.pop() else Utf8Buffer.initWithFactor(allocator, 10);
            if (options) |opts| {
                switch (opts.format) {
                    inline .simple => {
                        if (opts.time_enabled) {
                            const t = Time.new(opts.time_measure);
                            switch (opts.time_formating) {
                                .timestamp => {
                                    data.appendf("{}", .{t.value}) catch |err| {
                                        failureFn(opts.internal_failure, "Failed to include the datainto the log buffer; {}", .{err});
                                    };
                                },
                                .pattern => {
                                    var buffer: [1024]u8 = undefined;
                                    const len = t.formatfInto(allocator, opts.time_pattern, &buffer) catch |err| blk: {
                                        failureFn(opts.internal_failure, "Failed to include the datainto the log buffer; {}", .{err});
                                        break :blk 0;
                                    };
                                    data.appendf("{s}=\u{0022}{s}\u{0022} ", .{ opts.time_field_name, buffer[0..len] }) catch |err| {
                                        failureFn(opts.internal_failure, "Failed to include the datainto the log buffer; {}", .{err});
                                    };
                                },
                            }
                        }
                        data.appendf(" {s}", .{opLevel.String().ptr[0..4]}) catch |err| {
                            failureFn(opts.internal_failure, "Failed to insert and unicode code \u{0022}; {}", .{err});
                        };
                    },
                    inline .json => {
                        data.append("{") catch |err| {
                            failureFn(opts.internal_failure, "Failed to include the datainto the log buffer; {}", .{err});
                        };
                        if (opts.time_enabled) {
                            const t = Time.new(opts.time_measure);

                            switch (opts.time_formating) {
                                .timestamp => {
                                    data.appendf("\u{0022}{s}\u{0022}:{}, ", .{ opts.time_field_name, t.value }) catch |err| {
                                        failureFn(opts.internal_failure, "Failed to include the datainto the log buffer; {}", .{err});
                                    };
                                },
                                .pattern => {
                                    var buffer: [1024]u8 = undefined;
                                    const len = t.formatfInto(allocator, opts.time_pattern, &buffer) catch |err| blk: {
                                        failureFn(opts.internal_failure, "Failed to include the datainto the log buffer; {}", .{err});
                                        break :blk 0;
                                    };
                                    data.appendf("\u{0022}{s}\u{0022}: \u{0022}{s}\u{0022}, ", .{ opts.time_field_name, buffer[0..len] }) catch |err| {
                                        failureFn(opts.internal_failure, "Failed to include the datainto the log buffer; {}", .{err});
                                    };
                                },
                            }
                        }
                        data.appendf("\u{0022}{s}\u{0022}: \u{0022}{s}\u{0022}", .{ opts.level_field_name, opLevel.String() }) catch |err| {
                            failureFn(opts.internal_failure, "Failed to include the datainto the log buffer; {}", .{err});
                        };
                    },
                }
            }
            return Self{
                .allocator = allocator,
                .options = options,
                .opLevel = opLevel,
                .pool = if (pool) |p| p else null,
                .data = data,
            };
        }

        pub fn deinit(self: *Self) void {
            if (self.pool) |pool| {
                self.data.clear();
                pool.push(&self.data) catch |err| {
                    std.debug.print("Error - {any}", .{err});
                };
            } else {
                self.data.deinit();
            }
        }

        pub fn Attr(self: *Self, key: []const u8, value: anytype) *Self {
            if (self.options) |options| {
                const T = @TypeOf(value);
                const ty = @typeInfo(T);

                switch (ty) {
                    .ErrorUnion => {
                        if (value) |payload| {
                            return self.Attr(key, payload);
                        } else |err| {
                            return self.Attr(key, err);
                        }
                    },
                    .Type => {
                        return self.Attr(key, @typeName(value));
                    },
                    .EnumLiteral => {
                        const buffer = [_]u8{'.'} ++ @tagName(value);
                        return self.Attr(key, buffer);
                    },
                    .Void => {
                        return self.Attr(key, "void");
                    },
                    .Optional => {
                        if (value) |payload| {
                            return self.Attr(key, payload);
                        } else {
                            return self.Attr(key, null);
                        }
                    },
                    .Fn => {
                        return self;
                    },
                    else => {},
                }

                switch (options.format) {
                    inline .simple => {
                        switch (ty) {
                            .Enum => self.data.appendf(" {s}=\u{0022}{s}\u{0022}", .{ key, @typeName(value) }) catch |err| {
                                failureFn(options.internal_failure, "Failed to consider attribute {s}:{s}; {}", .{ key, @typeName(value), err });
                            },
                            .Bool => self.data.appendf(" {s}=\u{0022}{s}\u{0022}", .{ key, if (value) "true" else "false" }) catch |err| {
                                failureFn(options.internal_failure, "Failed to consider attribute {s}:{}; {}", .{ key, value, err });
                            },
                            .Pointer => |ptr_info| switch (ptr_info.size) {
                                .Slice => self.data.appendf(" {s}=\u{0022}{s}\u{0022}", .{ key, value }) catch |err| {
                                    failureFn(options.internal_failure, "Failed to consider attribute {s}:{s}; {}", .{ key, value, err });
                                },
                                else => {},
                            },
                            .ComptimeInt, .Int, .ComptimeFloat, .Float => self.data.appendf(" {s}={}", .{ key, value }) catch |err| {
                                failureFn(options.internal_failure, "Failed to consider attribute {s}:{}; {}", .{ key, value, err });
                            },
                            .ErrorSet => self.data.appendf(" {s}=\u{0022}{s}\u{0022}", .{ options.error_field_name, @errorName(value) }) catch |err| {
                                failureFn(options.internal_failure, "Failed to consider attribute {s}:{s}; {}", .{ options.error_field_name, value, err });
                            },
                            .Null => self.data.appendf(" {s}=null", .{key}) catch |err| {
                                failureFn(options.internal_failure, "Failed to consider attribute {s}:null; {}", .{ key, err });
                            },
                            .Struct, .Union => {
                                if (options.struct_union.escape_enabled) {
                                    self.data.appendf(" {s}=\u{0022}", .{key}) catch |err| {
                                        failureFn(options.internal_failure, "Failed to consider struct json  attribute {s}; {}", .{ key, err });
                                    };
                                } else {
                                    self.data.appendf(" {s}=", .{key}) catch |err| {
                                        failureFn(options.internal_failure, "Failed to consider struct json  attribute {s}; {}", .{ key, err });
                                    };
                                }

                                const cPos = self.data.length();
                                std.json.stringifyMaxDepth(value, .{}, self.data.writer(), std.math.maxInt(u16)) catch |err| {
                                    failureFn(options.internal_failure, "Failed to consider attribute {s}:{}; {}", .{ key, value, err });
                                };

                                if (options.struct_union.escape_enabled) {
                                    _ = self.data.replaceAllFromPos(
                                        cPos,
                                        options.struct_union.src_escape_characters,
                                        options.struct_union.dst_escape_characters,
                                    ) catch |err| {
                                        failureFn(options.internal_failure, "Failed to consider attribute {s}:{}; {}", .{ key, value, err });
                                    };
                                }

                                if (options.struct_union.escape_enabled) {
                                    self.data.appendf("\u{0022}", .{}) catch |err| {
                                        failureFn(options.internal_failure, "Failed to consider struct json attribute {s}; {}", .{ key, err });
                                    };
                                }
                            },
                            else => self.data.appendf(" {s}=\u{0022}{}\u{0022}", .{ key, value }) catch |err| {
                                failureFn(options.internal_failure, "Failed to consider attribute {s}:{}; {}", .{ key, value, err });
                            },
                        }
                    },
                    inline .json => {
                        switch (ty) {
                            .Enum => self.data.appendf(", \u{0022}{s}\u{0022}: \u{0022}{s}\u{0022}", .{ key, @typeName(value) }) catch |err| {
                                failureFn(options.internal_failure, "Failed to consider attribute {s}:{s}; {}", .{ key, @typeName(value), err });
                            },
                            .Bool => self.data.appendf(", \u{0022}{s}\u{0022}: {s}", .{ key, if (value) "true" else "false" }) catch |err| {
                                failureFn(options.internal_failure, "Failed to consider attribute {s}:{}; {}", .{ key, value, err });
                            },
                            .Pointer => |ptr_info| switch (ptr_info.size) {
                                .Slice, .Many, .One, .C => self.data.appendf(", \u{0022}{s}\u{0022}: \u{0022}{s}\u{0022}", .{ key, value }) catch |err| {
                                    failureFn(options.internal_failure, "Failed to consider attribute {s}:{s}; {}", .{ key, value, err });
                                },
                            },
                            .ComptimeInt, .Int, .ComptimeFloat, .Float => self.data.appendf(", \u{0022}{s}\u{0022}:{}", .{ key, value }) catch |err| {
                                failureFn(options.internal_failure, "Failed to consider attribute {s}:{}; {}", .{ key, value, err });
                            },
                            .ErrorSet => self.data.appendf(", \u{0022}{s}\u{0022}: \u{0022}{s}\u{0022}", .{ key, @errorName(value) }) catch |err| {
                                failureFn(options.internal_failure, "Failed to consider attribute {s}:{}; {}", .{ key, value, err });
                            },
                            .Null => self.data.appendf(", \u{0022}{s}\u{0022}:null", .{key}) catch |err| {
                                failureFn(options.internal_failure, "Failed to consider attribute {s}:null; {}", .{ key, err });
                            },
                            .Struct, .Union => {
                                self.data.appendf(", \u{0022}{s}\u{0022}:", .{key}) catch |err| {
                                    failureFn(options.internal_failure, "Failed to consider attribute {s}; {}", .{ key, err });
                                };

                                std.json.stringifyMaxDepth(value, .{}, self.data.writer(), std.math.maxInt(u16)) catch |err| {
                                    failureFn(options.internal_failure, "Failed to consider attribute {s}:{}; {}", .{ key, value, err });
                                };
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
                _ = self.Attr(options.error_field_name, @errorName(value));
            }
            return self;
        }

        pub fn Source(self: *Self, src: std.builtin.SourceLocation) *Self {
            if (self.options) |options| {
                if (options.caller_enabled) {
                    const data = options.caller_marshal_fn(src);
                    return self.Attr(options.caller_field_name[0..], data);
                }
            }

            return self;
        }

        pub fn Message(self: *Self, message: []const u8) *Self {
            if (self.options) |options| {
                _ = self.Attr(options.message_field_name, message);
            }
            return self;
        }

        pub fn SendWriter(self: *Self, writer: anytype) !void {
            defer self.deinit();
            errdefer self.deinit();

            if (self.options) |options| {
                switch (options.format) {
                    inline .simple => {
                        try self.data.append("\n");
                    },
                    inline .json => {
                        try self.data.append("}\n");
                    },
                }

                _ = try writer.write(self.data.bytes());

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
};
