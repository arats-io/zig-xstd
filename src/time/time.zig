const std = @import("std");
const Utf8Buffer = @import("../bytes/mod.zig").Utf8Buffer;

pub const Measure = enum(u2) { seconds = 0, millis = 1, micros = 2, nanos = 3 };

pub const Month = enum(u4) {
    January = 1,
    February,
    March,
    April,
    May,
    June,
    July,
    August,
    September,
    October,
    November,
    December,

    pub fn string(self: Month) []const u8 {
        return @tagName(self);
    }

    pub fn shortString(self: Month) []const u8 {
        return @tagName(self)[0..3];
    }
};

pub const Weekday = enum(u3) {
    Monday = 1,
    Tuesday,
    Wednesday,
    Thursday,
    Friday,
    Saturday,
    Sunday,

    pub fn string(self: Weekday) []const u8 {
        return @tagName(self);
    }
    pub fn shortString(self: Weekday) []const u8 {
        return @tagName(self)[0..3];
    }

    pub fn shorterString(self: Weekday) []const u8 {
        return @tagName(self)[0..2];
    }
};

pub const DateTime = struct {
    year: u16,
    month: u5,
    yday: u9,
    wday: u3,
    day: u5,
    hour: u6,
    min: u6,
    sec: u6,
};

pub const Time = struct {
    const Self = @This();

    measure: Measure,
    value: i128,

    date_time: ?DateTime = null,
    offset: ?i32 = null,

    rest: u64 = 0,
    milli: u10 = 0,
    micro: u10 = 0,
    nano: u10 = 0,

    pub fn new(measure: Measure) Self {
        const t = @constCast(&Self{ .measure = measure, .value = switch (measure) {
            inline .seconds => std.time.timestamp(),
            inline .millis => std.time.milliTimestamp(),
            inline .micros => std.time.microTimestamp(),
            inline .nanos => std.time.nanoTimestamp(),
        } }).pupulate();
        return t.*;
    }

    fn dateTime(self: Self) DateTime {
        return self.date_time.?;
    }

    fn pupulate(self: *Self) *Self {
        const seconds = switch (self.measure) {
            inline .seconds => self.value,
            inline .millis => blk: {
                const milli = @rem(self.value, std.time.ms_per_s);
                @atomicStore(u10, @constCast(&self.milli), @as(u10, @intCast(milli)), .monotonic);
                @atomicStore(u64, @constCast(&self.rest), @as(u64, @intCast(milli)), .monotonic);

                break :blk @divTrunc(self.value, std.time.ms_per_s);
            },
            inline .micros => blk: {
                const micro = @rem(self.value, std.time.ns_per_us);
                @atomicStore(u10, @constCast(&self.micro), @as(u10, @intCast(micro)), .monotonic);

                var milli = @rem(self.value, std.time.us_per_s);
                @atomicStore(u64, @constCast(&self.rest), @as(u64, @intCast(milli)), .monotonic);

                milli = @divTrunc(milli, std.time.ns_per_us);
                @atomicStore(u10, @constCast(&self.milli), @as(u10, @intCast(milli)), .monotonic);

                break :blk @divTrunc(self.value, std.time.us_per_s);
            },
            inline .nanos => blk: {
                const nano = @rem(self.value, std.time.ns_per_us);
                @atomicStore(u10, @constCast(&self.nano), @as(u10, @intCast(nano)), .monotonic);

                var micro = @rem(self.value, std.time.ns_per_ms);
                micro = @divTrunc(micro, std.time.ns_per_us);
                @atomicStore(u10, @constCast(&self.micro), @as(u10, @intCast(micro)), .monotonic);

                var milli = @rem(self.value, std.time.ns_per_s);
                @atomicStore(u64, @constCast(&self.rest), @as(u64, @intCast(milli)), .monotonic);

                milli = @divTrunc(milli, std.time.ns_per_ms);
                @atomicStore(u10, @constCast(&self.milli), @as(u10, @intCast(milli)), .monotonic);

                break :blk @divTrunc(self.value, std.time.ns_per_s);
            },
        };

        self.offset = offset();
        self.date_time = absDate(seconds + self.offset.?);

        return self;
    }

    fn offset() i32 {
        const loc = @import("zoneinfo.zig").Local.Get() catch |err| {
            std.debug.panic("{any}", .{err});
        };
        return @as(i32, @bitCast(loc.Lookup().offset));
    }

    // format returns a date with custom format
    // | | Token | Output |
    // |-----------------:|:------|:---------------------------------------|
    // | Month
    // | | M  | 1 2 ... 11 12 |
    // | | Mo | 1st 2nd ... 11th 12th |
    // | | MM | 01 02 ... 11 12 |
    // | | MMM | Jan Feb ... Nov Dec |
    // | | MMMM | January February ... November December |
    // | Quarter
    // | | Q  | 1 2 3 4 |
    // | | QQ | 01 02 03 04 |
    // | | Qo | 1st 2nd 3rd 4th |
    // | Day of Month
    // | | D  | 1 2 ... 30 31 |
    // | | Do | 1st 2nd ... 30th 31st |
    // | | DD | 01 02 ... 30 31 |
    // | Day of Year
    // | |  DDD | 1 2 ... 364 365 |
    // | | DDDo | 1st 2nd ... 364th 365th |
    // | | DDDD | 001 002 ... 364 365 |
    // | Day of Week
    // | | d | 0 1 ... 5 6 (Sun-Sat) |
    // | | c | 1 2 ... 6 7 (Mon-Sun) |
    // | | dd | Su Mo ... Fr Sa |
    // | | ddd | Sun Mon ... Fri Sat |
    // | | dddd | Sunday Monday ... Friday Saturday |
    // | Week of Year
    // | | w  | 1 2 ... 52 53 |
    // | | wo | 1st 2nd ... 52nd 53rd |
    // | | ww | 01 02 ... 52 53 |
    // | Year
    // | |   YY | 70 71 ... 29 30 |
    // | | YYYY | 1970 1971 ... 2029 2030 |
    // | Era
    // | | N  | BC AD |    - AD (Not yet supported)
    // | | NN | Before Christ, Anno Domini |    - AD (Not yet supported)
    // | AM/PM
    // | | A | AM PM |
    // | | a | am pm |
    // | Hour
    // | | H  | 0 1 ... 22 23 |
    // | | HH | 00 01 ... 22 23 |
    // | | h | 1 2 ... 11 12 |
    // | | hh | 01 02 ... 11 12 |
    // | | k | 1 2 ... 23 24 |
    // | | kk | 01 02 ... 23 24 |
    // | Minute
    // | | m  | 0 1 ... 58 59 |
    // | | mm | 00 01 ... 58 59 |
    // | Second
    // | | s  | 0 1 ... 58 59 |
    // | | ss | 00 01 ... 58 59 |
    // | Offset
    // | | Z  | -7 -6 ... +5 +6 |
    // | | ZZ | -0700 -0600 ... +0500 +0600 |
    // | | ZZZ | -07:00 -06:00 ... +05:00 +06:00 |
    // Usage:
    // Time.now().format('MMMM Mo YY N kk:mm:ss A')) // output like: January 1st 22 AD 13:45:33 PM

    pub fn formatf(self: Self, allocator: std.mem.Allocator, pattern: []const u8, writer: anytype) !void {
        var sb = try self.format(allocator, pattern);
        defer sb.deinit();
        errdefer sb.deinit();
        _ = try writer.write(sb.bytes());
    }

    pub fn formatfInto(self: Self, allocator: std.mem.Allocator, pattern: []const u8, dst: []const u8) !usize {
        var sb = try self.format(allocator, pattern);
        defer sb.deinit();
        errdefer sb.deinit();
        return try sb.bytesInto(dst);
    }

    fn format(self: Self, allocator: std.mem.Allocator, pattern: []const u8) !Utf8Buffer {
        var sb = try Utf8Buffer.initWithCapacity(allocator, pattern.len);
        errdefer sb.deinit();

        var i: usize = 0;
        while (i < pattern.len) {
            var j: usize = 4;
            while (j > 0) : (j -= 1) {
                if (i > pattern.len - j) {
                    continue;
                }

                const slice = pattern.ptr[i .. i + j];
                const l1 = j == 1;
                const l2 = j == 2 and in(2, slice);
                const l3 = j == 3 and in(3, slice);
                const l4 = j == 4 and in(4, slice);
                if (l1 or l2 or l3 or l4) {
                    const token = pattern.ptr[i .. i + j];
                    try self.appendToken(token, @constCast(&sb));
                    i += (j - 1);
                    break;
                }
            }
            i += 1;
        }

        return sb;
    }

    fn appendToken(self: Self, token: []const u8, sb: *Utf8Buffer) !void {
        const date_time = self.dateTime();

        if (std.mem.eql(u8, token, "YYYY")) {
            try sb.appendf("{d}", .{date_time.year});
        } else if (std.mem.eql(u8, token, "MMMM")) {
            try sb.appendf("{s}", .{self.getMonth().string()});
        } else if (std.mem.eql(u8, token, "MMM")) {
            try sb.appendf("{s}", .{self.getMonth().shortString()});
        } else if (std.mem.eql(u8, token, "MM")) {
            if (date_time.month < 10) {
                try sb.append("0");
            }
            try sb.appendf("{d}", .{date_time.month});
        } else if (std.mem.eql(u8, token, "M")) {
            try sb.appendf("{d}", .{date_time.month});
        } else if (std.mem.eql(u8, token, "Mo")) {
            const suffix = switch (date_time.month) {
                1 => "st",
                2 => "nd",
                3 => "rd",
                else => "th",
            };
            try sb.appendf("{d}{s}", .{ date_time.month, suffix });
        } else if (std.mem.eql(u8, token, "DD")) {
            if (date_time.day < 10) {
                try sb.append("0");
            }
            try sb.appendf("{d}", .{date_time.day});
        } else if (std.mem.eql(u8, token, "D")) {
            try sb.appendf("{d}", .{date_time.day});
        } else if (std.mem.eql(u8, token, "Do")) {
            const rem = @rem(date_time.day, 30);
            const suffix = switch (rem) {
                1 => "st",
                2 => "nd",
                3 => "rd",
                else => "th",
            };
            try sb.appendf("{d}{s}", .{ date_time.day, suffix });
        } else if (std.mem.eql(u8, token, "DDDD")) {
            if (date_time.yday < 10) {
                try sb.appendf("00{d}", .{date_time.yday});
            } else if (date_time.yday < 100) {
                try sb.appendf("0{d}", .{date_time.yday});
            } else {
                try sb.appendf("{d}", .{date_time.yday});
            }
        } else if (std.mem.eql(u8, token, "DDD")) {
            try sb.appendf("{d}", .{date_time.yday});
        } else if (std.mem.eql(u8, token, "DDDo")) {
            const rem = @rem(date_time.yday, daysBefore[date_time.month]);
            const suffix = switch (rem) {
                1 => "st",
                2 => "nd",
                3 => "rd",
                else => "th",
            };
            try sb.appendf("{d}{s}", .{ date_time.yday, suffix });
        } else if (std.mem.eql(u8, token, "HH")) {
            if (date_time.hour < 10) {
                try sb.append("0");
            }
            try sb.appendf("{d}", .{date_time.hour});
        } else if (std.mem.eql(u8, token, "H")) {
            try sb.appendf("{d}", .{date_time.hour});
        } else if (std.mem.eql(u8, token, "kk")) {
            if (date_time.hour < 10) {
                try sb.append("0");
            }
            try sb.appendf("{d}", .{date_time.hour});
        } else if (std.mem.eql(u8, token, "k")) {
            try sb.appendf("{d}", .{date_time.hour});
        } else if (std.mem.eql(u8, token, "hh")) {
            const h = @rem(date_time.hour, 12);
            try sb.appendf("{d}", .{h});
        } else if (std.mem.eql(u8, token, "h")) {
            const h = @rem(date_time.hour, 12);
            if (h < 10) {
                try sb.append("0");
                try sb.appendf("0{d}", .{h});
            } else {
                try sb.appendf("{d}", .{h});
            }
        } else if (std.mem.eql(u8, token, "mm")) {
            if (date_time.min < 10) {
                try sb.append("0");
            }
            try sb.appendf("{d}", .{date_time.min});
        } else if (std.mem.eql(u8, token, "m")) {
            try sb.appendf("{d}", .{date_time.min});
        } else if (std.mem.eql(u8, token, "ss")) {
            if (date_time.sec < 10) {
                try sb.append("0");
            }
            try sb.appendf("{d}", .{date_time.sec});
        } else if (std.mem.eql(u8, token, "s")) {
            try sb.appendf("{d}", .{date_time.sec});
        } else if (@intFromEnum(self.measure) >= @intFromEnum(Measure.millis) and std.mem.eql(u8, token, "SSS")) {
            try sb.appendf("{d}", .{self.rest});
        } else if (std.mem.eql(u8, token, "a") or std.mem.eql(u8, token, "A")) {
            if (date_time.hour <= 11) {
                try sb.append("AM");
            } else {
                try sb.append("PM");
            }
        } else if (std.mem.eql(u8, token, "c") or std.mem.eql(u8, token, "d")) {
            try sb.appendf("{d}", .{date_time.wday});
        } else if (std.mem.eql(u8, token, "dd")) {
            try sb.appendf("{s}", .{self.getWeekday().shorterString()});
        } else if (std.mem.eql(u8, token, "ddd")) {
            try sb.appendf("{s}", .{self.getWeekday().shortString()});
        } else if (std.mem.eql(u8, token, "dddd")) {
            try sb.appendf("{s}", .{self.getWeekday().string()});
        } else if (std.mem.eql(u8, token, "ZZZ")) {
            try self.zzz(sb, ":");
        } else if (std.mem.eql(u8, token, "ZZ")) {
            try self.zzz(sb, "");
        } else if (std.mem.eql(u8, token, "Z")) {
            const h = @divFloor(self.offset.?, std.time.s_per_hour);
            if (h > 0) {
                try sb.append("+");
            }
            try sb.appendf("{d}", .{h});
        } else if (std.mem.eql(u8, token, "NN")) {
            try sb.append("BC");
        } else if (std.mem.eql(u8, token, "N")) {
            try sb.append("Before Christ");
        } else if (std.mem.eql(u8, token, "w")) {
            const l: u32 = if (isLeap(date_time.year)) 1 else 0;
            const wy = @divTrunc(mceil(date_time.day + daysBefore[date_time.month - 1] + l), 7);
            try sb.appendf("{d}", .{wy});
        } else if (std.mem.eql(u8, token, "wo")) {
            const l: u32 = if (isLeap(date_time.year)) 1 else 0;
            const wy = @divTrunc(mceil(date_time.day + daysBefore[date_time.month - 1] + l), 7);
            const suffix = switch (wy) {
                1 => "st",
                2 => "nd",
                3 => "rd",
                else => "th",
            };
            try sb.appendf("{d}{s}", .{ wy, suffix });
        } else if (std.mem.eql(u8, token, "ww")) {
            const l: u32 = if (isLeap(date_time.year)) 1 else 0;
            const wy = @divTrunc(mceil(date_time.day + daysBefore[date_time.month - 1] + l), 7);
            if (wy < 10) {
                try sb.appendf("0{d}", .{wy});
            } else {
                try sb.appendf("{d}", .{wy});
            }
        } else if (std.mem.eql(u8, token, "QQ")) {
            const q = @divTrunc(date_time.month - 1, 3) + 1;
            try sb.appendf("0{d}", .{q});
        } else if (std.mem.eql(u8, token, "Q")) {
            const q = @divTrunc(date_time.month - 1, 3) + 1;
            try sb.appendf("0{d}", .{q});
        } else if (std.mem.eql(u8, token, "Qo")) {
            const q = @divTrunc(date_time.month - 1, 3) + 1;
            const suffix = switch (q) {
                1 => "st",
                2 => "nd",
                3 => "rd",
                else => "th",
            };
            try sb.appendf("{d}{s}", .{ q, suffix });
        } else {
            try sb.append(token);
        }
    }

    pub fn getWeekday(self: Self) Weekday {
        return @as(Weekday, @enumFromInt(self.dateTime().wday));
    }
    pub fn getMonth(self: Self) Month {
        return @as(Month, @enumFromInt(self.dateTime().month));
    }

    fn zzz(self: Self, sb: *Utf8Buffer, delimeter: []const u8) !void {
        var h = @divFloor(self.offset.?, std.time.s_per_hour);
        if (h > 0) {
            try sb.append("+");
        } else if (h < 0) {
            try sb.append("-");
            h = @as(i32, @intCast(@abs(h)));
        }
        if (h < 10) {
            try sb.appendf("0{d}", .{h});
        } else {
            try sb.appendf("{d}", .{h});
        }

        const m = @as(i32, @intCast(@divFloor(@as(i32, @intCast(@abs(self.offset.?))) - h * std.time.s_per_hour, std.time.s_per_min)));
        if (m < 10) {
            try sb.appendf("{s}0{d}", .{ delimeter, m });
        } else {
            try sb.appendf("{s}{d}", .{ delimeter, m });
        }
    }
};

