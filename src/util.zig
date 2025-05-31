const zap = @import("zap");

const std = @import("std");
const FormatOptions = std.fmt.FormatOptions;
const Allocator = std.mem.Allocator;
const ArrayListUnmanaged = std.ArrayListUnmanaged;

const Order = std.math.Order;

pub fn stripPrefix(comptime T: type, prefix: []const T, str: []const T) ?[]const T {
    return if (std.mem.startsWith(T, str, prefix))
        str[prefix.len..]
    else
        null;
}

test stripPrefix {
    try std.testing.expectEqualStrings(stripPrefix(u8, "fo", "foo").?, "o");
    try std.testing.expectEqualStrings(stripPrefix(u8, "", "foo").?, "foo");
    try std.testing.expectEqual(stripPrefix(u8, "ba", "foo"), null);
    try std.testing.expectEqual(stripPrefix(u8, "ba", "b"), null);
}

pub fn orderLexicographic(a: Order, b: Order) Order {
    return if (a != .eq) a else b;
}

pub fn urlPathPercentDecode(ally: Allocator, path: []const u8) !ArrayListUnmanaged(u8) {
    // add 1 for NUL terminator
    var buf = try ArrayListUnmanaged(u8).initCapacity(ally, path.len + 1);
    errdefer buf.deinit(ally);
    const size: isize = zap.fio.http_decode_path(buf.items.ptr, path.ptr, path.len);
    if (size < 0)
        return error.InvalidPercentEncoding;
    buf.items.len = @intCast(size);
    return buf;
}

pub fn urlPercentEncodeInto(ally: Allocator, str: []const u8, buf: *ArrayListUnmanaged(u8)) !void {
    for (str) |byte| {
        if (std.ascii.isAlphanumeric(byte) or switch (byte) {
            '-', '_', '~', '/', '.' => true,
            else => false,
        }) {
            try buf.append(ally, byte);
        } else {
            const ptr = try buf.addManyAsArray(ally, 3);
            ptr[0] = '%';
            ptr[1] = std.fmt.hex_charset[byte / 16];
            ptr[2] = std.fmt.hex_charset[byte % 16];
            // ptr[1] =
        }
    }
}

pub fn urlPercentEncode(ally: Allocator, str: []const u8) !ArrayListUnmanaged(u8) {
    var buf = try ArrayListUnmanaged(u8).initCapacity(ally, str.len);
    errdefer buf.deinit(ally);
    try urlPercentEncodeInto(ally, str, &buf);
    return buf;
}

test urlPathPercentDecode {
    const check = struct {
        fn check(input: []const u8, expected_result: anyerror![]const u8) !void {
            const ally = std.testing.allocator;
            if (urlPathPercentDecode(ally, input)) |actual_buf| {
                var buf = actual_buf;
                defer buf.deinit(ally);
                try std.testing.expectEqualSlices(u8, buf.items, try expected_result);
            } else |actual_error| {
                if (expected_result) |_| {
                    return actual_error;
                } else |expected_error| {
                    try std.testing.expectEqual(expected_error, actual_error);
                }
            }
        }
    };
    try check.check("%20", " ");
    try check.check("/_%2f%2F_/", "/_//_/");
    try check.check("%25%32%32", "%22");
    try check.check("%zz", error.InvalidPercentEncoding);
}

pub fn fileExtension(path: []const u8) []const u8 {
    const basename = std.fs.path.basename(path);
    const index = std.mem.lastIndexOfScalar(u8, basename, '.') orelse return path;
    return path[index..];
}

test fileExtension {
    std.testing.expectEqualSlices(u8, fileExtension("a/b.c/d"), "d");
    std.testing.expectEqualSlices(u8, fileExtension(""), "d");

    std.fs.cwd().readFile("...");
}

pub const HtmlEscape = struct {
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

pub fn htmlEscape(str: []const u8) HtmlEscape {
    return HtmlEscape{ .inner = str };
}
