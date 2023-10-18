const std = @import("std");
const builtin = @import("builtin");

const time = @import("time.zig");

pub const Error = error{
    UnknownTimeZone,
};

pub fn GetLocation() Location {
    // const Impl = if (builtin.single_threaded)
    //     SingleThreadedImpl
    // else if (builtin.os.tag == .windows)
    //     WindowsImpl
    // else if (builtin.os.tag.isDarwin())
    //     DarwinImpl
    // else if (builtin.os.tag == .linux)
    //     LinuxImpl
    // else if (builtin.os.tag == .freebsd)
    //     FreebsdImpl
    // else if (builtin.os.tag == .openbsd)
    //     OpenbsdImpl
    // else if (builtin.os.tag == .dragonfly)
    //     DragonflyImpl
    // else if (builtin.target.isWasm())
    //     WasmImpl
    // else if (std.Thread.use_pthreads)
    //     PosixImpl
    // else
    //     UnsupportedImpl;

    const empty = Location{
        .name = "",
        .zone = &[0]zone{},
        .tx = &[0]zoneTrans{},
        .extend = "",
        .cacheStart = 0,
        .cacheEnd = 0,
        .cacheZone = zone{ .name = "", .offset = 0, .isDST = false },
    };

    if (builtin.os.tag.isDarwin()) {
        return unix() catch empty;
    } else {
        return empty;
    }
}

pub const Location = struct {
    name: []const u8,
    zone: []zone,
    tx: []zoneTrans,

    // The tzdata information can be followed by a string that describes
    // how to handle DST transitions not recorded in zoneTrans.
    // The format is the TZ environment variable without a colon; see
    // https://pubs.opengroup.org/onlinepubs/9699919799/basedefs/V1_chap08.html.
    // Example string, for America/Los_Angeles: PST8PDT,M3.2.0,M11.1.0
    extend: []const u8,

    // Most lookups will be for the current time.
    // To avoid the binary search through tx, keep a
    // static one-element cache that gives the correct
    // zone for the time when the Location was created.
    // if cacheStart <= t < cacheEnd,
    // lookup can return cacheZone.
    // The units for cacheStart and cacheEnd are seconds
    // since January 1, 1970 UTC, to match the argument
    // to lookup.
    cacheStart: i64,
    cacheEnd: i64,
    cacheZone: zone,

    pub fn Name(self: Location) []const u8 {
        return self.name;
    }
    pub fn Extend(self: Location) []const u8 {
        return self.extend;
    }
};

const zone = struct {
    name: []const u8, // abbreviated name, "CET"
    offset: i32, // seconds east of UTC
    isDST: bool, // is this zone Daylight Savings Time?
};
const zoneTrans = struct {
    when: i64, // transition time, in seconds since 1970 GMT
    index: u8, // the index of the zone that goes into effect at that time
    isstd: bool, // ignored - no idea what these mean
    isutc: bool, // ignored - no idea what these mean
};

fn unix() !Location {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const allocator = arena.allocator();

    const val: ?[]const u8 = std.process.getEnvVarOwned(allocator, "TZ") catch null;
    if (val) |tz| {
        var tzTmp = tz;
        if (tzTmp[0] == ':') {
            tzTmp = tzTmp[1..];
        }
        if (!std.mem.eql(u8, tzTmp, "") and tzTmp[0] == '/') {
            const sources = std.ArrayList([]const u8).init(allocator);
            const z = try loadLocation(allocator, tzTmp, sources);
            return Location{
                .zone = z.zone,
                .tx = z.tx,
                .name = if (std.mem.eql(u8, tzTmp, "/etc/localtime")) "Local" else tz,
                .extend = z.extend,
                .cacheStart = z.cacheStart,
                .cacheEnd = z.cacheEnd,
                .cacheZone = z.cacheZone,
            };
        } else if (!std.mem.eql(u8, tzTmp, "") and !std.mem.eql(u8, tzTmp, "UTC")) {
            var sources = std.ArrayList([]const u8).init(allocator);
            try sources.append("/etc");
            try sources.append("/usr/share/zoneinfo/");
            try sources.append("/usr/share/lib/zoneinfo/");
            try sources.append("/usr/lib/locale/TZ/");
            try sources.append("/etc/zoneinfo");

            return try loadLocation(allocator, tzTmp, sources);
        }
    }

    var sources = std.ArrayList([]const u8).init(allocator);
    try sources.append("/etc");
    const z = try loadLocation(allocator, "localtime", sources);
    var buff: [100]u8 = undefined;
    const extend = try std.fmt.bufPrint(&buff, "{s}", .{z.extend});
    return Location{
        .zone = z.zone,
        .tx = z.tx,
        .name = "Local",
        .extend = extend[0..],
        .cacheStart = z.cacheStart,
        .cacheEnd = z.cacheEnd,
        .cacheZone = z.cacheZone,
    };
}

