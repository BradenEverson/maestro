//! Header Chunk Definition

const std = @import("std");
const chunk = @import("../chunk.zig");

/// The overall organization of the MIDI file.
/// Only three values are valid, making most of the 16
/// bits irrelevant
pub const Format = enum(u16) {
    /// The file contains a single multi-channel track
    Zero = 0,
    /// The file contains one or more simultaneous
    /// tracks (or MIDI outputs) of a sequence
    One = 1,
    /// The file contains one or more sequentially
    /// independent single-track patterns
    Two = 2,
};

/// The meaning of the delta-times in the MIDI sequence,
pub const Division = union(enum) {
    /// When bit 15 is a 0, bits 14-0 represent
    /// ticks per quarter note
    metrical: u16,
    /// When bit 15 is 1, bits 14-8 represent the
    /// negative SMPTE format, and bits 7-0 represent
    /// ticks per frame
    time_code: SmpteTicks,

    const DIVISION_MASK: u16 = 0x7FFF;

    pub fn fromU16(num: u16) Division {
        const masked = num & DIVISION_MASK;
        const msb = num >> 15;

        if (msb == 0) {
            return .{ .metrical = masked };
        } else {
            const tpf: u8 = @truncate(masked);
            const smpte: u7 = @truncate(masked >> 8);
            const smpte_i: i7 = @bitCast(smpte);

            return .{ .time_code = .{
                .smpte = smpte_i,
                .tpf = tpf,
            } };
        }
    }
};

/// Division defined by time-code-based time
pub const SmpteTicks = struct {
    /// 7 bits of negative timecode
    smpte: i7,
    /// 8 bits of ticks per frame
    tpf: u8,
};

/// The format of the rest of the file
format: Format,
/// How many tracks we've got
ntrks: u16,
/// Time signature or division
division: Division,

const Header = @This();

pub fn fromBytes(
    bytes: []const u8,
) !struct { Header, []const u8 } {
    const chunk_header = bytes[0..4];

    if (!std.mem.eql(u8, chunk_header, chunk.HEADER_TAG))
        return error.WrongTag;

    var rest = bytes[4..];
    _, rest = chunk.bufferedIntRead(u32, rest);

    const format, rest = chunk.bufferedIntRead(u16, rest);
    const ntrks, rest = chunk.bufferedIntRead(u16, rest);
    const division, rest = chunk.bufferedIntRead(u16, rest);

    return .{
        .{
            .format = @enumFromInt(format),
            .ntrks = ntrks,
            .division = Division.fromU16(division),
        },
        rest,
    };
}
