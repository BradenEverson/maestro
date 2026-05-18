//! Track Chunk Definition

const std = @import("std");
const Allocator = std.mem.Allocator;

const chunk = @import("../chunk.zig");

const Track = @This();

mtrk_events: std.ArrayList(MTrkEvent) = .empty,

pub fn fromBytes(
    alloc: Allocator,
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
    rest = rest[0..len];

    var result: Track = .{};

    while (rest.len > 0) {
        const event, rest = try MTrkEvent
            .fromBytes(rest);
        try result.mtrk_events.append(
            alloc,
            event,
        );
    }

    return .{
        result,
        rest[len..],
    };
}

pub const MTrkEvent = struct {
    delta_time: u32,
    event: Event,

    pub fn fromBytes(
        bytes: []const u8,
    ) !struct { MTrkEvent, []const u8 } {
        const dt = bytes[0];
        var rest = bytes[1..];

        const fb = rest[0];
        rest = rest[1..];

        std.debug.print("dt: {} - byte: {b}\n", .{ dt, fb });

        return error.TODO;
    }
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
