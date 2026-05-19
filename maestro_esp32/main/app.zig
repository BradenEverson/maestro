const std = @import("std");
const builtin = @import("builtin");
const idf = @import("esp_idf");

const MIDI = @import("midi");
const Hand = @import("hand.zig");

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

    while (true) {
        log.info("On", .{});
        hand.pressNote(.c) catch {};
        hand.pressNote(.d) catch {};
        hand.pressNote(.e) catch {};
        hand.pressNote(.f) catch {};
        hand.pressNote(.g) catch {};
        hand.pressNote(.a) catch {};
        hand.pressNote(.b) catch {};
        idf.rtos.Task.delayMs(1000);

        log.info("Off", .{});
        hand.depressNote(.c) catch {};
        hand.depressNote(.d) catch {};
        hand.depressNote(.e) catch {};
        hand.depressNote(.f) catch {};
        hand.depressNote(.g) catch {};
        hand.depressNote(.a) catch {};
        hand.depressNote(.b) catch {};
        idf.rtos.Task.delayMs(1000);
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
