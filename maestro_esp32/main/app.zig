const std = @import("std");
const builtin = @import("builtin");
const idf = @import("esp_idf");

const MIDI = @import("midi");
const Hand = @import("hand.zig");
const Note = Hand.Note;

const test_midi = @embedFile("v1keytest.mid");

const log = std.log.scoped(.maestro);

export fn app_main() callconv(.c) void {
    var heap: idf.heap.VPortAllocator = .init();
    const alloc = heap.allocator();

    var midi = MIDI.fromBytes(alloc, test_midi) catch |err| {
        log.err("MIDI Parse Failed {s}", .{@errorName(err)});
        return;
    };
    defer midi.deinit(alloc);

    log.info("Parse Complete!", .{});

    var hand = Hand.init([_]idf.gpio.Num(){
        .@"1",
        .@"2",
        .@"42",
        .@"41",
        .@"40",
        .@"39",
        .@"38",
    }, 0) catch |err| {
        log.err("Hand Init Failed :((( {s}", .{@errorName(err)});
        return;
    };

    var idx: usize = 0;
    var stopped: bool = false;

    while (!stopped) {
        const curr = midi.tracks[0].mtrk_events.items[idx];

        idf.rtos.Task.delayMs(curr.delta_time);

        switch (curr.event) {
            .midi => |m| switch (m) {
                .note_on => |on| {
                    log.info("ON: {}\n", .{on.@"1".key});
                    const note = Hand.noteFromInt(on.@"1".key);
                    hand.pressNote(note) catch {};
                },
                .note_off => |off| {
                    log.info("OFF: {}\n", .{off.@"1".key});
                    const note = Hand.noteFromInt(off.@"1".key);
                    hand.depressNote(note) catch {};
                },
            },

            .meta => |m| switch (m) {
                .end_of_track => stopped = true,
                else => {},
            },

            .ignored => {},
        }

        idx += 1;
    }

    log.info("DONE", .{});

    while (true) {
        idf.rtos.Task.delayMs(100);
    }
}

pub const panic = idf.esp_panic.panic;
pub const std_options: std.Options = .{
    .log_level = switch (builtin.mode) {
        .Debug => .debug,
        else => .info,
    },
    .logFn = idf.log.espLogFn,
};
