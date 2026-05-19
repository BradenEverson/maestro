const std = @import("std");
const hal = @import("hal.zig");

export fn run() void {
    hal.enable(.a);

    hal.output(.a, 5);

    while (true) {
        hal.set(.a, 5);

        delay();

        hal.reset(.a, 5);

        delay();
    }
}

fn delay() void {
    for (0..100_000) |i| {
        std.mem.doNotOptimizeAway(i);
    }
}

export fn __aeabi_unwind_cpp_pr0() void {
    while (true) {}
}
