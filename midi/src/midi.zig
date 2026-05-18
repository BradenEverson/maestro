//! The MIDI file stored as a whole

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const HeaderChunk = @import("chunk.zig").HeaderChunk;
pub const TrackChunk = @import("chunk.zig").TrackChunk;

pub const MidiError = error{
    WrongTag,
    TODO,
};

/// The very first chunk defines the format of the rest
/// of the chunks and how many chunks are expected
header: HeaderChunk,

/// The remaining chunks describe the different tracks
/// of the audio
tracks: []const TrackChunk,

const MIDI = @This();

pub fn deinit(
    midi: *MIDI,
    alloc: Allocator,
) void {
    alloc.free(midi.tracks);
}

pub fn fromBytes(
    alloc: Allocator,
    bytes: []const u8,
) !MIDI {
    var rest = bytes;
    // Parse the header, this will give us number of tracks
    const header, rest = try HeaderChunk
        .fromBytes(rest);

    // Allocate amount of tracks the header specified,
    // then parse each track out
    const tracks = try alloc.alloc(
        TrackChunk,
        @as(usize, header.ntrks),
    );
    errdefer alloc.free(tracks);

    for (tracks) |*track| {
        track.*, rest = try TrackChunk.fromBytes(
            alloc,
            rest,
        );
    }

    return .{
        .header = header,
        .tracks = tracks,
    };
}
