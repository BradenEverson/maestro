//! The MIDI file stored as a whole

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const HeaderChunk = @import("chunk.zig").HeaderChunk;
pub const TrackChunk = @import("chunk.zig").TrackChunk;

pub const MidiError = error{
    TODO,
};

/// The very first chunk defines the format of the rest of the chunks and
/// how many chunks are expected
header_chunk: HeaderChunk,

/// The remaining chunks describe the different tracks of the audio
chunks: []const TrackChunk,

const MIDI = @This();

pub fn deinit(midi: *MIDI, alloc: Allocator) void {
    alloc.free(midi.chunks);
}

pub fn tryFromBytes(bytes: []const u8) !MIDI {
    var rest = bytes;
    // Parse the header, this will give us number of tracks
    const header, rest = try HeaderChunk.fromBytes(rest);
    _ = header;

    // Allocate amount of tracks the header specified,
    // then parse each track out

    return error.TODO;
}
