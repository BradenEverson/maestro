const std = @import("std");
const builtin = @import("builtin");
const idf = @import("esp_idf");

const log = std.log.scoped(.right_hand_man);

export fn app_main() callconv(.c) void {
    var heap: idf.heap.VPortAllocator = .init();
    const alloc = heap.allocator();

    _ = alloc;

    log.info("I'm the right hand!!!", .{});

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
