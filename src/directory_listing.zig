const zap = @import("zap");
const zdt = @import("zdt");

const std = @import("std");

const Allocator = std.mem.Allocator;
const ArrayListUnmanaged = std.ArrayListUnmanaged;
const FormatOptions = std.fmt.FormatOptions;

const util = @import("util.zig");
const log = @import("main.zig").log;

const HtmlEscape = struct {
    inner: []const u8,

    pub fn format(self: HtmlEscape, comptime fmt: []const u8, opts: FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = opts;
        for (self.inner) |c| {
            switch (c) {
                '&' => try writer.writeAll("&amp;"),
                '<' => try writer.writeAll("&lt;"),
                '>' => try writer.writeAll("&gt;"),
                '"' => try writer.writeAll("&quot;"),
                '\'' => try writer.writeAll("&#39;"),
                else => try writer.writeByte(c),
            }
        }
    }
};

fn htmlEscape(str: []const u8) HtmlEscape {
    return HtmlEscape{ .inner = str };
}

const MaybeSize = struct {
    size: ?u64,
    pub fn format(self: MaybeSize, comptime fmt: []const u8, opts: FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = opts;
        if (self.size) |sz| {
            try writer.print("{}", .{sz});
        } else {
            try writer.writeAll("-");
        }
    }
};

const DatetimeOrError = struct {
    err: ?[]const u8,
    time: zdt.Datetime,

    const Self = @This();

    fn fromErr(e: anyerror) Self {
        return .{
            .err = @errorName(e),
            .time = undefined,
        };
    }

    fn fromTime(t: zdt.Datetime) Self {
        return .{
            .err = null,
            .time = t,
        };
    }

    pub fn format(self: Self, comptime fmt: []const u8, opts: FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = opts;
        if (self.err) |msg| {
            try writer.print(
                \\<span class="e">{}</span>
            , .{htmlEscape(msg)});
        } else {
            try writer.print(
                \\{%Y %b %d} {d:0>2}:{d:0>2}
            , .{
                self.time,
                self.time.hour,
                self.time.minute,
            });
        }
    }
};

const DirEntry = struct {
    name: []u8,
    access_error: ?anyerror,
    is_dir: bool,
    size: u64,
    mtime: zdt.Datetime,

    const AccessError = std.fs.Dir.StatFileError || zdt.ZdtError;
    const GetEntriesError = std.fs.Dir.OpenError || std.fs.Dir.Iterator.Error || error{OutOfMemory};

    fn lessThan(ctx: void, a: DirEntry, b: DirEntry) bool {
        _ = ctx;
        return (a.is_dir and !b.is_dir) or
            (a.is_dir == b.is_dir and std.mem.lessThan(u8, a.name, b.name));
    }

    fn getSize(self: DirEntry) MaybeSize {
        return .{
            .size = if (self.access_error == null and !self.is_dir)
                self.size
            else
                null,
        };
    }

    fn getMtime(self: DirEntry) DatetimeOrError {
        if (self.access_error) |e| return .fromErr(e);
        return .fromTime(self.mtime);
    }
};

fn getEntries(arena: Allocator, filesystem_path: []const u8) DirEntry.GetEntriesError!ArrayListUnmanaged(DirEntry) {
    var dir = try std.fs.cwd().openDir(filesystem_path, .{ .iterate = true });
    defer dir.close();

    var entries = ArrayListUnmanaged(DirEntry){};

    var iter = dir.iterateAssumeFirstIteration();
    while (try iter.next()) |posix_entry| {
        const name = try arena.dupe(u8, posix_entry.name);
        const entry = try entries.addOne(arena);
        entry.* = .{
            .name = name,
            .access_error = null,
            .is_dir = posix_entry.kind == .directory,
            .size = undefined,
            .mtime = undefined,
        };
        const stat = dir.statFile(posix_entry.name) catch |e| {
            entry.access_error = e;
            continue;
        };
        const mtime = zdt.Datetime.fromUnix(stat.mtime, .nanosecond, null) catch |e| {
            entry.access_error = e;
            continue;
        };
        entry.size = stat.size;
        entry.mtime = mtime;
    }

    std.sort.pdq(DirEntry, entries.items, {}, DirEntry.lessThan);
    return entries;
}

pub fn serveDirectoryIndex(
    arena: Allocator,
    short_path: []const u8,
    filesystem_path: []const u8,
    req: zap.Request,
) !void {
    var buf = try std.ArrayListUnmanaged(u8).initCapacity(arena, 8192);
    const writer = buf.writer(arena);

    try writer.print(
        \\<!DOCTYPE html>
        \\<html>
        \\<head>
        \\  <title>Index of /{0}{1s}</title>
        \\  <meta charset="utf-8">
        \\  <style>
        \\    h1{{margin-top:0;}}
        \\    table{{font-family:monospace;border-collapse:collapse;}}
        \\    .a{{max-width:60em;overflow-x:hidden;text-overflow:ellipsis;text-wrap:nowrap;}}
        \\    .stat{{padding-left:2em;padding-right:2em;}}
        \\    .sz{{text-align:right;}}
        \\    .e{{background-color:#eaa;}}
        \\  </style>
        \\</head>
        \\<body>
        \\<h1>Index of /{0}{1s}</h1>
        \\<hr>
        \\<table>
        \\
    , .{
        htmlEscape(short_path),
        if (short_path.len > 0) "/" else "",
    });
    if (short_path.len > 0) {
        try writer.writeAll(
            \\<tr><td class="a"><a href="../">../</a></td></tr>
            \\
        );
    }

    const entries = try getEntries(arena, filesystem_path);
    for (entries.items) |entry| {
        const entry_name_encoded = try util.urlPercentEncode(arena, entry.name);
        try writer.print(
            \\<tr>
        ++
            \\<td class="a"><a href="./{[encoded_name]}{[slash]s}">{[name]s}{[slash]s}</a></td>
        ++
            \\<td class="stat">{[mtime_or_error]}</td>
        ++
            \\<td class="sz">{[size]}</td>
        ++
            \\</tr>
            \\
        , .{
            .encoded_name = htmlEscape(entry_name_encoded.items),
            .name = htmlEscape(entry.name),
            .slash = @as([]const u8, if (entry.is_dir) "/" else ""),
            .mtime_or_error = entry.getMtime(),
            .size = entry.getSize(),
        });
    }

    try writer.writeAll(
        \\</table>
        \\<hr>
        \\</body>
        \\</html>
    );
    try req.sendBody(buf.items);
}
