//! A MIDI chunk :D

pub const HeaderChunk = @import("chunk/header.zig");
pub const TrackChunk = @import("chunk/track.zig");

pub const Chunk = union(enum) {
    header: HeaderChunk,
    track: TrackChunk,
};
