const std = @import("std");
const maestro_solver = @import("solver");
const Solver = maestro_solver.Solver;
const MaestroProgram = maestro_solver.MaestroProgram;

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
    var program: MaestroProgram = .{};

    defer program.deinit(alloc);

    var timestamp: u32 = 0;

    for (midi.tracks[0].mtrk_events.items) |*event| {
        event.timestamp = timestamp + event.delta_time;
        try solver.feed(alloc, &program, event.*);
        timestamp += event.delta_time;
    }
}