// loadLocation returns the Location with the given name from one of
// the specified sources. See loadTzinfo for a list of supported sources.
// The first timezone data matching the given name that is successfully loaded
// and parsed is returned as a Location.
fn loadLocation(allocator: std.mem.Allocator, name: []const u8, sources: std.ArrayList([]const u8)) !Location {
    var arr = sources;
    while (arr.popOrNull()) |source| {
        const zoneData = try loadTzinfo(allocator, name, source);
        return try LoadLocationFromTZData(name, zoneData);
    }
    return Error.UnknownTimeZone;
}

// loadFromEmbeddedTZData is used to load a specific tzdata file
// from tzdata information embedded in the binary itself.
// This is set when the time/tzdata package is imported,
// via registerLoadFromEmbeddedTzdata.
fn loadFromEmbeddedTZData(zipname: []const u8) ![]const u8 {
    _ = zipname;
}

// loadTzinfoFromTzdata returns the time zone information of the time zone
// with the given name, from a tzdata database file as they are typically
// found on android.
fn loadTzinfoFromTzdata(file: []const u8, name: []const u8) ![]const u8 {
    _ = name;
    _ = file;
    return "";
}

// loadTzinfoFromDirOrZip returns the contents of the file with the given name
// in dir. dir can either be an uncompressed zip file, or a directory.
fn loadTzinfoFromDirOrZip(allocator: std.mem.Allocator, dir: []const u8, name: []const u8) ![]const u8 {
    if (dir.len >= 6 and std.mem.eql(u8, dir[dir.len - 4 ..], ".zip")) {
        // return loadTzinfoFromZip(dir, name);
        return "";
    }
    if (!std.mem.eql(u8, dir, "")) {
        var buf: [512]u8 = undefined;
        const res = try std.fmt.bufPrint(&buf, "{s}/{s}", .{ dir, name });
        return try std.fs.cwd().readFileAlloc(allocator, res, 1 * 1024 * 1024);
    }

    return try std.fs.cwd().readFileAlloc(allocator, name, 1 * 1024 * 1024);
}

// loadTzinfo returns the time zone information of the time zone
// with the given name, from a given source. A source may be a
// timezone database directory, tzdata database file or an uncompressed
// zip file, containing the contents of such a directory.
fn loadTzinfo(allocator: std.mem.Allocator, name: []const u8, source: []const u8) ![]const u8 {
    if (source.len >= 6 and std.mem.eql(u8, source[source.len - 6 ..], "tzdata")) {
        return loadTzinfoFromTzdata(source, name);
    }
    return loadTzinfoFromDirOrZip(allocator, source, name);
}

const LocationError = error{
    BadData,
};

