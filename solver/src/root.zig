//! Solver responsible for translating sequence of MIDI events
//! into maestro events that can include moving the servos

const std = @import("std");
const Allocator = std.mem.Allocator;

const Midi = @import("midi");

const OCTAVE_SIZE: usize = 12;
const PIANO_LEN: usize = 61;
const HANDS: usize = 2;

/// Black keys require that a hand be octave
/// aligned, if we need to reach one we must
/// ensure this alignment before knowing we
/// can actuate
fn isBlackKey(key: usize) bool {
    const black_keys_octave =
        &[_]usize{ 1, 3, 6, 8, 10 };

    const octave_idx = key % OCTAVE_SIZE;

    return std.mem.find(
        usize,
        black_keys_octave,
        &[_]usize{octave_idx},
    ) != null;
}

pub const MaestroProgram = struct {
    tempo: u24 = 0,
    instructions: std.ArrayList(Instruction) = .empty,

    pub fn deinit(
        mp: *MaestroProgram,
        alloc: Allocator,
    ) void {
        mp.instructions.deinit(alloc);
    }
};

pub const Instruction = struct {
    delta_time: usize,
    cmd: MaestroCommand,
};

pub const MaestroCommand = union(enum) {
    note_on: usize,
    note_off: usize,
    move_hand: struct {
        /// Hand index
        hand: usize,
        direction: enum { left, right },
        /// Number of white keys to move in that
        /// direction
        white_keys: usize,
    },
};

pub const SolverError = Allocator.Error;

pub const HandInfo = struct {
    index: usize,
    pressing: [HANDS]bool = @splat(false),
};

pub const Solver = struct {
    hands: [HANDS]HandInfo = [HANDS]HandInfo{
        // First hand homes on the leftmost spot
        .{ .index = 0 },

        // Second hand homes on the rightmost spot
        .{ .index = 60 - OCTAVE_SIZE },
    },

    fn isOctaveAligned(hand: usize) bool {
        return hand % OCTAVE_SIZE == 0;
    }

    fn handsCover(
        s: *Solver,
        note: usize,
    ) bool {
        for (s.hands) |hand| {
            if (hand <= note and
                hand + OCTAVE_SIZE >= hand)
                return true;
        }

        return false;
    }

    pub fn solve(
        solver: *Solver,
        alloc: Allocator,
        stream: []Midi.TrackChunk.MTrkEvent,
    ) SolverError!MaestroProgram {
        _ = solver;

        var program: MaestroProgram = .{};
        errdefer program.deinit(alloc);

        var timer_sim: usize = 0;

        for (stream) |evt| {
            switch (evt.event) {
                .midi => |m| switch (m) {
                    .note_on => {},
                    .note_off => {},
                },
                .meta => |m| switch (m) {
                    .set_tempo => |tempo| {
                        program.tempo = tempo;
                    },
                    .end_of_track => break,
                },
                else => {},
            }

            timer_sim += evt.delta_time;
        }

        return program;
    }
};

test "black key identification" {
    // Selecting the highest octave
    try std.testing.expect(isBlackKey(58));
    try std.testing.expect(isBlackKey(56));
    try std.testing.expect(isBlackKey(54));

    try std.testing.expect(isBlackKey(51));
    try std.testing.expect(isBlackKey(49));
}
