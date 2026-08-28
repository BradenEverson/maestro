//! Solver responsible for translating sequence of MIDI events
//! into maestro events that can include moving the servos

const std = @import("std");
const Allocator = std.mem.Allocator;
const Midi = @import("midi");

const the_hand = @import("hand.zig");
const HandInfo = the_hand.HandInfo;
const Hand = the_hand.Hand;

const PIANO_LEN: usize = 61;

pub const packet = @import("packet.zig");

/// How many keys back we are when translating
/// from sequencer to keyboard
///
/// For testing, I'm currently like 4 octaves back
/// (we have a smaller fixture rn)
const KEY_OFFSET: usize = 0;

fn ticksPerKeyMove(ticks_per_quarter: u16, us_per_quarter: u24) usize {
    return (the_hand.TIME_TO_MOVE_KEY * 1000 * @as(usize, ticks_per_quarter)) /
        @as(usize, us_per_quarter);
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

pub const Direction = enum(u8) {
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

    pub fn toPacket(cmd: *const MaestroCommand) packet.RightHandMessage {
        switch (cmd.*) {
            .note_on => |note_on| {
                return .{ .press = @truncate(note_on.relative_note) };
            },

            .note_off => |note_off| {
                return .{ .depress = @truncate(note_off.relative_note) };
            },

            .move_hand => |move_hand| {
                const dir = @intFromEnum(move_hand.direction);
                const white_keys: u8 = @truncate(move_hand.white_keys);

                return .{ .move = .{ .dir = dir, .white_keys = white_keys } };
            },
        }
    }
};

pub const Solver = struct {
    left: HandInfo = .{ .index = 0 },
    right: HandInfo = .{ .index = PIANO_LEN - the_hand.OCTAVE_SIZE },

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
            .left => solver.left.index + the_hand.OCTAVE_SIZE >= key,
            .right => solver.right.index <= key,
        };
    }

    fn getHandConst(solver: *const Solver, hand: Hand) *const HandInfo {
        return switch (hand) {
            .left => &solver.left,
            .right => &solver.right,
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

    fn bestPositionForTheFuture(
        solver: *Solver,
        hand: Hand,
        must_at_least_hit: usize,
        time_to_do_it: usize,
    ) ?struct { position: usize, future_coverage: usize, time_to_get_there: usize } {
        const hand_info = solver.getHandConst(hand);
        const time_to_get_there = hand_info.timeToGetThere(must_at_least_hit, solver.ticks_per_key);

        if (hand_info.covers(must_at_least_hit)) {
            return .{
                .position = must_at_least_hit,
                .future_coverage = 0,
                .time_to_get_there = 0,
            };
        }

        if (time_to_get_there <= time_to_do_it) {
            return .{
                .position = must_at_least_hit,
                .future_coverage = 1,
                .time_to_get_there = time_to_get_there,
            };
        }

        return null;
    }

    fn bestHandForTheJob(
        solver: *Solver,
        gotta_go_to: usize,
        time_to_do_it: usize,
    ) ?struct { hand: Hand, new_pos: usize } {
        var best_candidate: ?Hand = null;
        var best_time: usize = std.math.maxInt(usize);
        var position: usize = time_to_do_it;
        var coverage: usize = 0;

        // TODO: Check if right is blocking here too :)
        if (solver.left.isFree()) { //and !solver.blocking(.right, gotta_go_to)) {
            // Check if distance needed to get there is within time to do it

            const best_pos = solver.bestPositionForTheFuture(.left, gotta_go_to, time_to_do_it);

            if (best_pos) |pos| {
                best_candidate = .left;
                best_time = pos.time_to_get_there;
                coverage = pos.future_coverage;
                position = pos.position;
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

        if (best_candidate) |candidate| {
            return .{ .hand = candidate, .new_pos = position };
        } else {
            return null;
        }
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

                    if (solver.bestHandForTheJob(key, event.delta_time)) |best_stuff| {
                        const hand = best_stuff.hand;
                        const pos = best_stuff.new_pos;

                        const hand_info = solver.getHand(hand);
                        var time_to_move: usize = 0;

                        if (!hand_info.covers(pos)) {
                            time_to_move = hand_info.timeToGetThere(pos, solver.ticks_per_key);

                            if (solver.moveTo(hand, pos)) |instr| {
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
                    }
                },
                .note_off => |note_off| {
                    const key = note_off.@"1".key;

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

        if (solver.moveTo(hand_for_it.?.hand, hand_for_it.?.new_pos)) |instr| {
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

        for (program.instructions.items, 0..) |*instr, i| {
            if (i > 0) {
                instr.delay = instr.timestamp - program.instructions.items[i - 1].timestamp;
            }
        }
    }
};

test {
    _ = @import("hand.zig");
    _ = @import("packet.zig");
}
