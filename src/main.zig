const std = @import("std");
const zap = @import("zap");

const Allocator = std.mem.Allocator;
const assert = std.debug.assert;

const util = @import("util.zig");
const directory_listing = @import("directory_listing.zig");
const NameMap = @import("filetypes.zig").NameMap;
const htmlEscape = util.htmlEscape;

pub const std_options = std.Options{
    .logFn = @import("timestamped_log.zig").log_with_timestamp,
};

pub const log = std.log.scoped(.@"fileserver.minx");

fn requestPathIsValidFilePath(path: []const u8) bool {
    const State = enum {
        ok,
        @"/",
        @".",
        @"..",
    };
    var state: State = .@"/";
    for (path) |c| {
        if (c == '\x00') return false;
        switch (state) {
            .ok => if (c == '/') {
                state = .@"/";
            },
            .@"/" => switch (c) {
                '/' => return false,
                '.' => state = .@".",
                else => state = .ok,
            },
            .@"." => switch (c) {
                '/' => return false,
                '.' => state = .@"..",
                else => state = .ok,
            },
            .@".." => switch (c) {
                '/' => return false,
                else => state = .ok,
            },
        }
    }
    switch (state) {
        .ok, .@"/" => return true,
        .@".", .@".." => return false,
    }
}

test requestPathIsValidFilePath {
    try std.testing.expect(requestPathIsValidFilePath(""));
    try std.testing.expect(requestPathIsValidFilePath("foo"));
    try std.testing.expect(!requestPathIsValidFilePath("/foo"));
    try std.testing.expect(!requestPathIsValidFilePath("/"));
    try std.testing.expect(requestPathIsValidFilePath("foo/bar/"));
    try std.testing.expect(requestPathIsValidFilePath("foo/bar"));
    try std.testing.expect(!requestPathIsValidFilePath("foo//bar"));
    try std.testing.expect(!requestPathIsValidFilePath("foo/./bar"));
    try std.testing.expect(!requestPathIsValidFilePath("foo/../bar"));
    try std.testing.expect(requestPathIsValidFilePath("foo/.../bar"));
    try std.testing.expect(requestPathIsValidFilePath("foo/.c/bar"));
    try std.testing.expect(requestPathIsValidFilePath("foo/..c/bar"));
}

const Context = struct {
    executable_dir_path: []u8,
    artifact_dir_path: []const u8,
    filetypes: NameMap,

    fn init(ally: Allocator, filetypes: NameMap) !Context {
        const executable_dir_path = try std.fs.selfExeDirPathAlloc(ally);
        errdefer ally.free(executable_dir_path);
        const artifact_dir_path = std.fs.path.dirname(executable_dir_path).?;
        log.debug("artifact_dir_path={s}", .{artifact_dir_path});
        return .{
            .executable_dir_path = executable_dir_path,
            .artifact_dir_path = artifact_dir_path,
            .filetypes = filetypes,
        };
    }

    fn deinit(self: Context, ally: Allocator) void {
        ally.free(self.executable_dir_path);
    }
};

// const barebones_error_page =
//     \\<!DOCTYPE html>
//     \\<html>
//     \\<head><title>{s}</title></head>
//     \\<body>
//     \\<h1>{s}</h1>
//     \\<hr>
//     \\<p>{s}</p>
//     \\</body>
//     \\</html>
// ;

