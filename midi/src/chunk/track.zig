//! Track Chunk Definition

const std = @import("std");
const Allocator = std.mem.Allocator;

const chunk = @import("../chunk.zig");

const Track = @This();

mtrk_events: std.ArrayList(MTrkEvent) = .empty,

pub fn deinit(self: *Track, alloc: Allocator) void {
    self.mtrk_events.deinit(alloc);
}

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
        rest,
    };
}

pub const MTrkEvent = struct {
    delta_time: u32,
    event: Event,

    pub fn fromBytes(
        bytes: []const u8,
    ) !struct { MTrkEvent, []const u8 } {
        const dt, var rest = chunk.readVarLen(bytes);

        const status = rest[0];
        rest = rest[1..];

        if (status == 0xFF) {
            rest = rest[1..];
            const meta_len, rest = chunk.readVarLen(rest);
            rest = rest[meta_len..];
            return .{ .{ .delta_time = dt, .event = .ignored }, rest };
        }

        if (status == 0xF0 or status == 0xF7) {
            const sysex_len, rest = chunk.readVarLen(rest);
            rest = rest[sysex_len..];
            return .{ .{ .delta_time = dt, .event = .ignored }, rest };
        }

        const kind = status & 0xF0;
        const channel = status & 0x0F;

        switch (kind) {
            0x80 => {
                const key = rest[0];
                const vel = rest[1];
                rest = rest[2..];
                return .{ .{
                    .delta_time = dt,
                    .event = .{
                        .midi = .{ .note_off = .{ channel, .{
                            .key = key,
                            .velocity = vel,
                        } } },
                    },
                }, rest };
            },
            0x90 => {
                const key = rest[0];
                const vel = rest[1];
                rest = rest[2..];
                const midi_event: MidiEvent = if (vel == 0)
                    .{ .note_off = .{ channel, .{ .key = key, .velocity = 0 } } }
                else
                    .{ .note_on = .{ channel, .{ .key = key, .velocity = vel } } };
                return .{ .{ .delta_time = dt, .event = .{ .midi = midi_event } }, rest };
            },
            0xA0, 0xB0, 0xE0 => {
                rest = rest[2..];
            },
            0xC0, 0xD0 => {
                rest = rest[1..];
            },
            else => {},
        }

        return .{ .{ .delta_time = dt, .event = .ignored }, rest };
    }
};

pub const Event = union(enum) {
    midi: MidiEvent,
    ignored,
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
