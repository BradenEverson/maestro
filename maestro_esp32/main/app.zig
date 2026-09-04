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

const test_midi = @embedFile("two_hand_test.mid");

const log = std.log.scoped(.maestro);

const UART_PORT: c_uint = 1; // UART1
const BAUD_RATE = 115200;
const BUF_SIZE = 256;

const TX_PIN: c_int = 38;
const RX_PIN: c_int = 39;

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

    idf.uart.driverInstall(UART_PORT, .{
        .rx_buffer_size = BUF_SIZE * 2,
        .tx_buffer_size = 0,
    }) catch unreachable;

    idf.uart.setBaudrate(UART_PORT, BAUD_RATE) catch unreachable;
    idf.uart.setWordLength(UART_PORT, idf.sys.UART_DATA_8_BITS) catch unreachable;
    idf.uart.setParity(UART_PORT, idf.sys.UART_PARITY_DISABLE) catch unreachable;
    idf.uart.setStopBits(UART_PORT, idf.sys.UART_STOP_BITS_1) catch unreachable;

    setPin(UART_PORT, .{
        .tx = TX_PIN,
        .rx = RX_PIN,
    }) catch unreachable;

    var midi = MIDI.fromBytes(alloc, test_midi) catch {
        // log.err("MIDI Parse Failed {s}", .{@errorName(err)});
        return;
    };
    defer midi.deinit(alloc);

    log.info("Parse Complete!", .{});
    log.info("Solving MIDI!", .{});

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
    log.info("Solve Complete!", .{});

    idf.rtos.Task.delayMs(1500);

    // Clear solved instructions and such if we need to test specific movements!
    //
    //
    // program.instructions.clearAndFree(alloc);
    //
    // program.instructions.append(alloc, .{ .timestamp = 0, .delay = 0, .cmd = .{ .note_on = .{ .hand = .left, .relative_note = 0 } } }) catch unreachable;
    // program.instructions.append(alloc, .{ .timestamp = 100, .delay = 100, .cmd = .{ .note_off = .{ .hand = .left, .relative_note = 0 } } }) catch unreachable;
    //
    // program.instructions.append(alloc, .{ .timestamp = 500, .delay = 400, .cmd = .{ .move_hand = .{ .hand = .left, .white_keys = 1, .direction = .left } } }) catch unreachable;
    //
    // program.instructions.append(alloc, .{ .timestamp = 600, .delay = 100, .cmd = .{ .note_on = .{ .hand = .left, .relative_note = 0 } } }) catch unreachable;
    // program.instructions.append(alloc, .{ .timestamp = 700, .delay = 100, .cmd = .{ .note_off = .{ .hand = .left, .relative_note = 0 } } }) catch unreachable;
    //
    // program.instructions.append(alloc, .{ .timestamp = 1500, .delay = 1000, .cmd = .{ .move_hand = .{ .hand = .left, .white_keys = 1, .direction = .left } } }) catch unreachable;
    //
    // program.instructions.append(alloc, .{ .timestamp = 1600, .delay = 100, .cmd = .{ .note_on = .{ .hand = .left, .relative_note = 0 } } }) catch unreachable;
    // program.instructions.append(alloc, .{ .timestamp = 1700, .delay = 100, .cmd = .{ .note_off = .{ .hand = .left, .relative_note = 0 } } }) catch unreachable;
    //
    // program.instructions.append(alloc, .{ .timestamp = 2500, .delay = 1000, .cmd = .{ .move_hand = .{ .hand = .left, .white_keys = 2, .direction = .left } } }) catch unreachable;
    //
    // program.instructions.append(alloc, .{ .timestamp = 2600, .delay = 100, .cmd = .{ .note_on = .{ .hand = .left, .relative_note = 0 } } }) catch unreachable;
    // program.instructions.append(alloc, .{ .timestamp = 2700, .delay = 100, .cmd = .{ .note_off = .{ .hand = .left, .relative_note = 0 } } }) catch unreachable;
    //
    // program.instructions.append(alloc, .{ .timestamp = 3500, .delay = 1000, .cmd = .{ .move_hand = .{ .hand = .left, .white_keys = 3, .direction = .left } } }) catch unreachable;
    //
    // program.instructions.append(alloc, .{ .timestamp = 3600, .delay = 100, .cmd = .{ .note_on = .{ .hand = .left, .relative_note = 0 } } }) catch unreachable;
    // program.instructions.append(alloc, .{ .timestamp = 3700, .delay = 100, .cmd = .{ .note_off = .{ .hand = .left, .relative_note = 0 } } }) catch unreachable;
    //
    // program.instructions.append(alloc, .{ .timestamp = 13500, .delay = 10000, .cmd = .{ .move_hand = .{ .hand = .left, .white_keys = 14, .direction = .right } } }) catch unreachable;
    //
    // program.instructions.append(alloc, .{ .timestamp = 13600, .delay = 100, .cmd = .{ .note_on = .{ .hand = .left, .relative_note = 0 } } }) catch unreachable;
    // program.instructions.append(alloc, .{ .timestamp = 13700, .delay = 100, .cmd = .{ .note_off = .{ .hand = .left, .relative_note = 0 } } }) catch unreachable;
    // program.instructions.append(alloc, .{ .timestamp = 5000, .delay = 5000, .cmd = .{ .note_on = .{ .hand = .right, .relative_note = 0 } } }) catch unreachable;
    // program.instructions.append(alloc, .{ .timestamp = 5000, .delay = 0, .cmd = .{ .note_on = .{ .hand = .right, .relative_note = 1 } } }) catch unreachable;
    // program.instructions.append(alloc, .{ .timestamp = 5000, .delay = 0, .cmd = .{ .note_on = .{ .hand = .right, .relative_note = 2 } } }) catch unreachable;
    // program.instructions.append(alloc, .{ .timestamp = 5000, .delay = 0, .cmd = .{ .note_on = .{ .hand = .right, .relative_note = 3 } } }) catch unreachable;
    // program.instructions.append(alloc, .{ .timestamp = 5000, .delay = 0, .cmd = .{ .note_on = .{ .hand = .right, .relative_note = 4 } } }) catch unreachable;
    // program.instructions.append(alloc, .{ .timestamp = 5000, .delay = 0, .cmd = .{ .note_on = .{ .hand = .right, .relative_note = 5 } } }) catch unreachable;
    // program.instructions.append(alloc, .{ .timestamp = 5000, .delay = 0, .cmd = .{ .note_on = .{ .hand = .right, .relative_note = 6 } } }) catch unreachable;
    // program.instructions.append(alloc, .{ .timestamp = 5000, .delay = 0, .cmd = .{ .note_on = .{ .hand = .right, .relative_note = 7 } } }) catch unreachable;
    // program.instructions.append(alloc, .{ .timestamp = 5000, .delay = 0, .cmd = .{ .note_on = .{ .hand = .right, .relative_note = 8 } } }) catch unreachable;
    // program.instructions.append(alloc, .{ .timestamp = 5000, .delay = 0, .cmd = .{ .note_on = .{ .hand = .right, .relative_note = 9 } } }) catch unreachable;
    // program.instructions.append(alloc, .{ .timestamp = 5000, .delay = 0, .cmd = .{ .note_on = .{ .hand = .right, .relative_note = 10 } } }) catch unreachable;
    // program.instructions.append(alloc, .{ .timestamp = 5000, .delay = 0, .cmd = .{ .note_on = .{ .hand = .right, .relative_note = 11 } } }) catch unreachable;
    //
    // program.instructions.append(alloc, .{ .timestamp = 10000, .delay = 5000, .cmd = .{ .note_off = .{ .hand = .right, .relative_note = 0 } } }) catch unreachable;
    // program.instructions.append(alloc, .{ .timestamp = 10000, .delay = 0, .cmd = .{ .note_off = .{ .hand = .right, .relative_note = 1 } } }) catch unreachable;
    // program.instructions.append(alloc, .{ .timestamp = 10000, .delay = 0, .cmd = .{ .note_off = .{ .hand = .right, .relative_note = 2 } } }) catch unreachable;
    // program.instructions.append(alloc, .{ .timestamp = 10000, .delay = 0, .cmd = .{ .note_off = .{ .hand = .right, .relative_note = 3 } } }) catch unreachable;
    // program.instructions.append(alloc, .{ .timestamp = 10000, .delay = 0, .cmd = .{ .note_off = .{ .hand = .right, .relative_note = 4 } } }) catch unreachable;
    // program.instructions.append(alloc, .{ .timestamp = 10000, .delay = 0, .cmd = .{ .note_off = .{ .hand = .right, .relative_note = 5 } } }) catch unreachable;
    // program.instructions.append(alloc, .{ .timestamp = 10000, .delay = 0, .cmd = .{ .note_off = .{ .hand = .right, .relative_note = 6 } } }) catch unreachable;
    // program.instructions.append(alloc, .{ .timestamp = 10000, .delay = 0, .cmd = .{ .note_off = .{ .hand = .right, .relative_note = 7 } } }) catch unreachable;
    // program.instructions.append(alloc, .{ .timestamp = 10000, .delay = 0, .cmd = .{ .note_off = .{ .hand = .right, .relative_note = 8 } } }) catch unreachable;
    // program.instructions.append(alloc, .{ .timestamp = 10000, .delay = 0, .cmd = .{ .note_off = .{ .hand = .right, .relative_note = 9 } } }) catch unreachable;
    // program.instructions.append(alloc, .{ .timestamp = 10000, .delay = 0, .cmd = .{ .note_off = .{ .hand = .right, .relative_note = 10 } } }) catch unreachable;
    // program.instructions.append(alloc, .{ .timestamp = 10000, .delay = 0, .cmd = .{ .note_off = .{ .hand = .right, .relative_note = 11 } } }) catch unreachable;

    log.info("Solve Complete!", .{});

    var hand = Hand.init(
        // Octave of solonoids
        [_]idf.gpio.Num(){
            .@"4",
            .@"18",
            .@"5",
            .@"8",
            .@"6",
            .@"7",
            .@"3",
            .@"15",
            .@"46",
            .@"16",
            .@"37",
            .@"17",
        },

        // step
        .@"41",
        // dir
        .@"40",

        // endstop!
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
            log.info("Sending Msg: {any}", .{instr.cmd});

            const packet = instr.cmd.toPacket();
            const send = packet.toBytesToSend(&packet_buffer);

            // log.info("{X}", .{send});

            _ = idf.uart.writeBytes(UART_PORT, send) catch {
                log.err("Failed to write", .{});
            };
        } else {
            switch (instr.cmd) {
                .note_on => |note_on| {
                    log.info("ON: {}", .{note_on.relative_note});
                    hand.pressNote(note_on.relative_note) catch unreachable;
                },

                .note_off => |note_off| {
                    log.info("OFF: {}", .{note_off.relative_note});
                    hand.depressNote(note_off.relative_note) catch unreachable;
                },

                .move_hand => |move_info| {
                    log.info("MOVING {} keys {any}", .{ move_info.white_keys, move_info.direction });

                    for (0..move_info.white_keys) |_| {
                        hand.moveNote(move_info.direction) catch {
                            // log.err("Move Failed!!!", .{});
                            unreachable;
                        };
                    }
                },
            }
        }
    }

    log.info("DONE", .{});

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