pub inline fn isLeap(year: i128) bool {
    return @rem(year, 4) == 0 and (@rem(year, 100) != 0 or @rem(year, 400) == 0);
}

pub inline fn daysIn(m: i32, year: i32) u32 {
    if (m == 2 and isLeap(year)) {
        return 29;
    }
    const idx = @as(usize, @intCast(m));
    return daysBefore[idx] - daysBefore[idx - 1];
}

pub const absolute_zero_year = 1970;
pub const days_per_year = 365;
pub const days_per_400_years = days_per_year * 400 + 97;
pub const days_per_100_years = days_per_year * 100 + 24;
pub const days_per_4_years = days_per_year * 4 + 1;

// daysBefore[m] counts the number of days in a non-leap year
// before month m begins. There is an entry for m=12, counting
// the number of days before January of next year (365).
pub const daysBefore = [13]u32{
    0,
    31,
    31 + 28,
    31 + 28 + 31,
    31 + 28 + 31 + 30,
    31 + 28 + 31 + 30 + 31,
    31 + 28 + 31 + 30 + 31 + 30,
    31 + 28 + 31 + 30 + 31 + 30 + 31,
    31 + 28 + 31 + 30 + 31 + 30 + 31 + 31,
    31 + 28 + 31 + 30 + 31 + 30 + 31 + 31 + 30,
    31 + 28 + 31 + 30 + 31 + 30 + 31 + 31 + 30 + 31,
    31 + 28 + 31 + 30 + 31 + 30 + 31 + 31 + 30 + 31 + 30,
    31 + 28 + 31 + 30 + 31 + 30 + 31 + 31 + 30 + 31 + 30 + 31,
};

