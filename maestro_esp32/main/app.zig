const std = @import("std");
const builtin = @import("builtin");
const idf = @import("esp_idf");
const sys = idf.sys;

const MIDI = @import("midi");
const Hand = @import("hand.zig");
const Note = Hand.Note;

const maestro_solver = @import("solver");
const Solver = maestro_solver.Solver;
const MaestroProgram = maestro_solver.MaestroProgram;

const test_midi = @embedFile("took_her_to_the_o_short_notes.mid");

const log = std.log.scoped(.maestro);

const UART_PORT: c_uint = 1; // UART1
const BAUD_RATE = 115200;
const BUF_SIZE = 256;

const TX_PIN: c_int = 43;
const RX_PIN: c_int = 44;

pub fn setPin(port: c_uint, pins: struct {
    tx: c_int = sys.UART_PIN_NO_CHANGE,
    rx: c_int = sys.UART_PIN_NO_CHANGE,
    rts: c_int = sys.UART_PIN_NO_CHANGE,
    cts: c_int = sys.UART_PIN_NO_CHANGE,
}) !void {
    const ret = sys._uart_set_pin4(
        port,
        pins.tx,
        pins.rx,
        pins.rts,
        pins.cts,
    );
    if (ret != sys.ESP_OK) return error.SetPinFailed;
}

const MAX_BUFFER_SIZE: usize = 256;

export fn app_main() callconv(.c) void {
    var packet_buffer: [MAX_BUFFER_SIZE]u8 = undefined;

    var heap: idf.heap.VPortAllocator = .init();
    const alloc = heap.allocator();

    setPin(UART_PORT, .{
        .tx = TX_PIN,
        .rx = RX_PIN,
    }) catch unreachable;

    idf.uart.driverInstall(UART_PORT, .{
        .rx_buffer_size = BUF_SIZE * 2,
        .tx_buffer_size = 0,
    }) catch unreachable;

    var midi = MIDI.fromBytes(alloc, test_midi) catch {
        // log.err("MIDI Parse Failed {s}", .{@errorName(err)});
        return;
    };
    defer midi.deinit(alloc);

    // log.info("Parse Complete!", .{});
    // log.info("Solving MIDI!", .{});
    //
    const tempo = maestro_solver.getTempo(midi.tracks[0].mtrk_events.items);

    var solver: Solver = .{
        .instructions = midi.tracks[0].mtrk_events.items,
        .ticks_per_quarter = midi.header.division.metrical, // only support metrical rn :)

        .us_per_quarter = tempo.?,
    };

    var program: MaestroProgram = .{};

    defer program.deinit(alloc);

    solver.solve(alloc, &program) catch {
        // log.err("Solve Failed {s}", .{@errorName(err)});
        return;
    };

    // program.instructions.append(alloc, .{ .timestamp = 100, .cmd = .{ .move_hand = .{
    //     .direction = .right,
    //     .hand = .left,
    //     .white_keys = 1,
    // } } }) catch unreachable;

    // log.info("Solve Complete!", .{});

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
        .@"10",

        0,
    ) catch {
        // log.err("Hand Init Failed :((( {s}", .{@errorName(err)});
        return;
    };

    const RTOS_HZ: u32 = 1000;

    if (midi.header.division != .metrical) {
        // log.err("Only metrical supported for now", .{});
        return;
    }

    const ticks_per_qn: u32 = @intCast(midi.header.division.metrical);

    const tempo_us = program.tempo;
    // log.info("Tempo: {} BPM\n", .{60_000_000 / @as(u32, tempo_us)});

    for (program.instructions.items) |instr| {
        const delay_ticks: u32 = @intCast(
            (@as(u64, instr.delay) * tempo_us * RTOS_HZ) /
                (@as(u64, ticks_per_qn) * 1_000_000),
        );

        // log.info("{any} - {}", .{ instr, delay_ticks });
        if (delay_ticks > 0) {
            idf.rtos.Task.delay(delay_ticks);
        }

        if (instr.cmd.hand() == .right) {
            const packet = instr.cmd.toPacket();
            const send = packet.toBytesToSend(&packet_buffer);

            _ = idf.uart.writeBytes(UART_PORT, send) catch unreachable;
        } else {
            switch (instr.cmd) {
                .note_on => |note_on| {
                    // TODO: Eventually, we will have two hands
                    // for now, treat it all as a command to this
                    // one hand :)

                    // log.info("ON: {}", .{note_on.relative_note});
                    hand.pressNote(note_on.relative_note) catch unreachable;
                },

                .note_off => |note_off| {
                    // TODO: Same deal
                    // log.info("OFF: {}", .{note_off.relative_note});
                    hand.depressNote(note_off.relative_note) catch unreachable;
                },

                .move_hand => |move_info| {
                    // TODO: same deal, hand will eventually be
                    // many hands woohooo
                    // log.info("MOVING {} keys {any}", .{ move_info.white_keys, move_info.direction });

                    for (0..move_info.white_keys) |_|
                        hand.moveNote(move_info.direction) catch {
                            // log.err("Move Failed!!!", .{});
                            unreachable;
                        };
                },
            }
        }
    }

    // log.info("DONE", .{});

    // TODO: Home for the right stepper is opposite
    hand.stepper.goHome() catch unreachable;

    while (true) {
        idf.rtos.Task.delayMs(100);
    }
}

pub const panic = idf.esp_panic.panic;
pub const std_options: std.Options = .{
    .page_size_min = 4096,
    .page_size_max = 4096,

    .log_level = switch (builtin.mode) {
        .Debug => .debug,
        else => .info,
    },
    .logFn = idf.log.espLogFn,
};
