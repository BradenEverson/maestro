const std = @import("std");
const builtin = @import("builtin");
const idf = @import("esp_idf");

const MIDI = @import("midi");
const Hand = @import("hand.zig");
const Note = Hand.Note;

const Solver = @import("solver").Solver;

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
    log.info("Solving MIDI!", .{});

    var solver = Solver{};
    var maestro_program = solver.solve(
        alloc,
        midi.tracks[0].mtrk_events.items,
    ) catch unreachable;
    defer maestro_program.deinit(alloc);

    log.info("Solve Complete!", .{});

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

    const tempo_us = maestro_program.tempo;
    log.info("Tempo: {} BPM\n", .{60_000_000 / @as(u32, tempo_us)});

    for (maestro_program.instructions.items) |instr| {
        const delay_ticks: u32 = @intCast(
            (@as(u64, instr.delta_time) * tempo_us * RTOS_HZ) /
                (@as(u64, ticks_per_qn) * 1_000_000),
        );

        log.info("{any} - {}", .{ instr, delay_ticks });
        if (delay_ticks > 0) {
            idf.rtos.Task.delay(delay_ticks);
        }

        switch (instr.cmd) {
            .note_on => |note_on| {
                // TODO: Eventually, we will have two hands
                // for now, treat it all as a command to this
                // one hand :)

                log.info("ON: {}", .{note_on.relative_note});
                hand.pressNote(note_on.relative_note) catch unreachable;
            },

            .note_off => |note_off| {
                // TODO: Same deal
                log.info("OFF: {}", .{note_off.relative_note});
                hand.depressNote(note_off.relative_note) catch unreachable;
            },

            .move_hand => |move_info| {
                // TODO: same deal, hand will eventually be
                // many hands woohooo
                log.info("MOVING {} keys {any}", .{ move_info.white_keys, move_info.direction });

                for (0..move_info.white_keys) |_|
                    hand.moveNote(move_info.direction) catch {
                        log.err("Move Failed!!!", .{});
                        unreachable;
                    };
            },
        }
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