// LoadLocationFromTZData returns a Location with the given name
// initialized from the IANA Time Zone database-formatted data.
// The data should be in the format of a standard IANA time zone file
// (for example, the content of /etc/localtime on Unix systems).
fn LoadLocationFromTZData(name: []const u8, data: []const u8) LocationError!Location {
    // 4-byte magic "TZif"
    var dataIdx: i32 = 0;
    var i = @as(usize, @intCast(dataIdx));
    if (data.len < i + 4) return LocationError.BadData;

    if (!std.mem.eql(u8, data[i..(i + 4)], "TZif")) {
        return LocationError.BadData;
    }
    dataIdx += 4;

    // 1-byte version, then 15 bytes of padding
    i = @as(usize, @intCast(dataIdx));
    if (data.len < i + 16) return LocationError.BadData;

    const p = data[i..(i + 16)];
    dataIdx += 16;

    var version: i8 = -1;
    if (p[0] == '0') {
        version = 1;
    } else if (p[0] == '2') {
        version = 2;
    } else if (p[0] == '3') {
        version = 3;
    }

    if (version == -1) {
        return LocationError.BadData;
    }

    // six big-endian 32-bit integers:
    //	number of UTC/local indicators
    //	number of standard/wall indicators
    //	number of leap seconds
    //	number of transition times
    //	number of local time zones
    //	number of characters of time zone abbrev strings
    var n: [6]i32 = undefined;
    for (0..6) |idx| {
        i = @as(usize, @intCast(dataIdx));
        const nn = big4(data, i);
        if (!nn.ok) {
            return LocationError.BadData;
        }
        dataIdx += 4;

        if (@as(i32, @intCast(nn.val)) != nn.val) {
            return LocationError.BadData;
        }
        n[idx] = @as(i32, @intCast(nn.val));
    }

    // If we have version 2 or 3, then the data is first written out
    // in a 32-bit format, then written out again in a 64-bit format.
    // Skip the 32-bit format and read the 64-bit one, as it can
    // describe a broader range of dates.

    const NUTCLocal = 0;
    const NStdWall = 1;
    const NLeap = 2;
    const NTime = 3;
    const NZone = 4;
    const NChar = 5;
    var is64 = false;
    if (version > 1) {
        // Skip the 32-bit data.
        const skip = n[NTime] * 4 +
            n[NTime] +
            n[NZone] * 6 +
            n[NChar] +
            n[NLeap] * 8 +
            n[NStdWall] +
            n[NUTCLocal];

        // Skip the version 2 header that we just read.
        dataIdx += skip;
        dataIdx += 20;

        is64 = true;

        // Read the counts again, they can differ.
        for (0..6) |idx| {
            i = @as(usize, @intCast(dataIdx));
            const nn = big4(data, i);
            if (!nn.ok) {
                return LocationError.BadData;
            }
            dataIdx += 4;

            if (@as(i32, @intCast(nn.val)) != nn.val) {
                return LocationError.BadData;
            }
            n[idx] = @as(i32, @intCast(nn.val));
        }
    }

    const size: i32 = if (is64) 8 else 4;

    // Transition times.
    var t = @as(usize, @intCast(n[NTime] * size));
    i = @as(usize, @intCast(dataIdx));
    const txtimes = data[i..(i + t)];
    dataIdx += n[NTime] * size;

    // Time zone indices for transition times.
    t = @as(usize, @intCast(n[NTime]));
    i = @as(usize, @intCast(dataIdx));
    const txzones = data[i..(i + t)];
    dataIdx += n[NTime];

    // Zone info structures
    t = @as(usize, @intCast(n[NZone] * 6));
    i = @as(usize, @intCast(dataIdx));
    const zonedata = data[i..(i + t)];
    dataIdx += n[NZone] * 6;

    // Time zone abbreviations.
    t = @as(usize, @intCast(n[NChar]));
    i = @as(usize, @intCast(dataIdx));
    const abbrev = data[i..(i + t)];
    dataIdx += n[NChar];

    // Leap-second time pairs
    t = @as(usize, @intCast(n[NLeap] * (size + 4)));
    dataIdx += n[NLeap] * (size + 4);

    // Whether tx times associated with local time types
    // are specified as standard time or wall time.
    t = @as(usize, @intCast(n[NStdWall]));
    i = @as(usize, @intCast(dataIdx));
    const isstd = data[i..(i + t)];
    dataIdx += n[NStdWall];

    // Whether tx times associated with local time types
    // are specified as UTC or local time.
    t = @as(usize, @intCast(n[NUTCLocal]));
    i = @as(usize, @intCast(dataIdx));
    const isutc = data[i..(i + t)];
    dataIdx += n[NUTCLocal];

    i = @as(usize, @intCast(dataIdx));
    var extend = data[i..];
    if (extend.len > 2 and extend[0] == '\n' and extend[extend.len - 1] == '\n') {
        extend = extend[1 .. extend.len - 1];
    }

    // Now we can build up a useful data structure.
    // First the zone information.
    //	utcoff[4] isdst[1] nameindex[1]
    const nzone = @as(usize, @intCast(n[NZone]));
    if (nzone == 0) {
        // Reject tzdata files with no zones. There's nothing useful in them.
        // This also avoids a panic later when we add and then use a fake transition (golang.org/issue/29437).
        return LocationError.BadData;
    }

    var zonesBuff = [_]zone{undefined} ** 10000;
    var dataZoneIdx: i32 = 0;
    for (0..nzone) |idx| {
        i = @as(usize, @intCast(dataZoneIdx));
        var bign = big4(zonedata, i);
        if (!bign.ok) {
            return LocationError.BadData;
        }
        dataZoneIdx += 4;

        const offset = @as(i32, @intCast(bign.val));

        i = @as(usize, @intCast(dataZoneIdx));
        var b = zonedata[i];
        dataZoneIdx += 1;

        const isDST = b != 0;

        i = @as(usize, @intCast(dataZoneIdx));
        b = zonedata[i];
        dataZoneIdx += 1;

        if (@as(usize, @intCast(b)) >= abbrev.len) {
            return LocationError.BadData;
        }

        const zname = abbrev[b..];

        if (builtin.os.tag == .aix and name.len > 8 and (std.mem.eql(u8, name[0..8], "Etc/GMT+") or std.mem.eql(u8, name[0..8], "Etc/GMT-"))) {
            // There is a bug with AIX 7.2 TL 0 with files in Etc,
            // GMT+1 will return GMT-1 instead of GMT+1 or -01.
            if (!std.mem.eql(u8, name, "Etc/GMT+0")) {
                // GMT+0 is OK
                zname = name[4..];
            }
        }
        zonesBuff[idx] = zone{ .name = zname, .offset = offset, .isDST = isDST };
    }
    const zones = zonesBuff[0..nzone];

    // Now the transition time info.
    const nzonerx = @as(usize, @intCast(n[NTime]));
    var txBuff = [_]zoneTrans{undefined} ** 10000;
    var dataZoneTransIdx: i32 = 0;
    for (0..nzonerx) |idx| {
        var when: i64 = 0;
        if (!is64) {
            i = @as(usize, @intCast(dataZoneTransIdx));
            const n4 = big4(txtimes, i);
            dataZoneTransIdx += 4;

            if (!n4.ok) {
                return LocationError.BadData;
            } else {
                when = @as(i64, @intCast(n4.val));
            }
        } else {
            i = @as(usize, @intCast(dataZoneTransIdx));
            const n8 = big8(txtimes, i);
            dataZoneTransIdx += 8;

            if (!n8.ok) {
                return LocationError.BadData;
            } else {
                when = @as(i64, @bitCast(n8.val));
            }
        }

        if (txzones[idx] >= zones.len) {
            return LocationError.BadData;
        }

        const index = txzones[idx];

        const isstdBool: bool = if (idx < isstd.len) isstd[idx] != 0 else false;
        const isutcBool: bool = if (idx < isutc.len) isutc[idx] != 0 else false;

        txBuff[idx] = zoneTrans{ .when = when, .index = index, .isstd = isstdBool, .isutc = isutcBool };
    }
    const tx = txBuff[0..nzonerx];

    if (tx.len == 0) {
        // Build fake transition to cover all time.
        // This happens in fixed locations like "Etc/GMT0".
        tx[0] = zoneTrans{ .when = std.math.minInt(u64), .index = 0, .isstd = false, .isutc = false };
    }

    // Fill in the cache with information about right now,
    // since that will be the most common lookup.
    var cacheStart: i64 = 0;
    var cacheEnd: i64 = 0;
    var cacheZone: ?zone = null;

    const sec: i64 = unixToInternal + internalToAbsolute + std.time.timestamp();
    for (0..tx.len) |txIdx| {
        if (tx[txIdx].when <= sec and (txIdx + 1 == tx.len or sec < tx[txIdx + 1].when)) {
            cacheStart = tx[txIdx].when;
            cacheEnd = std.math.maxInt(i64);
            cacheZone = zones[tx[txIdx].index];
            if (txIdx + 1 < tx.len) {
                cacheEnd = tx[txIdx + 1].when;
            } else if (!std.mem.eql(u8, extend, "")) {
                // If we're at the end of the known zone transitions,
                // try the extend string.

                const r = tzset(extend, cacheStart, sec);
                if (r.ok) {
                    const zname = r.name;
                    const zoffset = r.offset;
                    const zestart = r.start;
                    const zeend = r.end;
                    const zisDST = r.isDST;

                    cacheStart = zestart;
                    cacheEnd = zeend;
                    // Find the zone that is returned by tzset to avoid allocation if possible.
                    for (zones, 0..) |z, zoneIdx| {
                        if (std.mem.eql(u8, z.name, zname) and z.offset == zoffset and z.isDST == zisDST) {
                            cacheZone = zones[zoneIdx];
                            break;
                        }
                    }
                    if (cacheZone == null) {
                        cacheZone = zone{
                            .name = zname,
                            .offset = zoffset,
                            .isDST = zisDST,
                        };
                    }
                }
            }
            break;
        }
    }

    return Location{ .zone = zones, .tx = tx, .name = name, .extend = extend, .cacheStart = cacheStart, .cacheEnd = cacheEnd, .cacheZone = cacheZone.? };
}

