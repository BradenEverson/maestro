//! A MIDI chunk is either a Header or Track chunk

pub const HeaderChunk = @import("chunk/header.zig");
pub const TrackChunk = @import("chunk/track.zig");
