//! MIDI File Parsing

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Chunk = @import("chunk.zig");

chunks: []const Chunk,

const MIDI = @This();

pub fn deinit(midi: *MIDI, alloc: Allocator) void {
    alloc.free(midi.chunks);
}

pub fn tryFromBytes(bytes: []const u8) !MIDI {
    _ = bytes;

    // TODO
    return .{
        .chunks = &[0]Chunk{},
    };
}
