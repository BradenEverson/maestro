//! Track Chunk Definition

const std = @import("std");

const Track = @This();

pub fn fromBytes(bytes: []const u8) !struct { Track, []const u8 } {
    _ = bytes;
    return error.TODO;
}