const FileEndpoint = struct {
    path: []const u8,
    prefix_to_strip: []const u8,
    dir_root: []const u8,
    error_strategy: zap.Endpoint.ErrorStrategy = .log_to_response,

    const Self = @This();

    fn new(path: []const u8, dir_root: []const u8) !Self {
        return Self{
            .path = path,
            .prefix_to_strip = if (path.len == 0) "/" else path,
            .dir_root = dir_root,
        };
    }

    fn deinit(self: *Self) void {
        _ = self;
    }

    fn send_404(_: *Self, req: zap.Request) !void {
        try req.setHeader("content-type", "text/plain; encoding=utf-8");
        req.setStatus(.not_found);
        try req.sendBody(
            \\404 not found
            \\[fs.minx]
        );
    }

    const Error = error{
        // ours
        BadRequest, // maps to 400
        Pandoc, // maps to 50x
        // general
        OutOfMemory,
        // zap
        HttpSendBody,
        HttpSetContentType,
        HttpSetHeader,
        HttpParseBody,
        SetCookie,
        SendFile,
        HttpIterParams,
        // filesystem failures - see std.fs.File.OpenError
        FileNotFound, // maps to 404
        NoSpaceLeft,
        IsDir, // maps to 404 in some contexts
        FileTooBig,
        DeviceBusy,
        AccessDenied, // maps to 403
        SystemResources,
        WouldBlock,
        NoDevice,
        Unexpected,
        SharingViolation,
        PathAlreadyExists,
        PipeBusy,
        NameTooLong, // maps to 404
        SymLinkLoop, // maps to 404
        ProcessFdQuotaExceeded,
        SystemFdQuotaExceeded,
        NotDir,
        FileLocksNotSupported,
        FileBusy,
        // WASI-specific, shouldn't happen
        InvalidUtf8,
        // Windows-specific, shouldn't happen
        InvalidWtf8,
        BadPathName,
        NetworkNotFound,
        AntivirusInterference,
    };

    fn highlightFile(
        arena: Allocator,
        ctx: *Context,
        language: []const u8,
        short_path: []const u8,
        filesystem_path: []const u8,
        req: zap.Request,
    ) Error!void {
        const result = std.process.Child.run(.{
            .allocator = arena,
            .argv = &[_][]const u8{
                "pandoc",
                "--indented-code-classes",
                language,
                "--from",
                try std.fmt.allocPrint(arena, "{s}/data/pandoc_highlight.lua", .{ctx.artifact_dir_path}),
                filesystem_path,
            },
            .max_output_bytes = 4 * 1024 * 1024,
        }) catch |err| {
            log.err("process.Child.run() returned {s}", .{@errorName(err)});
            return error.Pandoc;
        };
        const body = try std.fmt.allocPrint(
            arena,
            \\<!DOCTYPE html>
            \\<html>
            \\<head>
            \\  <title>/{[path]}</title>
            \\  <meta charset="utf-8">
            \\<style>
            \\{[css]s}
            \\</style>
            \\</head>
            \\<body>
            \\<h1>/{[path]}</h1>
            \\<hr>
            \\{[code]s}
            \\</body>
            \\</html>
            \\
        ,
            .{
                .path = htmlEscape(short_path),
                .css = @embedFile("./code.css"),
                .code = result.stdout,
            },
        );
        try req.sendBody(body);
    }

    fn try_get(self: *Self, ally: Allocator, arena: Allocator, ctx: *Context, req: zap.Request) Error!void {
        _ = ally;
        try req.setHeader("server", "fileserver.minx");
        log.debug("QUERY: {s}", .{req.query orelse "無"});

        const url_encoded_path = util.stripPrefix(u8, self.prefix_to_strip, req.path orelse "") orelse
            return error.BadRequest;

        var path_vec = util.urlPathPercentDecode(arena, url_encoded_path) catch |err| switch (err) {
            error.InvalidPercentEncoding => return error.BadRequest,
            error.OutOfMemory => |e| return e,
        };
        defer path_vec.deinit(arena);
        var path = path_vec.items;

        if (!requestPathIsValidFilePath(path)) return error.BadRequest;
        std.debug.assert(!(path.len > 0 and path[0] == '/')); // must be a relative path
        const path_ends_with_slash = path.len > 0 and path[path.len - 1] == '/';
        if (path_ends_with_slash) path.len -= 1;

        var buf: [std.fs.max_path_bytes]u8 = undefined;
        const filesystem_path = std.fmt.bufPrintZ(&buf, "{s}/{s}", .{ self.dir_root, path }) catch |err| switch (err) {
            error.NoSpaceLeft => return error.FileNotFound,
        };

        const file = std.fs.cwd().openFile(filesystem_path, .{}) catch |err| switch (err) {
            error.IsDir => return error.FileNotFound,
            else => |e| return e,
        };
        defer file.close();

        const stat = try file.stat();
        const is_dir = stat.kind == .directory;

        if (is_dir) {
            if (path.len > 0 and !path_ends_with_slash) {
                var redirect_location = std.ArrayListUnmanaged(u8){}; // percent-encoded
                try redirect_location.appendSlice(arena, self.path);
                try redirect_location.append(arena, '/');
                try util.urlPercentEncodeInto(arena, path, &redirect_location);
                try redirect_location.append(arena, '/');
                return req.redirectTo(redirect_location.items, .see_other);
            }
            return directory_listing.serveDirectoryIndex(arena, path, filesystem_path, req);
        }

        const filetype = ctx.filetypes.fileTypeFor(filesystem_path);
        log.info("successfully opened: {s} type: {any} :)", .{ filesystem_path, filetype });

        const highlight_lang = if (filetype) |ft| ft.highlightPandocLanguage() else null;
        if (highlight_lang) |language| {
            log.info("pandoc language: {s}", .{language});
            return Self.highlightFile(arena, ctx, language, path, filesystem_path, req);
        }

        try req.sendFile(filesystem_path);
    }

    pub fn get(self: *@This(), ally: Allocator, ctx: *Context, req: zap.Request) !void {
        var arena = std.heap.ArenaAllocator.init(ally);
        defer arena.deinit();
        return self.try_get(ally, arena.allocator(), ctx, req);
    }

    fn stub(self: *@This(), ally: Allocator, ctx: *Context, r: zap.Request) !void {
        _ = self;
        _ = ally;
        _ = ctx;
        r.setStatus(.bad_request);
    }

    pub const post = stub;
    pub const put = stub;
    pub const delete = stub;
    pub const patch = stub;
    pub const options = stub;
    pub const head = stub;
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const ally = gpa.allocator();

    var envs = try std.process.getEnvMap(ally);
    defer envs.deinit();
    const root_url_dir = envs.get("MINX_ROOT_URL_DIR") orelse {
        log.err("please pass MINX_ROOT_URL_DIR", .{});
        return error.MissingConfig;
    };

    var name_map_arena = std.heap.ArenaAllocator.init(ally);
    errdefer name_map_arena.deinit();
    const name_map = try NameMap.init(name_map_arena.allocator());
    log.info("successfully initialized name_map", .{});

    var ctx = try Context.init(ally, name_map);
    defer ctx.deinit(ally);

    var app = try zap.App.Create(Context).init(ally, &ctx, .{});
    defer app.deinit();
    var root_endpoint = try FileEndpoint.new("", root_url_dir);
    defer root_endpoint.deinit();

    try app.register(&root_endpoint);
    const port = 8041;
    app.listen(.{ .port = port }) catch |e| switch (e) {
        error.ListenError => {},
        else => return e,
    };
    log.info("Listening on port {}", .{port});
    zap.start(.{
        .threads = 2,
        .workers = 1,
    });
}