const tokens_2 = [_][]const u8{ "MM", "Mo", "DD", "Do", "YY", "ss", "kk", "NN", "mm", "hh", "HH", "ZZ", "dd", "Qo", "QQ", "wo", "ww" };
const tokens_3 = [_][]const u8{ "MMM", "DDD", "ZZZ", "ddd", "SSS" };
const tokens_4 = [_][]const u8{ "MMMM", "DDDD", "DDDo", "dddd", "YYYY" };

fn in(comptime tokentype: u4, elem: []const u8) bool {
    inline for (switch (tokentype) {
        inline 2 => tokens_2,
        inline 3 => tokens_3,
        inline 4 => tokens_4,
        inline 5...15, 0...1 => [_][]const u8{},
    }) |item| {
        if (std.mem.eql(u8, item, elem)) {
            return true;
        }
    }
    return false;
}

fn mceil(x: i128) i128 {
    if (x > 0) {
        return 1 + x;
    } else if (x < 0) {
        return x;
    }
    return 0;
}

const weekday_t = [_]u8{ 0, 3, 2, 5, 0, 3, 5, 1, 4, 6, 2, 4 };
fn weekday(y: u16, m: u5, d: u5) u16 {
    // Sakomotho's algorithm is explained here:
    // https://stackoverflow.com/a/6385934
    var sy = y;
    if (m < 3) {
        sy = sy - 1;
    }
    const t1 = @divTrunc(sy, 4);
    const t2 = @divTrunc(sy, 100);
    const t3 = @divTrunc(sy, 400);

    const i = @as(usize, @intCast(m));
    return @rem((sy + t1 - t2 + t3 + weekday_t[i - 1] + d - 1), 7) + 1;
}

