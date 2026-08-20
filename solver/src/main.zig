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

    const tempo = maestro_solver.getTempo(midi.tracks[0].mtrk_events.items);

    var solver: Solver = .{
        .instructions = midi.tracks[0].mtrk_events.items,
        .ticks_per_quarter = midi.header.division.metrical, // only support metrical rn :)
        .us_per_quarter = tempo.?,
    };
    var program: MaestroProgram = .{};

    defer program.deinit(alloc);

    try solver.solve(alloc, &program);

    std.debug.print("Solver Complete!! Note hit rate: {} / {}\n", .{ solver.hit, solver.notes });

    for (program.instructions.items) |instr| {
        std.debug.print("{any}\n", .{instr});
    }
}
