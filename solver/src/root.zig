//! Solver responsible for translating sequence of MIDI events into maestro events that can include moving the servos

const std = @import("std");
const Allocator = std.mem.Allocator;

const Midi = @import("midi");

stream: Midi,

const Solver = @This();

pub fn init(alloc: Allocator, bytes: []const u8) !Solver {
    return .{
        .stream = try Midi.fromBytes(alloc, bytes),
    };
}

pub fn deinit(solver: *Solver, alloc: Allocator) void {
    solver.stream.deinit(alloc);
}
