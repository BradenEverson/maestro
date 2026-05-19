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

const STATUS_META: u8 = 0xFF;
const META_EOT: u8 = 0x2F;
const META_SET_TEMPO: u8 = 0x51;
const META_SET_TIME_SIGNATURE: u8 = 0x58;

const STATUS_SYSEX1: u8 = 0xF0;
const STATUS_SYSEX2: u8 = 0xF7;

const NOTE_OFF: u8 = 0x80;
const NOTE_ON: u8 = 0x90;
const POLYPHONIC_KEY_PRESSURE: u8 = 0xA0;
const CONTROL_CHANGE: u8 = 0xB0;
const PROGRAM_CHANGE: u8 = 0xC0;

pub const MTrkEvent = struct {
    delta_time: u32,
    event: Event,

    pub fn fromBytes(
        bytes: []const u8,
    ) !struct { MTrkEvent, []const u8 } {
        const dt, var rest = chunk.readVarLen(bytes);

        const status = rest[0];
        rest = rest[1..];

        if (status == STATUS_META) {
            const code: u8 = rest[0];
            rest = rest[1..];
            const meta_len, rest = chunk.readVarLen(rest);

            switch (code) {
                META_EOT => {
                    rest = rest[meta_len..];
                    return .{
                        .{
                            .delta_time = dt,
                            .event = .{ .meta = .end_of_track },
                        },
                        rest,
                    };
                },

                META_SET_TEMPO => {
                    const tempo, rest = chunk.bufferedIntRead(u24, rest);
                    return .{
                        .{
                            .delta_time = dt,
                            .event = .{ .meta = .{
                                .set_tempo = tempo,
                            } },
                        },
                        rest,
                    };
                },

                META_SET_TIME_SIGNATURE => {
                    const nn, rest = chunk.bufferedIntRead(u8, rest);
                    const dd, rest = chunk.bufferedIntRead(u8, rest);
                    const cc, rest = chunk.bufferedIntRead(u8, rest);
                    const bb, rest = chunk.bufferedIntRead(u8, rest);

                    return .{
                        .{
                            .delta_time = dt,
                            .event = .{ .meta = .{
                                .time_signature = .{
                                    .numerator = nn,
                                    .denominator = dd,
                                    .clocks_per_click = cc,
                                    .notes_in_quarter_note = bb,
                                },
                            } },
                        },
                        rest,
                    };
                },

                else => {
                    rest = rest[meta_len..];
                    return .{
                        .{
                            .delta_time = dt,
                            .event = .ignored,
                        },
                        rest,
                    };
                },
            }
        }

        if (status == STATUS_SYSEX1 or
            status == STATUS_SYSEX2)
        {
            const sysex_len, rest = chunk.readVarLen(rest);
            rest = rest[sysex_len..];
            return .{ .{
                .delta_time = dt,
                .event = .ignored,
            }, rest };
        }

        const kind = status & 0xF0;
        const channel = status & 0x0F;

        switch (kind) {
            NOTE_OFF => {
                const key = rest[0];
                const vel = rest[1];
                rest = rest[2..];
                return .{ .{
                    .delta_time = dt,
                    .event = .{
                        .midi = .{ .note_off = .{
                            channel,
                            .{
                                .key = key,
                                .velocity = vel,
                            },
                        } },
                    },
                }, rest };
            },
            NOTE_ON => {
                const key = rest[0];
                const vel = rest[1];
                rest = rest[2..];
                const midi_event: MidiEvent = if (vel == 0)
                    .{ .note_off = .{ channel, .{
                        .key = key,
                        .velocity = 0,
                    } } }
                else
                    .{ .note_on = .{ channel, .{
                        .key = key,
                        .velocity = vel,
                    } } };
                return .{ .{
                    .delta_time = dt,
                    .event = .{
                        .midi = midi_event,
                    },
                }, rest };
            },
            0xA0, 0xB0, 0xE0 => {
                rest = rest[2..];
            },
            0xC0, 0xD0 => {
                rest = rest[1..];
            },
            else => {},
        }

        return .{ .{
            .delta_time = dt,
            .event = .ignored,
        }, rest };
    }
};

pub const Event = union(enum) {
    midi: MidiEvent,
    meta: MetaEvent,
    ignored,
    // We do not care about the other
    // variants for now :(
};

pub const MetaEvent = union(enum) {
    time_signature: struct {
        numerator: u8,
        denominator: u8,
        clocks_per_click: u8,
        notes_in_quarter_note: u8,
    },
    set_tempo: u24,
    end_of_track,
};

pub const MidiEvent = union(enum) {
    note_off: struct { u8, NoteMeta },
    note_on: struct { u8, NoteMeta },
    // We do not care about the
    // other variants for now :(
};

pub const NoteMeta = struct {
    key: u8,
    velocity: u8,
};
