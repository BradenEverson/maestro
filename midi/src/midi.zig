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
    _ = bytes;

    // TODO
    return error.TODO;
}
