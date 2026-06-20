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

    var hand = Hand.init(
        [_]idf.gpio.Num(){
            .@"4",
            .@"5",
            .@"6",
            .@"7",
            .@"15",
            .@"16",
            .@"17",
            .@"18",
            .@"8",
            .@"3",
            .@"46",
            .@"9",
        },

        .@"41",
        .@"40",

        0,
    ) catch |err| {
        log.err("Hand Init Failed :((( {s}", .{@errorName(err)});
        return;
    };

    const RTOS_HZ: u32 = 1000;

    if (midi.header.division != .metrical) {
        log.err("Only metrical supported for now", .{});
        return;
    }

    const ticks_per_qn: u32 = @intCast(midi.header.division.metrical);
    var tempo_us: u32 = 500_000;
    var idx: usize = 0;
    var stopped: bool = false;

    while (true) {
        for (0..400) |_| {
            hand.stepper.step() catch unreachable;
        }
        hand.stepper.switchDirection(.left) catch unreachable;
        for (0..400) |_| {
            hand.stepper.step() catch unreachable;
        }
        hand.stepper.switchDirection(.right) catch unreachable;
    }

    while (!stopped) {
        const curr = midi.tracks[0].mtrk_events.items[idx];

        const delay_ticks: u32 = @intCast(
            (@as(u64, curr.delta_time) * tempo_us * RTOS_HZ) /
                (@as(u64, ticks_per_qn) * 1_000_000),
        );

        idf.rtos.Task.delay(delay_ticks);

        switch (curr.event) {
            .midi => |m| switch (m) {
                .note_on => |on| {
                    const note = Hand.noteFromInt(on.@"1".key);
                    log.info("ON: {}\n", .{note});

                    hand.pressNote(note) catch |err| {
                        log.err("Press failed :( {}", .{err});
                        return;
                    };
                },
                .note_off => |off| {
                    const note = Hand.noteFromInt(off.@"1".key);
                    log.info("OFF: {}\n", .{note});

                    hand.depressNote(note) catch |err| {
                        log.err("Depress failed :( {}", .{err});
                        return;
                    };
                },
            },
            .meta => |m| switch (m) {
                .set_tempo => |t| {
                    tempo_us = t;
                    log.info("Tempo: {} BPM\n", .{60_000_000 / @as(u32, t)});
                },
                .time_signature => |ts| {
                    log.info("Time sig: {}/{}\n", .{
                        ts.numerator,
                        @as(u32, 1) << @intCast(ts.denominator),
                    });
                },
                .end_of_track => stopped = true,
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
