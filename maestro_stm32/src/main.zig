const std = @import("std");
const hal = @import("hal.zig");

extern var TIM2_CR1: u32;
extern var TIM2_DIER: u32;
extern var TIM2_SR: u32;
extern var TIM2_EGR: u32;
extern var TIM2_PSC: u32;
extern var TIM2_ARR: u32;

// Add these declarations to use the linker-defined symbols
extern var RCC_APB1ENR: u32;
extern var NVIC_ISER0: u32;

export fn run() void {
    hal.enable(.a);
    hal.output(.a, 5);

    RCC_APB1ENR |= (1 << 0);

    const timer_freq = 16_000_000;
    const period_ms = 1000;
    const ticks = timer_freq * period_ms / 1000;
    TIM2_PSC = 0;
    TIM2_ARR = ticks - 1;

    TIM2_EGR |= (1 << 0);

    TIM2_SR &= ~@as(u32, 1);

    TIM2_DIER |= (1 << 0);

    NVIC_ISER0 |= (1 << 28);

    TIM2_CR1 |= (1 << 0);

    while (true) {}
}

var off: bool = true;

export fn tim2_handler() void {
    TIM2_SR &= ~@as(u32, 1);

    if (off) {
        hal.set(.a, 5);
    } else {
        hal.reset(.a, 5);
    }

    off = !off;
}

export fn __aeabi_unwind_cpp_pr0() void {
    while (true) {}
}
