// SPDX-License-Identifier: 0BSD
// SPDX-FileCopyrightText: 2025 zavexeon <zave@zave.codes>

// The values used in this source code, such as magic numbers, ioctl return values, etc are pulled from:
// https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/tree/include/linux/cdrom.h
//
// Also see: https://docs.kernel.org/userspace-api/ioctl/cdrom.html

const std = @import("std");
const errno = std.posix.errno;

/// Represents a physical optical drive in a system and provides an interface for interacting specifically with that
/// drive. Call .init() to get an instance of this struct.
const Drive = @This();

file_descriptor: std.posix.fd_t,

pub const OpenMode = enum {
    read_only,
    write_only,
    read_write,
};

pub const Options = struct {
    device_path: []const u8,
    open_mode: OpenMode,
};

/// Don't forget to call .deinit() when you're done.
pub fn init(options: Options) std.posix.OpenError!Drive {
    const flags = switch (options.open_mode) {
        .read_only => std.posix.O{ .ACCMODE = .RDONLY, .NONBLOCK = true },
        .write_only => std.posix.O{ .ACCMODE = .WRONLY, .NONBLOCK = true },
        .read_write => std.posix.O{ .ACCMODE = .WRONLY, .NONBLOCK = true },
    };

    const fd = try std.posix.open(options.device_path, flags, 0);

    return Drive{
        .file_descriptor = fd,
    };
}

pub fn deinit(self: *const Drive) void {
    std.posix.close(self.file_descriptor);
}

/// Magic numbers for ioctl commands. These may not all be implemented in this wrapper library.
const IoctlCommand = enum(u32) {
    /// CDROMPAUSE
    pause_audio = 0x5301,
    /// CDROMRESUME
    resume_audio = 0x5302,
    /// CDROMPLAYMSF
    play_msf = 0x5303,
    /// CDROMPLAYTRKIND
    play_track_index = 0x5304,
    /// CDROMREADTOCHDR
    read_toc_header = 0x5305,
    /// CDROMREADTOCENTRY
    read_toc_entry = 0x5306,
    /// CDROMSTOP
    stop_drive = 0x5307,
    /// CDROMSTART
    start_drive = 0x5308,
    /// CDROMEJECT
    eject = 0x5309,
    /// CDROMVOLCTRL
    volume_control = 0x530a,
    /// CDROMSUBCHNL
    read_subchannel_data = 0x530b,
    /// CDROMREADMODE2
    read_mode_2_data = 0x530c,
    /// CDROMREADMODE1
    read_mode_1_data = 0x530d,
    /// CDROMREADAUDIO
    read_audio = 0x530e,
    /// CDROMEJECT_SW
    auto_eject = 0x530f,
    /// CDROMMULTISESSION
    get_last_session_address = 0x5310,
    /// CDROM_GET_MCN
    get_mcn = 0x5311,
    /// CDROMRESET
    hard_reset = 0x5312,
    /// CDROMVOLREAD
    get_volume = 0x5313,
    /// CDROMREADRAW
    read_raw_mode = 0x5314,
    /// CDROMREADCOOKED
    read_cooked_mode = 0x5315,
    /// CDROMSEEK
    seek_msf_address = 0x5316,
    /// CDROMPLAYBLK
    play_logical_block_mode = 0x5317,
    /// CDROMREADALL
    read_all = 0x5318,
    /// CDROMGETSPINDOWN
    get_spindown_time = 0x531d, // apparently completely deprecated in the linux kernel, here for completion sake
    /// CDROMSETSPINDOWN
    set_spindown_time = 0x531e, // deprecated like CDROMGETSPINDOWN
    /// CDROMCLOSETRAY
    close_tray = 0x5319,
    /// CDROM_SET_OPTIONS
    set_options = 0x5320,
    /// CDROM_CLEAR_OPTIONS
    clear_options = 0x5321,
    /// CDROM_SELECT_SPEED
    set_speed = 0x5322,
    /// CDROM_SELECT_DISC
    select_disc = 0x5323,
    /// CDROM_MEDIA_CHANGED
    check_if_media_changed = 0x5325,
    /// CDROM_DRIVE_STATUS
    get_drive_status = 0x5326,
    /// CDROM_DISC_STATUS
    get_disc_status = 0x5327,
    /// CDROM_CHANGER_NSLOTS
    get_slots_count = 0x5328,
    /// CDROM_LOCKDOOR
    lock_door = 0x5329,
    /// CDROM_DEBUG
    debug_messages = 0x5330,
    /// GET_CAPABILITY
    get_capabilities = 0x5331,
    /// CDROMAUDIOBUFSIZ
    set_audio_buffer_size = 0x5382,
    /// DVD_READ_STRUCT
    dvd_read_struct = 0x5390,
    /// DVD_WRITE_STRUCT
    dvd_write_struct = 0x5391,
    /// DVD_AUTH
    dvd_auth = 0x5392,
    /// CDROM_SEND_PACKET
    send_packet = 0x5393,
    /// CDROM_NEXT_WRITABLE
    get_next_writable_block = 0x5394,
    /// CDROM_LAST_WRITTEN
    get_last_written_block = 0x5395,
    /// CDROM_TIMED_MEDIA_CHANGE
    get_last_media_change_timestamp = 0x5396,
};

