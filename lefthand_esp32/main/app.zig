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

const test_midi = @embedFile("runaway.mid");

const log = std.log.scoped(.maestro);
extern fn esp_rom_delay_us(us: u32) void;

const index_html = @embedFile("html/index.html");
const playing_html = @embedFile("html/playing.html");

export fn handleRoot(req: [*c]sys.httpd_req_t) callconv(.c) sys.esp_err_t {
    idf.http.Server.Response.sendStr(req, index_html) catch |err| {
        log.err("sendStr: {s}", .{@errorName(err)});
        return sys.ESP_FAIL;
    };
    return sys.ESP_OK;
}

export fn handlePlay(req: [*c]sys.httpd_req_t) callconv(.c) sys.esp_err_t {
    idf.http.Server.Response.sendStr(req, playing_html) catch |err| {
        log.err("sendStr: {s}", .{@errorName(err)});
        return sys.ESP_FAIL;
    };

    playSong();

    return sys.ESP_OK;
}

var g_event_group: sys.EventGroupHandle_t = null;
const CONNECTED_BIT: u32 = sys.WIFI_CONNECTED_BIT;

export fn onWifiEvent(_: ?*anyopaque, _: sys.esp_event_base_t, event_id: i32, _: ?*anyopaque) callconv(.c) void {
    if (event_id == sys.WIFI_EVENT_STA_START) {
        idf.wifi.connect() catch {};
    } else if (event_id == sys.WIFI_EVENT_STA_DISCONNECTED) {
        idf.wifi.connect() catch {};
    }
}

export fn onIpEvent(_: ?*anyopaque, _: sys.esp_event_base_t, event_id: i32, event_data: ?*anyopaque) callconv(.c) void {
    if (event_id == sys.IP_EVENT_STA_GOT_IP) {
        const ev = @as(*sys.ip_event_got_ip_t, @ptrCast(@alignCast(event_data)));
        const ip = ev.ip_info.ip.addr;
        log.info("Got IP: {}.{}.{}.{}", .{
            @as(u8, @truncate(ip)),
            @as(u8, @truncate(ip >> 8)),
            @as(u8, @truncate(ip >> 16)),
            @as(u8, @truncate(ip >> 24)),
        });
        _ = sys.xEventGroupSetBits(g_event_group, CONNECTED_BIT);
    }
}

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

fn doAllTheServerStartingStuff() void {
    idf.nvs.flashInitOrErase() catch |err| {
        log.err("NVS: {s}", .{@errorName(err)});
        return;
    };

    g_event_group = sys.xEventGroupCreate() orelse {
        log.err("xEventGroupCreate failed", .{});
        return;
    };
    idf.err.espCheckError(sys.esp_netif_init()) catch return;
    idf.event.loopCreateDefault() catch return;
    _ = sys.esp_netif_create_default_wifi_sta();

    var wifi_init_cfg = idf.wifi.init_config_default();
    idf.err.espCheckError(sys.esp_wifi_init(&wifi_init_cfg)) catch return;

    _ = idf.event.handlerInstanceRegister(sys.WIFI_EVENT, idf.event.ANY_ID, &onWifiEvent, null) catch return;
    _ = idf.event.handlerInstanceRegister(sys.IP_EVENT, sys.IP_EVENT_STA_GOT_IP, &onIpEvent, null) catch return;

    var wifi_config = idf.wifi.wifiConfig{
        .sta = .{
            .ssid = std.mem.zeroes([32]u8),
            .password = std.mem.zeroes([64]u8),
            .threshold = .{ .rssi = 0, .rssi_5g_adjustment = 0, .authmode = sys.WIFI_AUTH_WPA2_PSK },
            .sae_pwe_h2e = sys.WPA3_SAE_PWE_BOTH,
            .sae_h2e_identifier = std.mem.zeroes([32]u8),
        },
    };
    copyZ(&wifi_config.sta.ssid, sys.CONFIG_ESP_WIFI_SSID);
    copyZ(&wifi_config.sta.password, sys.CONFIG_ESP_WIFI_PASSWORD);

    idf.wifi.setMode(.WIFI_MODE_STA) catch return;
    idf.wifi.setConfig(.WIFI_IF_STA, &wifi_config) catch return;
    idf.wifi.start() catch return;

    log.info("Waiting for WiFi connection...", .{});
    _ = sys.xEventGroupWaitBits(g_event_group, CONNECTED_BIT, 0, 0, sys.portMAX_DELAY);

    startHttpServer() catch |err| {
        log.err("HTTP server start failed: {s}", .{@errorName(err)});
    };
}

