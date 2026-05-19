const std = @import("std");
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

    var parsed = try Midi.fromBytes(alloc, source);
    defer parsed.deinit(alloc);

    std.debug.print("{any}\n", .{parsed});

    for (parsed.tracks) |track| {
        for (track.mtrk_events.items) |event| if (event.event != .ignored)
            std.debug.print("{}\n", .{event});
    }
}
