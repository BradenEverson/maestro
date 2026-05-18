//! A MIDI chunk is either a Header or Track chunk

const std = @import("std");

pub const HeaderChunk = @import("chunk/header.zig");
pub const TrackChunk = @import("chunk/track.zig");

pub const HEADER_TAG: []const u8 = "MThd";
pub const TRACK_TAG: []const u8 = "MTrk";

pub fn bufferedIntRead(comptime T: type, bytes: []const u8) struct { T, []const u8 } {
    if (@typeInfo(T) != .int)
        @compileError("Buffered Read must target an Int type");

    const t_bits = @typeInfo(T).int.bits;
    if (t_bits % 8 != 0)
        @compileError("Buffered Read Int Type must be Byte aligned\n");

    const t_bytes = t_bits / 8;
    const t = std.mem.readInt(T, bytes[0..t_bytes], .big);
    return .{ t, bytes[t_bytes..] };
}
