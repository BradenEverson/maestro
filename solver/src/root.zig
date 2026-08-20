//! Solver responsible for translating sequence of MIDI events
//! into maestro events that can include moving the servos

const std = @import("std");
const Allocator = std.mem.Allocator;
const Midi = @import("midi");
const OCTAVE_SIZE: usize = 12;
const PIANO_LEN: usize = 61;
const HANDS: usize = 1;

/// time in ms it takes to move a single key
const TIME_TO_MOVE_KEY: usize = 30;

/// How many keys back we are when translating
/// from sequencer to keyboard
///
/// For testing, I'm currently like 4 octaves back
/// (we have a smaller fixture rn)
const KEY_OFFSET: usize = 0;

fn ticksPerKeyMove(ticks_per_quarter: u16, us_per_quarter: u24) usize {
    return (TIME_TO_MOVE_KEY * 1000 * @as(usize, ticks_per_quarter)) /
        @as(usize, us_per_quarter);
}

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

fn slotTypeMatches(hand_index: usize, key: usize) bool {
    if (isBlackKey(key)) {
        return hand_index % OCTAVE_SIZE == 0;
    }
    return isBlackKey(key) == isBlackKey(key - hand_index);
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

pub fn getTempo(events: []Midi.TrackChunk.MTrkEvent) ?u24 {
    for (events) |evt| {
        if (evt.event == .meta and evt.event.meta == .set_tempo) {
            return evt.event.meta.set_tempo;
        }
    }

    return null;
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
    timestamp: usize,
    delay: usize = 0,
    cmd: MaestroCommand,
};

pub const NoteInfo = struct {
    hand: Hand,
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

    pub fn isOctaveAligned(hand: *const HandInfo) bool {
        return hand.index % OCTAVE_SIZE == 0;
    }

    pub fn covers(hand: *const HandInfo, global_key: usize) bool {
        var cond = (global_key >= hand.index) and
            (global_key < hand.index + OCTAVE_SIZE);

        if (isBlackKey(global_key)) {
            cond = cond and hand.isOctaveAligned();
        }

        return cond;
    }

    fn nearestValidIndex(hand: *const HandInfo, go_to: usize) usize {
        if (isBlackKey(go_to)) {
            const octave = go_to / OCTAVE_SIZE;
            return octave * OCTAVE_SIZE;
        }

        const naive: usize = if (go_to > hand.index)
            go_to -| (OCTAVE_SIZE - 1)
        else
            go_to;

        const candidate = naive;
        var offset: usize = 0;
        while (offset < OCTAVE_SIZE) : (offset += 1) {
            const try_idx = if (candidate >= offset) candidate - offset else candidate + offset;
            if (slotTypeMatches(try_idx, go_to) and
                go_to >= try_idx and go_to < try_idx + OCTAVE_SIZE)
            {
                return try_idx;
            }
            const try_idx2 = candidate + offset;
            if (slotTypeMatches(try_idx2, go_to) and
                go_to >= try_idx2 and go_to < try_idx2 + OCTAVE_SIZE)
            {
                return try_idx2;
            }
        }

        const octave = go_to / OCTAVE_SIZE;
        return octave * OCTAVE_SIZE;
    }

    pub fn timeToGetThere(hand: *const HandInfo, go_to: usize, ticks_per_key: usize) usize {
        if (hand.covers(go_to)) return 0;
        const target = hand.nearestValidIndex(go_to);
        return whiteKeyDistance(hand.index, target) * ticks_per_key;
    }

    pub fn moveTo(hand: *HandInfo, go_to: usize) void {
        if (hand.covers(go_to)) return;
        hand.index = hand.nearestValidIndex(go_to);
    }

    pub fn getKey(hand: *HandInfo, key: usize) *bool {
        return &hand.pressing[key];
    }

    pub fn globalToLocal(hand: *const HandInfo, global_key: usize) ?usize {
        if (!hand.covers(global_key)) {
            return null;
        }

        return global_key - hand.index;
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

    ticks_per_quarter: u16,
    us_per_quarter: u24,
    ticks_per_key: usize = 0,

    hit: usize = 0,
    notes: usize = 0,

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

    fn handThatsTouching(
        solver: *Solver,
        note: usize,
    ) ?Hand {
        if (solver.left.getGlobalKey(note)) |_| {
            return .left;
            // TODO: Right here too
            // } else if (solver.right.getGlobalKey(note)) |_| {
            //     return .right;
        } else {
            return null;
        }
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

            const time_to_get_there = solver.left.timeToGetThere(gotta_go_to, solver.ticks_per_key);
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
        //     const time_to_get_there = solver.right.timeToGetThere(gotta_go_to, solver.ticks_per_key);
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
        const event = solver.instructions[solver.instruction_pointer];

        switch (event.event) {
            .midi => |midi| switch (midi) {
                .note_on => |note_on| {
                    solver.notes += 1;

                    const key = note_on.@"1".key;
                    // std.debug.print("{} {} on\n", .{ event.delta_time, key });

                    if (solver.bestHandForTheJob(key, event.delta_time)) |hand| {
                        const hand_info = solver.getHand(hand);
                        var time_to_move: usize = 0;

                        if (!hand_info.covers(key)) {
                            // std.debug.print("We can insert a move\n", .{});

                            time_to_move = hand_info.timeToGetThere(key, solver.ticks_per_key);

                            if (solver.moveTo(hand, key)) |instr| {
                                // std.debug.print("Can't move :(\n", .{});
                                var in = instr;

                                in.timestamp = event.timestamp - instr.timestamp;
                                try program.instructions.append(alloc, in);
                            }
                        }

                        const relative_note = hand_info.globalToLocal(key);

                        const on: Instruction = .{
                            .timestamp = event.timestamp,
                            .cmd = .{
                                .note_on = .{
                                    .hand = hand,
                                    .relative_note = relative_note.?,
                                },
                            },
                        };

                        try program.instructions.append(alloc, on);

                        const key_if_covers = hand_info
                            .getGlobalKey(@as(usize, key));
                        key_if_covers.?.* = true;
                        solver.hit += 1;
                    } else {
                        // std.debug.print("Note will be missed, no hand can reach it\n", .{});
                    }
                },
                .note_off => |note_off| {
                    const key = note_off.@"1".key;
                    // std.debug.print("{} {} off\n", .{ event.timestamp, key });

                    const maybe_touhcing = solver.handThatsTouching(key);

                    if (maybe_touhcing) |hand| {
                        const hand_info = solver.getHand(hand);

                        const k = hand_info
                            .getGlobalKey(@as(usize, key)).?;

                        k.* = false;
                        const relative_note = hand_info.globalToLocal(key);
                        const on: Instruction = .{
                            .timestamp = event.timestamp,
                            .cmd = .{
                                .note_off = .{
                                    .hand = hand,
                                    .relative_note = relative_note.?,
                                },
                            },
                        };

                        try program.instructions.append(alloc, on);
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

    /// Creates an instruction for moving to a location, THE TIMESTAMP WILL BE THE DURATION,
    /// THIS MUST BE SUBTRACTED FROM THE FUTURE INSTRUCTION TIMESTAMP TO GET THE REAL DEAL
    fn moveTo(solver: *Solver, hand: Hand, to: usize) ?Instruction {
        const hand_info = solver.getHand(hand);
        if (hand_info.covers(to)) {
            return null;
        }

        const dir: Direction = if (hand_info.index > to) .left else .right;
        const time = hand_info.timeToGetThere(to, solver.ticks_per_key);

        hand_info.moveTo(to);

        return .{
            .timestamp = time,
            .cmd = .{
                .move_hand = .{
                    .hand = hand,
                    .direction = dir,
                    .white_keys = time / solver.ticks_per_key,
                },
            },
        };
    }

    pub fn solve(solver: *Solver, alloc: Allocator, program: *MaestroProgram) !void {
        var timestamp: u32 = 0;

        solver.ticks_per_key = ticksPerKeyMove(solver.ticks_per_quarter, solver.us_per_quarter);

        const sixteenth_note = solver.ticks_per_quarter / 4;

        // Preprocessing
        for (solver.instructions, 0..) |*event, i| {
            if (event.event == .midi) {
                switch (event.event.midi) {
                    .note_on => event.event.midi.note_on.@"1".key -= KEY_OFFSET,
                    .note_off => {
                        event.event.midi.note_off.@"1".key -= KEY_OFFSET;

                        // Force all notes to be a sixteenth note
                        if (event.delta_time > sixteenth_note) {
                            if (i < solver.instructions.len - 1) {
                                solver.instructions[i + 1].delta_time += (event.delta_time - sixteenth_note);
                            }

                            event.delta_time = sixteenth_note;
                        }
                    },
                }
            }
        }

        const first_key = solver.startAt();
        const hand_for_it = solver.bestHandForTheJob(first_key, std.math.maxInt(usize));

        var time_to_make_first_move: usize = 0;

        if (solver.moveTo(hand_for_it.?, first_key)) |instr| {
            time_to_make_first_move = instr.timestamp;

            var in = instr;
            in.timestamp = 0;

            try program.instructions.append(alloc, in);
        }

        const offset: u32 = @truncate(time_to_make_first_move);

        for (solver.instructions) |*event| {
            event.timestamp = timestamp + event.delta_time + offset;
            try solver.feed(alloc, program);

            timestamp += event.delta_time;
        }

        // std.debug.print("Solver Complete!! Note hit rate: {} / {}\n", .{ solver.hit, solver.notes });

        for (program.instructions.items, 0..) |*instr, i| {
            if (i > 0) {
                instr.delay = instr.timestamp - program.instructions.items[i - 1].timestamp;
            }
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