pub fn daysSinceEpoch(year: i32) i64 {
    var y = year - absolute_zero_year;

    // Add in days from 400-year cycles.
    var n = @divFloor(y, 400);
    y -= 400 * n;
    var d = days_per_400_years * n;

    // Add in 100-year cycles.
    n = @divFloor(y, 100);
    y -= 100 * n;
    d += days_per_100_years * n;

    // Add in 4-year cycles.
    n = @divFloor(y, 4);
    y -= 4 * n;
    d += days_per_4_years * n;

    // Add in non-leap years.
    n = y;
    d += 365 * n;

    return @as(i64, @intCast(d));
}

pub fn absDate(seconds: i128) DateTime {
    // Split into time and day.
    var d = @divFloor(seconds, std.time.s_per_day);

    // Account for 400 year cycles.
    var n = @divFloor(d, days_per_400_years);
    var y = 400 * n;
    d -= days_per_400_years * n;

    // Cut off 100-year cycles.
    // The last cycle has one extra leap year, so on the last day
    // of that year, day / daysPer100Years will be 4 instead of 3.
    // Cut it back down to 3 by subtracting n>>2.
    n = @divFloor(d, days_per_100_years);
    n -= n >> 2;
    y += 100 * n;
    d -= days_per_100_years * n;

    // Cut off 4-year cycles.
    // The last cycle has a missing leap year, which does not
    // affect the computation.
    n = @divFloor(d, days_per_4_years);
    y += 4 * n;
    d -= days_per_4_years * n;

    // Cut off years within a 4-year cycle.
    // The last year is a leap year, so on the last day of that year,
    // day / 365 will be 4 instead of 3. Cut it back down to 3
    // by subtracting n>>2.
    n = @divFloor(d, days_per_year);
    n -= n >> 2;
    y += n;
    d -= days_per_year * n;

    var sec = @rem(seconds, std.time.s_per_day);
    const hour = @divFloor(sec, std.time.s_per_hour);
    sec -= hour * std.time.s_per_hour;
    const min = @divFloor(sec, std.time.s_per_min);
    sec -= min * std.time.s_per_min;

    const year = y + absolute_zero_year;

    var day = d;

    // Estimate month on assumption that every month has 31 days.
    // The estimate may be too low by at most one month, so adjust.
    var month = @divFloor(day, 31);
    if (isLeap(year)) {
        // Leap year
        if (day > 31 + 29 - 1) {
            day -= 1;
        }
        if (day == 31 + 29 - 1) {
            day -= 1;
            // Leap day.
            month = 2; // February
            day = 29;

            return DateTime{
                .year = @as(u16, @intCast(year)),
                .month = @as(u5, @intCast(month)),
                .yday = @as(u9, @intCast(d)),
                .wday = @as(u3, @intCast(weekday(@as(u16, @intCast(year)), @as(u5, @intCast(month)), @as(u5, @intCast(day))))),
                .day = @as(u5, @intCast(day)),
                .hour = @as(u6, @intCast(hour)),
                .min = @as(u6, @intCast(min)),
                .sec = @as(u6, @intCast(sec)),
            };
        }
    }

    const i = @as(usize, @intCast(month));
    var begin = daysBefore[i];
    const end = daysBefore[i + 1];

    if (day >= end) {
        month += 1;
        begin = end;
    }

    month += 1; // because January is 1
    day = day - begin + 1;

    return DateTime{
        .year = @as(u16, @intCast(year)),
        .month = @as(u5, @intCast(month)),
        .yday = @as(u9, @intCast(d)),
        .wday = @as(u3, @intCast(weekday(@as(u16, @intCast(year)), @as(u5, @intCast(month)), @as(u5, @intCast(day))))),
        .day = @as(u5, @intCast(day)),
        .hour = @as(u6, @intCast(hour)),
        .min = @as(u6, @intCast(min)),
        .sec = @as(u6, @intCast(sec)),
    };
}
