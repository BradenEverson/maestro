const std = @import("std");
const builtin = @import("builtin");
const idf = @import("esp_idf");
const sys = idf.sys;

const log = std.log.scoped(.right_hand_man);

const UART_PORT: c_uint = 1; // UART0
const BAUD_RATE = 115200;
const BUF_SIZE = 256;

const TX_PIN: c_int = 43;
const RX_PIN: c_int = 44;

const maestro_solver = @import("solver");
const MessageParser = maestro_solver.packet.MessageParser;

const Hand = @import("hand.zig");

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

export fn app_main() callconv(.c) void {
    var heap: idf.heap.VPortAllocator = .init();
    const alloc = heap.allocator();

    var parser: MessageParser = .{};

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
    ) catch |err| {
        log.err("Hand Init Failed :((( {s}", .{@errorName(err)});
        return;
    };

    _ = alloc;

    log.info("Hand made", .{});

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

    log.info("UART ready", .{});

    var buf: [BUF_SIZE]u8 = undefined;
    while (true) {
        const n = idf.uart.readBytes(UART_PORT, &buf, 100) catch unreachable;
        for (0..n) |i| {
            log.info("byte {X}", .{buf[i]});
            if (parser.feedByte(buf[i])) |msg| {
                log.info("Message received: {any}", .{msg});
                switch (msg) {
                    .press => |press| {
                        hand.pressNote(@as(usize, press)) catch {
                            // log.err("press Failed!!!", .{});
                            unreachable;
                        };
                    },

                    .depress => |depress| {
                        hand.depressNote(@as(usize, depress)) catch {
                            // log.err("depress Failed!!!", .{});
                            unreachable;
                        };
                    },

                    .move => |move| {
                        for (0..move.white_keys) |_| {
                            hand.moveNote(move.dir) catch {
                                // log.err("Move Failed!!!", .{});
                                unreachable;
                            };
                        }
                    },
                }
            }
        }
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
