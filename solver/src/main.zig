const std = @import("std");
const Solver = @import("solver").Solver;

const Midi = @import("midi");

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const alloc = init.gpa;

    var args = init.minimal.args.iterate();
    _ = args.next();

    var source: []u8 = undefined;

    if (args.next()) |file_path| {
        source = try std.Io.Dir.cwd().readFileAlloc(
            io,
            file_path,
            alloc,
            .unlimited,
        );
    } else {
        std.debug.print("Missing MIDI file!!!\n", .{});
        std.process.exit(1);
    }

    defer alloc.free(source);

    var midi = try Midi.fromBytes(alloc, source);
    defer midi.deinit(alloc);

    var solver: Solver = .{};

    var program = try solver.solve(
        midi.tracks[0].mtrk_events.items,
    );
    defer program.deinit(alloc);
}
