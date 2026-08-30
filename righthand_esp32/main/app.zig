const std = @import("std");
const builtin = @import("builtin");
const idf = @import("esp_idf");
const sys = idf.sys;

const log = std.log.scoped(.right_hand_man);

const UART_PORT: c_uint = 1; // UART1
const BAUD_RATE = 115200;
const BUF_SIZE = 256;

const TX_PIN: c_int = 43;
const RX_PIN: c_int = 44;

const maestro_solver = @import("solver");
const MessageParser = maestro_solver.packet.MessageParser;

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

    _ = alloc;

    setPin(UART_PORT, .{
        .tx = TX_PIN,
        .rx = RX_PIN,
    }) catch unreachable;

    idf.uart.driverInstall(UART_PORT, .{
        .rx_buffer_size = BUF_SIZE * 2,
        .tx_buffer_size = 0,
    }) catch unreachable;

    var buf: [BUF_SIZE]u8 = undefined;
    while (true) {
        const n = idf.uart.readBytes(UART_PORT, &buf, sys.portMAX_DELAY) catch unreachable;
        for (0..n) |_| {
            if (parser.feedByte(buf[n])) |msg| {
                _ = msg;
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
