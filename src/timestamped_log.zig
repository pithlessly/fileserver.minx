const zdt = @import("zdt");

const std = @import("std");
const log = std.log;

fn lossy_now() zdt.Datetime {
    return zdt.Datetime.now(null) catch zdt.Datetime.epoch;
}

const ansi_bold_red = "\x1b[91;1m";
const ansi_bold_green = "\x1b[92;1m";
const ansi_bold_yellow = "\x1b[93;1m";
const ansi_bold_blue = "\x1b[94;1m";
const ansi_reset = "\x1b[m";

fn log_color(lvl: std.log.Level) []const u8 {
    return switch (lvl) {
        .err => ansi_bold_red,
        .warn => ansi_bold_yellow,
        .info => ansi_bold_blue,
        .debug => ansi_bold_green,
    };
}

pub fn log_with_timestamp(
    comptime message_level: std.log.Level,
    comptime scope: @Type(.enum_literal),
    comptime format: []const u8,
    args: anytype,
) void {
    const now = lossy_now();
    const level_txt = comptime log_color(message_level) ++ message_level.asText() ++ ansi_reset;
    const prefix2 = if (scope == .default) ": " else "(" ++ @tagName(scope) ++ "): ";
    const stderr = std.io.getStdErr().writer();
    var bw = std.io.bufferedWriter(stderr);
    const writer = bw.writer();

    std.debug.lockStdErr();
    defer std.debug.unlockStdErr();
    nosuspend {
        writer.print(
            "[{:.3}] " ++ level_txt ++ prefix2 ++ format ++ "\n",
            .{now} ++ args,
        ) catch return;
        bw.flush() catch return;
    }
}
