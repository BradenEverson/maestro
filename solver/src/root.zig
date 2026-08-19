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

pub const Direction = enum(u32) {
    left = 0,
    right = 1,
};

pub const MaestroCommand = union(enum) {
    note_on: NoteInfo,
    note_off: NoteInfo,
    move_hand: struct {
        hand: usize,
        direction: Direction,
        white_keys: usize,
    },
};

pub const SolverError = Allocator.Error || error{NoFreeHandAvailable};

pub const HandInfo = struct {
    index: usize,
    pressing: [OCTAVE_SIZE]bool = @splat(false),

    pub fn isFree(hand: *const HandInfo) bool {
        for (hand.pressing) |key|
            if (key) return false;

        return true;
    }

    pub fn covers(hand: *const HandInfo, global_key: usize) bool {
        return (global_key >= hand.index) and
            (global_key < hand.index + OCTAVE_SIZE);
    }

    pub fn getKey(hand: *HandInfo, key: usize) *bool {
        return &hand.pressing[key];
    }

    pub fn getGlobalKey(hand: *HandInfo, global_key: usize) ?*bool {
        if (!hand.covers(global_key)) {
            return null;
        }

        return &hand.pressing[global_key - hand.index];
    }

    pub fn lowestUsed(hand: *const HandInfo) ?usize {
        if (!hand.isFree())
            return null;

        var idx: usize = 0;
        for (hand.pressing) |key| {
            if (key)
                break;

            idx += 1;
        }

        return idx;
    }
};

pub const Hand = enum {
    left,
    right,
};

pub const Solver = struct {
    left: HandInfo = .{ .index = 0 },
    right: HandInfo = .{ .index = PIANO_LEN - OCTAVE_SIZE },

    instructions: []Midi.TrackChunk.MTrkEvent,
    instruction_pointer: usize = 0,

    fn getHand(solver: *Solver, hand: Hand) *HandInfo {
        return switch (hand) {
            .left => &solver.left,
            .right => &solver.right,
        };
    }

    fn bounds(
        solver: *Solver,
        hand: Hand,
    ) ?struct { left: usize, right: usize } {
        var hand_choice = solver.getHand(hand).*;

        if (!hand_choice.isFree())
            // No bounds if we aren't yet bounded!
            return null;

        const lowest_closed: usize = hand_choice.lowestUsed().? + hand_choice.index;
        var highest_closed: usize = lowest_closed;

        var future_idx: usize = solver.instruction_pointer;
        while (hand_choice.isFree()) {
            const event = solver.instructions[future_idx];
            if (event.event == .midi) {
                const midi = event.event.midi;

                switch (midi) {
                    .note_on => |note| {
                        const key_if_covers = hand_choice
                            .getGlobalKey(@as(usize, note.@"1".key));

                        if (key_if_covers) |key| {
                            key.* = true;
                        }

                        highest_closed = @as(usize, note.@"1".key);
                    },

                    .note_off => |note| {
                        const key_if_covers = hand_choice
                            .getGlobalKey(@as(usize, note.@"1".key));

                        if (key_if_covers) |key| {
                            key.* = false;
                        }
                    },
                }
            } else if (event.event == .meta and
                event.event.meta == .end_of_track)
            {
                break;
            }
            future_idx += 1;
        }

        return .{
            .left = lowest_closed,
            .right = future_idx,
        };
    }

    pub fn feed(
        solver: *Solver,
        alloc: Allocator,
        program: *MaestroProgram,
    ) !void {
        _ = alloc;

        const event = solver.instructions[solver.instruction_pointer];

        switch (event.event) {
            .midi => |midi| switch (midi) {
                .note_on => |note_on| {
                    const key = note_on.@"1".key;
                    std.debug.print("{} {} on\n", .{ event.timestamp, key });

                    const key_if_covers = solver.left
                        .getGlobalKey(@as(usize, key));

                    if (key_if_covers) |k| {
                        k.* = true;
                    }

                    const new_bounds = solver.bounds(.left);
                    std.debug.print("{any}\n", .{new_bounds});
                },
                .note_off => |note_off| {
                    const key = note_off.@"1".key;
                    std.debug.print("{} {} off\n", .{ event.timestamp, key });

                    const key_if_covers = solver.left
                        .getGlobalKey(@as(usize, key));

                    if (key_if_covers) |k| {
                        k.* = false;
                    }

                    const new_bounds = solver.bounds(.left);
                    std.debug.print("{any}\n", .{new_bounds});
                },
            },
            .meta => |meta| switch (meta) {
                .set_tempo => |tempo| program.tempo = tempo,
                else => {},
            },
            .ignored => {},
        }

        solver.instruction_pointer += 1;
    }

    pub fn solve(solver: *Solver, alloc: Allocator, program: *MaestroProgram) !void {
        var timestamp: u32 = 0;

        for (solver.instructions) |*event| {
            event.timestamp = timestamp + event.delta_time;
            try solver.feed(alloc, program);
            timestamp += event.delta_time;
        }
    }
};

test "black key identification" {
    try std.testing.expect(isBlackKey(58));
    try std.testing.expect(isBlackKey(56));
    try std.testing.expect(isBlackKey(54));
    try std.testing.expect(isBlackKey(51));
    try std.testing.expect(isBlackKey(49));
}
