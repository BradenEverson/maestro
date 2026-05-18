//! Track Chunk Definition

const std = @import("std");
const chunk = @import("../chunk.zig");

const Track = @This();

mtrk_events: std.ArrayList(MTrkEvent),

pub fn fromBytes(
    bytes: []const u8,
) !struct {
    Track,
    []const u8,
} {
    const chunk_header = bytes[0..4];

    if (!std.mem.eql(
        u8,
        chunk_header,
        chunk.TRACK_TAG,
    ))
        return error.WrongTag;

    var rest = bytes[4..];
    const len, rest =
        chunk.bufferedIntRead(u32, rest);

    std.debug.print("{} bytes\n", .{len});

    return error.TODO;
}

pub const MTrkEvent = struct {
    delta_time: u32,
    event: Event,
};

pub const Event = union(enum) {
    midi: MidiEvent,
    // We do not care about the other variants for now :(
    // sysex and meta events :(((
};

pub const MidiEvent = union(enum) {
    note_off: struct { u8, NoteMeta },
    note_on: struct { u8, NoteMeta },
    // We do not care about the other variants for now :(
};

pub const NoteMeta = struct {
    key: u8,
    velocity: u8,
};