// tzset takes a timezone string like the one found in the TZ environment
// variable, the time of the last time zone transition expressed as seconds
// since January 1, 1970 00:00:00 UTC, and a time expressed the same way.
// We call this a tzset string since in C the function tzset reads TZ.
// The return values are as for lookup, plus ok which reports whether the
// parse succeeded.

const internalYear = 1;
const unixToInternal = (1969 * 365 + @divTrunc(1969, 4) - @divTrunc(1969, 100) + @divTrunc(1969, 400)) * std.time.s_per_day;
const internalToUnix = -unixToInternal;

const absoluteToInternal = @as(i64, @intFromFloat(1969 * 365.2425 * std.time.s_per_day));
const internalToAbsolute = -absoluteToInternal;
const wallToInternal: i64 = (1884 * 365 + @divTrunc(1884, 4) - @divTrunc(1884, 100) + @divTrunc(1884, 400)) * std.time.s_per_day;

const tzsetResult = struct {
    name: []const u8,
    offset: i32,
    start: i64,
    end: i64,
    isDST: bool,
    ok: bool,
};
fn tzset(source: []const u8, lastTxSec: i64, sec: i64) tzsetResult {
    var stdOffset: i32 = 0;
    var dstOffset: i32 = 0;

    var r = tzsetName(source);
    const stdName = r.name;
    var s = r.rest;
    if (r.ok) {
        const offRes = tzsetOffset(s);
        stdOffset = -offRes.offset;

        if (!offRes.ok) {
            return tzsetResult{ .name = "", .offset = 0, .start = 0, .end = 0, .isDST = false, .ok = false };
        }
    }
    if (s.len == 0 or s[0] == ',') {
        // No daylight savings time.
        return tzsetResult{ .name = stdName, .offset = stdOffset, .start = lastTxSec, .end = std.math.maxInt(i64), .isDST = false, .ok = true };
    }

    r = tzsetName(s);
    const dstName = r.name;
    s = r.rest;
    if (r.ok) {
        if (s.len == 0 or s[0] == ',') {
            dstOffset = stdOffset + std.time.s_per_hour;
        } else {
            const offRes = tzsetOffset(s);
            if (!offRes.ok) {
                return tzsetResult{ .name = "", .offset = 0, .start = 0, .end = 0, .isDST = false, .ok = false };
            }
            s = offRes.rest;
            dstOffset = -offRes.offset;
        }
    }

    if (s.len == 0) {
        // Default DST rules per tzcode.
        s = ",M3.2.0,M11.1.0";
    }
    // The TZ definition does not mention ';' here but tzcode accepts it.
    if (s[0] != ',' and s[0] != ';') {
        return tzsetResult{ .name = "", .offset = 0, .start = 0, .end = 0, .isDST = false, .ok = false };
    }
    s = s[1..];

    var ru = tzsetRule(s);
    s = ru.rest;
    if (!ru.ok or s.len == 0 or s[0] != ',') {
        return tzsetResult{ .name = "", .offset = 0, .start = 0, .end = 0, .isDST = false, .ok = false };
    }
    const startRule = ru.rule;

    s = s[1..];
    ru = tzsetRule(s);
    s = ru.rest;
    if (!ru.ok or s.len > 0) {
        return tzsetResult{ .name = "", .offset = 0, .start = 0, .end = 0, .isDST = false, .ok = false };
    }
    const endRule = ru.rule;

    const seconds = sec + unixToInternal + internalToAbsolute;
    const t = @constCast(&time.Time(.seconds).new()).absDate(seconds);

    const year = t.year;
    const yday = @as(i32, @intCast(t.yday));

    const ysec = yday * std.time.s_per_day + @rem(sec, std.time.s_per_day);

    // Compute start of year in seconds since Unix epoch.
    const d = time.daysSinceEpoch(year);
    var abs = d * std.time.s_per_day;
    abs += absoluteToInternal + internalToUnix;

    var startSec = tzruleTime(year, startRule, stdOffset);
    var endSec = tzruleTime(year, endRule, dstOffset);

    var dstIsDST = false;
    var stdIsDST = true;

    // Note: this is a flipping of "DST" and "STD" while retaining the labels
    // This happens in southern hemispheres. The labelling here thus is a little
    // inconsistent with the goal.
    if (endSec < startSec) {
        std.mem.swap(i64, @constCast(&startSec), @constCast(&endSec));
        std.mem.swap([]const u8, @constCast(&stdName), @constCast(&dstName));
        std.mem.swap(i32, @constCast(&stdOffset), @constCast(&dstOffset));
        std.mem.swap(bool, @constCast(&stdIsDST), @constCast(&dstIsDST));
    }

    // The start and end values that we return are accurate
    // close to a daylight savings transition, but are otherwise
    // just the start and end of the year. That suffices for
    // the only caller that cares, which is Date.
    if (ysec < startSec) {
        return tzsetResult{ .name = stdName, .offset = stdOffset, .start = abs, .end = startSec + abs, .isDST = stdIsDST, .ok = true };
    } else if (ysec >= endSec) {
        return tzsetResult{ .name = stdName, .offset = stdOffset, .start = endSec + abs, .end = @as(i64, @intCast(abs + 365 * std.time.s_per_day)), .isDST = stdIsDST, .ok = true };
    } else {
        return tzsetResult{ .name = stdName, .offset = stdOffset, .start = endSec + abs, .end = @as(i64, @intCast(endSec + abs)), .isDST = stdIsDST, .ok = true };
    }
}

