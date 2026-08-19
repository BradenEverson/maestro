//! Solver responsible for translating sequence of MIDI events
//! into maestro events that can include moving the servos

const std = @import("std");
const Allocator = std.mem.Allocator;
const Midi = @import("midi");
const OCTAVE_SIZE: usize = 12;
const PIANO_LEN: usize = 61;
const HANDS: usize = 1;

const TIME_TO_MOVE_KEY: usize = 1; // time in ms it takes to move a single key

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

fn whiteKeyDistance(from: usize, to: usize) usize {
    const wb_from = whiteKeysBefore(from);
    const wb_to = whiteKeysBefore(to);

    if (from > to) {
        return wb_from - wb_to;
    } else {
        return wb_to - wb_from;
    }
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
        hand: Hand,
        direction: Direction,
        time: usize,
    },
};

pub const SolverError = Allocator.Error || error{NoFreeHandAvailable};

pub const HandInfo = struct {
    index: usize,
    pressing: [OCTAVE_SIZE]bool = @splat(false),

    pub fn timeToGetThere(hand: *const HandInfo, go_to: usize) usize {
        if (hand.covers(go_to)) {
            return 0;
        } else if (go_to > hand.index) {
            // Measure from the far end of the hand
            const earliest_to_get_there = hand.index + OCTAVE_SIZE;
            return whiteKeyDistance(earliest_to_get_there, go_to) * TIME_TO_MOVE_KEY;
        } else {
            // Move from left end of the hand
            return whiteKeyDistance(hand.index, go_to) * TIME_TO_MOVE_KEY;
        }
    }

    pub fn moveTo(hand: *HandInfo, go_to: usize) void {
        if (hand.covers(go_to)) {
            return;
        } else if (go_to > hand.index) {
            // Go from the far end of the hand
            hand.index = go_to - OCTAVE_SIZE;
        } else {
            // Move from early end of the hand
            hand.index = go_to;
        }
    }

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

    /// Checks if a hand is physically blocking a note from
    /// being reached by the other hand
    fn blocking(solver: *const Solver, hand: Hand, key: usize) bool {
        return switch (hand) {
            .left => solver.left.index + OCTAVE_SIZE >= key,
            .right => solver.right.index <= key,
        };
    }

    fn getHand(solver: *Solver, hand: Hand) *HandInfo {
        return switch (hand) {
            .left => &solver.left,
            .right => &solver.right,
        };
    }

    fn bestHandForTheJob(
        solver: *const Solver,
        gotta_go_to: usize,
        time_to_do_it: usize,
    ) ?Hand {
        var best_candidate: ?Hand = null;
        var best_time: usize = std.math.maxInt(usize);

        // TODO: Check if right is blocking here too :)
        if (solver.left.isFree()) { //and !solver.blocking(.right, gotta_go_to)) {
            // Check if distance needed to get there is within time to do it

            const time_to_get_there = solver.right.timeToGetThere(gotta_go_to);
            if (time_to_get_there <= time_to_do_it) {
                best_candidate = .left;
                best_time = time_to_get_there;
            }
        }

        // TODO: Use left and right hands

        // if (solver.right.isFree() and !solver.blocking(.left, gotta_go_to)) {
        //     // Check if distance needed to get there is within time to do it
        //     // AND if it's less than the left distance if left is a valid
        //     // candidate
        //     //
        //     // AND AND AND if it physically can get there
        //
        //     const time_to_get_there = solver.left.timeToGetThere(gotta_go_to);
        //     if (time_to_get_there <= time_to_do_it and time_to_get_there < best_time) {
        //         best_candidate = .right;
        //         best_time = time_to_get_there;
        //     }
        // }

        return best_candidate;
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

    fn startAt(solver: *const Solver) usize {
        for (solver.instructions) |instr| {
            if (instr.event == .midi and
                instr.event.midi == .note_on)
            {
                return instr.event.midi.note_on.@"1".key;
            }
        }

        return 0;
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

                    if (solver.bestHandForTheJob(key, event.delta_time)) |hand| {
                        _ = hand;
                        std.debug.print("We can insert a move\n", .{});
                    } else {
                        std.debug.print("Note will be missed, no hand can reach it\n", .{});
                    }
                },
                .note_off => |note_off| {
                    const key = note_off.@"1".key;
                    std.debug.print("{} {} off\n", .{ event.timestamp, key });

                    const key_if_covers = solver.left
                        .getGlobalKey(@as(usize, key));

                    if (key_if_covers) |k| {
                        k.* = false;
                    }
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

    fn moveTo(solver: *Solver, hand: Hand, to: usize) ?Instruction {
        const hand_info = solver.getHand(hand);
        if (hand_info.covers(to)) {
            return null;
        }

        const dir: Direction = if (hand_info.index < to) .left else .right;
        const time = hand_info.timeToGetThere(to);

        hand_info.moveTo(to);

        return .{
            .delta_time = 0,
            .cmd = .{
                .move_hand = .{
                    .hand = hand,
                    .direction = dir,
                    .time = time,
                },
            },
        };
    }

    pub fn solve(solver: *Solver, alloc: Allocator, program: *MaestroProgram) !void {
        var timestamp: u32 = 0;

        const first_key = solver.startAt();
        const hand_for_it = solver.bestHandForTheJob(first_key, std.math.maxInt(usize));

        if (solver.moveTo(hand_for_it.?, first_key)) |instr| {
            try program.instructions.append(alloc, instr);
        }

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
