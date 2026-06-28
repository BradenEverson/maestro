//! Solver responsible for translating sequence of MIDI events
//! into maestro events that can include moving the servos

const std = @import("std");
const Allocator = std.mem.Allocator;
const Midi = @import("midi");
const OCTAVE_SIZE: usize = 12;
const PIANO_LEN: usize = 61;
const HANDS: usize = 1;

fn isBlackKey(key: usize) bool {
    const octave_idx = key % OCTAVE_SIZE;
    return switch (octave_idx) {
        1, 3, 6, 8, 10 => true,
        else => false,
    };
}

fn whiteKeysBefore(pos: usize) usize {
    var count: usize = 0;
    var i: usize = 0;
    while (i < pos) : (i += 1) {
        if (!isBlackKey(i)) count += 1;
    }
    return count;
}

fn whiteKeyDistance(from: usize, to: usize) i64 {
    const wb_from = whiteKeysBefore(from);
    const wb_to = whiteKeysBefore(to);
    return @as(i64, @intCast(wb_to)) - @as(i64, @intCast(wb_from));
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

pub const NoteInfo = struct {
    hand: usize,
    relative_note: usize,
};

pub const MaestroCommand = union(enum) {
    note_on: NoteInfo,
    note_off: NoteInfo,
    move_hand: struct {
        hand: usize,
        direction: enum { left, right },
        white_keys: usize,
    },
};

pub const SolverError = Allocator.Error || error{NoFreeHandAvailable};

pub const HandInfo = struct {
    index: usize,
    pressing: [OCTAVE_SIZE]bool = @splat(false),
};

pub const Solver = struct {
    hands: [HANDS]HandInfo = [HANDS]HandInfo{
        .{ .index = 0 },
    },

    fn isOctaveAligned(pos: usize) bool {
        return pos % OCTAVE_SIZE == 0;
    }

    fn handFree(s: *const Solver, hand: usize) bool {
        for (s.hands[hand].pressing) |pressing| {
            if (pressing) return false;
        }
        return true;
    }

    fn handsCover(s: *const Solver, note: usize) bool {
        for (s.hands) |hand| {
            if (hand.index <= note and
                hand.index + OCTAVE_SIZE > note)
                return true;
        }
        return false;
    }

    fn whichHandCovers(s: *const Solver, note: usize) ?NoteInfo {
        for (s.hands, 0..) |hand, hand_idx| {
            if (hand.index <= note and
                hand.index + OCTAVE_SIZE > note)
            {
                return .{
                    .hand = hand_idx,
                    .relative_note = note - hand.index,
                };
            }
        }
        return null;
    }

    fn targetPosition(note: usize) usize {
        const base = (note / OCTAVE_SIZE) * OCTAVE_SIZE;
        const max_pos = PIANO_LEN - OCTAVE_SIZE;
        return @min(base, max_pos);
    }

    fn emitMove(
        s: *Solver,
        alloc: Allocator,
        program: *MaestroProgram,
        hand_idx: usize,
        new_pos: usize,
    ) SolverError!void {
        const current = s.hands[hand_idx].index;
        if (current == new_pos) return;

        const dist = whiteKeyDistance(current, new_pos);
        if (dist == 0) {
            s.hands[hand_idx].index = new_pos;
            return;
        }

        try program.instructions.append(alloc, .{
            .delta_time = 0,
            .cmd = .{ .move_hand = .{
                .hand = hand_idx,
                .direction = if (dist > 0) .right else .left,
                .white_keys = @abs(dist),
            } },
        });
        s.hands[hand_idx].index = new_pos;
    }

    fn pickHand(s: *const Solver, note: usize) usize {
        for (s.hands, 0..) |_, i| {
            if (s.handFree(i)) return i;
        }
        var best: usize = 0;
        var best_dist: usize = std.math.maxInt(usize);
        for (s.hands, 0..) |hand, i| {
            const center = hand.index + OCTAVE_SIZE / 2;
            const dist = if (center >= note) center - note else note - center;
            if (dist < best_dist) {
                best_dist = dist;
                best = i;
            }
        }
        return best;
    }

    pub fn solve(
        solver: *Solver,
        alloc: Allocator,
        stream: []Midi.TrackChunk.MTrkEvent,
    ) SolverError!MaestroProgram {
        var program: MaestroProgram = .{};
        errdefer program.deinit(alloc);

        var timer_sim: usize = 0;

        for (stream) |evt| {
            switch (evt.event) {
                .midi => |m| switch (m) {
                    .note_on => |note_evt| {
                        const note = note_evt.@"1".key - 24;

                        if (!solver.handsCover(note)) {
                            const hand_idx = solver.pickHand(note);
                            const target = targetPosition(note);
                            try solver.emitMove(alloc, &program, hand_idx, target);
                        }

                        const info = solver.whichHandCovers(note) orelse
                            @panic("Allocation failed!!! No hands free");

                        solver.hands[info.hand].pressing[info.relative_note] = true;

                        try program.instructions.append(alloc, .{
                            .delta_time = timer_sim,
                            .cmd = .{ .note_on = info },
                        });
                        timer_sim = 0;
                    },

                    .note_off => |note_evt| {
                        const note = note_evt.@"1".key - 24;

                        if (solver.whichHandCovers(note)) |info| {
                            solver.hands[info.hand].pressing[info.relative_note] = false;

                            try program.instructions.append(alloc, .{
                                .delta_time = timer_sim,
                                .cmd = .{ .note_off = info },
                            });
                            timer_sim = 0;
                        }
                    },
                },

                .meta => |m| switch (m) {
                    .set_tempo => |tempo| {
                        program.tempo = tempo;
                    },
                    .end_of_track => break,
                    else => {},
                },

                else => {},
            }

            timer_sim += evt.delta_time;
        }

        return program;
    }
};

test "black key identification" {
    try std.testing.expect(isBlackKey(58));
    try std.testing.expect(isBlackKey(56));
    try std.testing.expect(isBlackKey(54));
    try std.testing.expect(isBlackKey(51));
    try std.testing.expect(isBlackKey(49));
}