// tzsetName returns the timezone name at the start of the tzset string s,
// and the remainder of s, and reports whether the parsing is OK.

const tzsetNameResult = struct {
    name: []const u8,
    rest: []const u8,
    ok: bool,
};
fn tzsetName(s: []const u8) tzsetNameResult {
    if (s.len == 0) {
        return tzsetNameResult{ .name = "", .rest = "", .ok = false };
    }
    if (s[0] != '<') {
        for (s, 0..) |r, i| {
            switch (r) {
                '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', ',', '-', '+' => {
                    if (i < 3) {
                        return tzsetNameResult{ .name = "", .rest = "", .ok = false };
                    }
                    return tzsetNameResult{ .name = s[0..i], .rest = s[i..], .ok = true };
                },
                else => {},
            }
        }
        if (s.len < 3) {
            return tzsetNameResult{ .name = "", .rest = "", .ok = false };
        }
        return tzsetNameResult{ .name = s, .rest = "", .ok = true };
    } else {
        for (s, 0..) |r, i| {
            if (r == '>') {
                return tzsetNameResult{ .name = s[1..i], .rest = s[i + 1 ..], .ok = true };
            }
        }
        return tzsetNameResult{ .name = "", .rest = "", .ok = false };
    }
}

// tzsetOffset returns the timezone offset at the start of the tzset string s,
// and the remainder of s, and reports whether the parsing is OK.
// The timezone offset is returned as a number of seconds.
const tzsetOffsetResult = struct {
    offset: i32,
    rest: []const u8,
    ok: bool,
};
fn tzsetOffset(source: []const u8) tzsetOffsetResult {
    var s = source;
    if (s.len == 0) {
        return tzsetOffsetResult{ .offset = 0, .rest = "", .ok = false };
    }

    var neg = false;
    if (s[0] == '+') {
        s = s[1..];
    } else if (s[0] == '-') {
        s = s[1..];
        neg = true;
    }

    // The tzdata code permits values up to 24 * 7 here,
    // although POSIX does not.
    var tynumResult = tzsetNum(s, 0, 24 * 7);
    const hours = tynumResult.num;
    s = tynumResult.rest;
    if (!tynumResult.ok) {
        return tzsetOffsetResult{ .offset = 0, .rest = "", .ok = false };
    }
    var off = hours * std.time.s_per_hour;
    if (s.len == 0 or s[0] != ':') {
        if (neg) {
            off = -off;
        }
        return tzsetOffsetResult{ .offset = off, .rest = s, .ok = true };
    }

    tynumResult = tzsetNum(s[1..], 0, 59);
    const mins = tynumResult.num;
    s = tynumResult.rest;
    if (!tynumResult.ok) {
        return tzsetOffsetResult{ .offset = 0, .rest = "", .ok = false };
    }
    off += mins * std.time.s_per_min;
    if (s.len == 0 or s[0] != ':') {
        if (neg) {
            off = -off;
        }
        return tzsetOffsetResult{ .offset = off, .rest = s, .ok = true };
    }

    tynumResult = tzsetNum(s[1..], 0, 59);
    const secs = tynumResult.num;
    s = tynumResult.rest;
    if (!tynumResult.ok) {
        return tzsetOffsetResult{ .offset = 0, .rest = "", .ok = false };
    }

    off += secs;

    if (neg) {
        off = -off;
    }
    return tzsetOffsetResult{ .offset = off, .rest = s, .ok = true };
}