/// Simple wrapper for calling ioctl. If libc is linked we use the libc implementation, this should allow this code to
/// run on any POSIX compliant system assuming Zig supports it. For Linux we don't need to link libc because Zig has a
/// ioctl implementation for Linux in it's standard library.
fn ioctl(self: *const Drive, request: IoctlCommand, arg: usize) usize {
    const req = @intFromEnum(request);
    if (@import("builtin").link_libc) {
        return @intCast(std.c.ioctl(self.file_descriptor, @intCast(req), arg));
    } else {
        return std.os.linux.ioctl(self.file_descriptor, req, arg);
    }
}

pub const RequestError = error{
    not_supported,
    invalid_drive_slot,
    out_of_memory,
    drive_busy,
    unexpected_error,
};

pub const DriveStatus = enum(u4) {
    no_info = 0,
    no_disc = 1,
    tray_open = 2,
    not_ready = 3,
    disc_ok = 4,
};

/// Internal helper function to handle edge case for an unexpected errno and return a generic unexpected error value.
/// Maybe we should call @panic instead of passing the error to the user?
fn handleUnexpectedErrno(err: std.posix.E) RequestError {
    std.posix.unexpectedErrno(err) catch {};
    return error.unexpected_error;
}

/// Get status of drive. Wraps CDROM_DRIVE_STATUS ioctl.
pub fn getStatus(self: *const Drive) RequestError!DriveStatus {
    const ret = self.ioctl(.get_drive_status, 0);
    return switch (errno(ret)) {
        .SUCCESS => @enumFromInt(ret),
        .NOSYS => error.not_supported,
        .INVAL => error.invalid_drive_slot,
        .NOMEM => error.out_of_memory,
        else => |err| handleUnexpectedErrno(err),
    };
}

/// Eject disc/tray. Wraps CDROMEJECT ioctl.
pub fn eject(self: *const Drive) RequestError!void {
    const ret = self.ioctl(.eject, 0);
    return switch (errno(ret)) {
        .SUCCESS => return,
        .NOSYS => error.not_supported,
        .BUSY => error.drive_busy,
        else => |err| handleUnexpectedErrno(err),
    };
}

/// Closes tray. Wraps CDROMCLOSETRAY ioctl.
pub fn closeTray(self: *const Drive) RequestError!void {
    const ret = self.ioctl(.close_tray, 0);
    return switch (errno(ret)) {
        .SUCCESS => return,
        .NOSYS => error.not_supported,
        .BUSY => error.drive_busy,
        else => |err| handleUnexpectedErrno(err),
    };
}

/// Get the media catalog number. Wraps CDROM_GET_MCN.
pub fn getMediaCatalogNumber(self: *const Drive) RequestError!usize {
    const ret = self.ioctl(.get_mcn, 0);
    return switch (errno(ret)) {
        .NOSYS => error.not_supported,
        else => ret,
    };
}

const CapabilityFlags = enum(u32) {
    close_tray = 0x1,
    open_tray = 0x2,
    lock = 0x4,
    select_speed = 0x8,
    select_disc = 0x10,
    multi_session = 0x20,
    mcn = 0x40,
    media_changed = 0x80,
    play_audio = 0x100,
    reset = 0x200,
    drive_status = 0x800,
    generic_packet = 0x1000,
    cd_r = 0x2000,
    cd_rw = 0x4000,
    dvd = 0x8000,
    dvd_r = 0x10000,
    dvd_ram = 0x20000,
    mo_drive = 0x40000,
    mrw = 0x80000,
    mrw_w = 0x100000,
    ram = 0x200000,
};

pub const Capabilities = packed struct {
    close_tray: bool,
    open_tray: bool,
    lock: bool,
    select_speed: bool,
    select_disc: bool,
    multi_session: bool,
    mcn: bool,
    media_changed: bool,
    play_audio: bool,
    reset: bool,
    drive_status: bool,
    generic_packet: bool,
    cd_r: bool,
    cd_rw: bool,
    dvd: bool,
    dvd_r: bool,
    dvd_ram: bool,
    mo_drive: bool,
    mrw: bool,
    mrw_w: bool,
    ram: bool,
};

/// Get the capabilities of the drive. Wraps CDROM_GET_CAPABILITY ioctl.
pub fn getCapabilities(self: *const Drive) Capabilities {
    const ret = self.ioctl(.get_capabilities, 0);
    var caps = std.mem.zeroInit(Capabilities, .{});

    // TODO - the CDROM_GET_CAPABILITY ioctl doesn't have any defined error returns. This means we can't rely on the
    // syscall to let us know if something went wrong. I should maybe add some sort of validation to make sure the
    // returned mask looks correct and return some kind of error if it doesn't.

    inline for (@typeInfo(Capabilities).@"struct".fields) |field| {
        const flag = @intFromEnum(@field(CapabilityFlags, field.name));
        @field(caps, field.name) = ret & flag != 0;
    }

    return caps;
}