var hand: Hand = undefined;

export fn app_main() callconv(.c) void {
    hand = Hand.init(
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

    doAllTheServerStartingStuff();

    while (true) {
        idf.rtos.Task.delayMs(100);
    }
}

fn playSong() void {
    var packet_buffer: [MAX_BUFFER_SIZE]u8 = undefined;
    var buf: [1]u8 = undefined;

    var heap: idf.heap.VPortAllocator = .init();
    const alloc = heap.allocator();

    var midi = MIDI.fromBytes(alloc, test_midi) catch |err| {
        log.err("MIDI Parse Failed {s}", .{@errorName(err)});
        return;
    };
    defer midi.deinit(alloc);

    log.info("Parse Complete!", .{});
    log.info("Solving MIDI!", .{});

    const tempo = maestro_solver.getTempo(midi.tracks[0].mtrk_events.items);

    if (midi.header.division != .metrical) {
        log.err("Only metrical supported for now", .{});
        return;
    }

    var solver: Solver = .{
        .instructions = midi.tracks[0].mtrk_events.items,
        .ticks_per_quarter = midi.header.division.metrical, // only support metrical rn :)

        .us_per_quarter = tempo.?,
    };

    var program: MaestroProgram = .{};

    defer program.deinit(alloc);

    solver.solve(alloc, &program) catch |err| {
        log.err("Solve Failed {s}", .{@errorName(err)});
        return;
    };
    log.info("Solve Complete!", .{});

    idf.rtos.Task.delayMs(1500);

    log.info("Solve Complete!", .{});

    const RTOS_HZ: u32 = 1000;

    const ticks_per_qn: u32 = @intCast(midi.header.division.metrical);

    const tempo_us = program.tempo;

    for (program.instructions.items) |instr| {
        const delay_ticks: u32 = @intCast(
            (@as(u64, instr.delay) * tempo_us * RTOS_HZ) /
                (@as(u64, ticks_per_qn) * 1_000_000),
        );

        if (delay_ticks > 0) {
            idf.rtos.Task.delay(delay_ticks);
        }

        if (instr.cmd.hand() == .right) {
            log.info("Sending Msg: {any}", .{instr.cmd});

            const packet = instr.cmd.toPacket();
            const send = packet.toBytesToSend(&packet_buffer);

            _ = idf.uart.writeBytes(UART_PORT, send) catch {
                log.err("Failed to write", .{});
            };

            switch (packet) {
                .move => {
                    _ = idf.uart.readBytes(UART_PORT, &buf, idf.rtos.portMAX_DELAY) catch {
                        log.err("Failed to read", .{});
                    };
                },
                else => {},
            }
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
                            log.err("Move Failed!!!", .{});
                            unreachable;
                        };
                    }
                },
            }
        }
    }

    log.info("DONE", .{});

    hand.stepper.goHome() catch unreachable;
}

fn startHttpServer() !void {
    var config = sys.zig_httpd_default_config();

    const server = try idf.http.Server.start(&config);

    const root_uri = sys.httpd_uri_t{
        .uri = "/",
        .method = sys.HTTP_GET,
        .handler = &handleRoot,
        .user_ctx = null,
    };
    try idf.http.Server.registerUri(server, &root_uri);

    const play_uri = sys.httpd_uri_t{
        .uri = "/play",
        .method = sys.HTTP_GET,
        .handler = &handlePlay,
        .user_ctx = null,
    };
    try idf.http.Server.registerUri(server, &play_uri);

    log.info("HTTP server started on port 80", .{});
}

fn copyZ(dest: []u8, src: []const u8) void {
    const n = @min(dest.len - 1, src.len);
    @memcpy(dest[0..n], src[0..n]);
    dest[n] = 0;
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