// tzsetNum parses a number from a tzset string.
// It returns the number, and the remainder of the string, and reports success.
// The number must be between min and max.
const tzsetNumResult = struct {
    num: i32,
    rest: []const u8,
    ok: bool,
};
fn tzsetNum(s: []const u8, min: i32, max: i32) tzsetNumResult {
    if (s.len == 0) {
        return tzsetNumResult{ .num = 0, .rest = "", .ok = false };
    }
    var num: i32 = 0;
    for (s, 0..) |r, i| {
        if (r < '0' or r > '9') {
            if (i == 0 or num < min) {
                return tzsetNumResult{ .num = 0, .rest = "", .ok = false };
            }
            return tzsetNumResult{ .num = num, .rest = s[i..], .ok = true };
        }
        num *= 10;
        num += r - '0';

        if (num > max) {
            return tzsetNumResult{ .num = 0, .rest = "", .ok = false };
        }
    }
    if (num < min) {
        return tzsetNumResult{ .num = 0, .rest = "", .ok = false };
    }
    return tzsetNumResult{ .num = num, .rest = "", .ok = true };
}

// tzsetRule parses a rule from a tzset string.
// It returns the rule, and the remainder of the string, and reports success.
// rule is a rule read from a tzset string.
const ruleKind = enum(u8) {
    Julian = 0,
    DOY,
    MonthWeekDay,
};
const rule = struct {
    kind: ruleKind,
    day: i32,
    week: i32,
    mon: i32,
    time: i32, // transition time

    pub fn empty() rule {
        return .{ .kind = .Julian, .day = 0, .week = 0, .mon = 0, .time = 0 };
    }
};

