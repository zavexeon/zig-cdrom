// SPDX-License-Identifier: 0BSD
// SPDX-FileCopyrightText: 2025 zavexeon <zave@zave.codes>

const std = @import("std");
const cdrom = @import("./cdrom.zig");

fn toggleTray(d: *const cdrom.Drive) !void {
    const status = try d.getStatus();
    switch (status) {
        .no_info => return,
        .tray_open => {
            std.debug.print("{s}", .{"Closing the tray."});
            try d.closeTray();
        },
        else => {
            std.debug.print("{s}", .{"Opening the tray."});
            try d.eject();
        },
    }
}

pub fn main() !void {
    const drive = try cdrom.Drive.init(.{ .device_path = "/dev/sr0", .open_mode = .read_only });
    try toggleTray(&drive);
}
