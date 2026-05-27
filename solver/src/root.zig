//! Solver responsible for translating sequence of MIDI events
//! into maestro events that can include moving the servos

const std = @import("std");
const Allocator = std.mem.Allocator;

const Midi = @import("midi");

/// Black keys require that a hand be octave
/// aligned, if we need to reach one we must
/// ensure this alignment before knowing we
/// can actuate
fn isBlackKey(key: usize) bool {
    const black_keys_octave =
        &[_]usize{ 1, 3, 6, 8, 10 };

    const octave_idx = key % 12;

    return std.mem.find(usize, black_keys_octave, &[_]usize{octave_idx}) != null;
}

pub const Solver = struct {
    stream: Midi,
    piano_len: usize = 61,

    // First hand homes on the leftmost spot
    hand1: usize = 0,
    // Second hand homes on the rightmost spot
    hand2: usize = 60 - HAND_SIZE,

    const HAND_SIZE: usize = 12;

    pub fn init(alloc: Allocator, bytes: []const u8) !Solver {
        return .{
            .stream = try Midi.fromBytes(alloc, bytes),
        };
    }

    pub fn deinit(solver: *Solver, alloc: Allocator) void {
        solver.stream.deinit(alloc);
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