const tzsetRuleResult = struct {
    rule: rule,
    rest: []const u8,
    ok: bool,
};
fn tzsetRule(source: []const u8) tzsetRuleResult {
    var s = source;
    if (s.len == 0) {
        return tzsetRuleResult{ .rule = rule.empty(), .rest = "", .ok = false };
    }

    var kind: ruleKind = ruleKind.Julian;
    var day: i32 = 0;
    var week: i32 = 0;
    var mon: i32 = 0;
    var ltime: i32 = 0;
    if (s[0] == 'J') {
        kind = ruleKind.Julian;

        const r = tzsetNum(s[1..], 1, 365);
        if (!r.ok) {
            return tzsetRuleResult{ .rule = rule.empty(), .rest = "", .ok = false };
        }
        day = r.num;
    } else if (s[0] == 'M') {
        kind = ruleKind.MonthWeekDay;

        var r = tzsetNum(s[1..], 1, 12);
        s = r.rest;
        if (!r.ok or s.len == 0 or s[0] != '.') {
            return tzsetRuleResult{ .rule = rule.empty(), .rest = "", .ok = false };
        }
        mon = r.num;

        r = tzsetNum(s[1..], 1, 5);
        s = r.rest;
        if (!r.ok or s.len == 0 or s[0] != '.') {
            return tzsetRuleResult{ .rule = rule.empty(), .rest = "", .ok = false };
        }
        week = r.num;

        r = tzsetNum(s[1..], 0, 6);
        if (!r.ok) {
            return tzsetRuleResult{ .rule = rule.empty(), .rest = "", .ok = false };
        }
        day = r.num;
        s = r.rest;
    } else {
        kind = ruleKind.DOY;

        const r = tzsetNum(s, 0, 365);
        if (!r.ok) {
            return tzsetRuleResult{ .rule = rule.empty(), .rest = "", .ok = false };
        }
        day = r.num;
    }

    if (s.len == 0 or s[0] != '/') {
        ltime = 2 * std.time.s_per_hour; // 2am is the default

        return tzsetRuleResult{ .rule = rule{ .kind = kind, .day = day, .week = week, .mon = mon, .time = ltime }, .rest = s, .ok = true };
    }

    const r = tzsetOffset(s[1..]);
    if (!r.ok) {
        return tzsetRuleResult{ .rule = rule.empty(), .rest = "", .ok = false };
    }
    return tzsetRuleResult{ .rule = rule{ .kind = kind, .day = day, .week = week, .mon = mon, .time = r.offset }, .rest = r.rest, .ok = true };
}

