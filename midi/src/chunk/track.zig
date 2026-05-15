//! Track Chunk Definition

const std = @import("std");
const chunk = @import("../chunk.zig");

const Track = @This();

mtrk_events: std.ArrayList(MTrkEvent),

pub fn fromBytes(bytes: []const u8) !struct { Track, []const u8 } {
    const chunk_header = bytes[0..4];
    std.debug.print("{s}\n", .{chunk_header});

    if (!std.mem.eql(u8, chunk_header, chunk.TRACK_TAG))
        return error.WrongTag;

    return error.TODO;
}

pub const MTrkEvent = struct {};