// tzruleTime takes a year, a rule, and a timezone offset,
// and returns the number of seconds since the start of the year
// that the rule takes effect.
fn tzruleTime(year: i32, r: rule, off: i32) i64 {
    var s: i64 = 0;
    switch (r.kind) {
        .Julian => {
            s = (r.day - 1) * std.time.s_per_day;
            if (time.isLeap(year) and r.day >= 60) {
                s += std.time.s_per_day;
            }
        },

        .DOY => s = r.day * std.time.s_per_day,
        .MonthWeekDay => {
            // Zeller's Congruence.
            const m1 = @rem((r.mon + 9), 12) + 1;
            var yy0 = year;
            if (r.mon <= 2) {
                yy0 -= 1;
            }
            var yy1 = @divFloor(yy0, 100);
            var yy2 = @rem(yy0, 100);
            var dow = @rem((@divFloor((26 * m1 - 2), 10) + 1 + yy2 + @divFloor(yy2, 4) + @divFloor(yy1, 4) - 2 * yy1), 7);
            if (dow < 0) {
                dow += 7;
            }
            // Now dow is the day-of-week of the first day of r.mon.
            // Get the day-of-month of the first "dow" day.
            var d = r.day - dow;
            if (d < 0) {
                d += 7;
            }

            for (1..@as(usize, @intCast(r.week))) |_| {
                if (d + 7 >= time.daysIn(r.mon, year)) {
                    break;
                }
                d += 7;
            }

            const idx = @as(usize, @intCast(r.mon));
            d += @as(i32, @intCast(time.daysBefore[idx - 1]));
            if (time.isLeap(year) and r.mon > 2) {
                d += 1;
            }
            s = d * std.time.s_per_day;
        },
    }

    return s + r.time - off;
}

fn BigNResult(comptime T: type) type {
    return struct {
        ok: bool,
        val: T,
    };
}

fn big4(data: []const u8, start: usize) BigNResult(u32) {
    if (data.len < start + 4) return .{ .ok = false, .val = 0 };
    const p = data[start .. start + 4];
    if (p.len < 4) {
        return .{ .ok = false, .val = 0 };
    }

    const b0 = @as(u32, @intCast(p[3]));
    const b8 = @as(u32, @intCast(p[2])) << 8;
    const b16 = @as(u32, @intCast(p[1])) << 16;
    const b24 = @as(u32, @intCast(p[0])) << 24;

    return .{ .ok = true, .val = (b0 | b8 | b16 | b24) };
}

fn big8(data: []const u8, start: usize) BigNResult(u64) {
    const n1 = big4(data, start);
    if (!n1.ok) {
        return .{ .ok = false, .val = 0 };
    }

    const n2 = big4(data, start + 4);
    if (!n2.ok) {
        return .{ .ok = false, .val = 0 };
    }
    const b16 = @as(u64, @intCast(n1.val)) << 32;
    const b32 = @as(u64, @intCast(n2.val));

    return .{ .ok = true, .val = b16 | b32 };
}