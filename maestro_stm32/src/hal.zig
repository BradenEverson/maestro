//! Hardware Abstraction Layer of Fun and Happiness!!!

extern var RCC_AHB1ENR: u32;

extern var GPIOA_MODER: u32;
extern var GPIOA_BSRR: u32;

extern var GPIOB_MODER: u32;
extern var GPIOB_BSRR: u32;

extern var GPIOC_MODER: u32;
extern var GPIOC_BSRR: u32;

pub const Port = enum {
    a,
    b,
    c,
};

fn getPortMode(port: Port) *u32 {
    return switch (port) {
        .a => &GPIOA_MODER,
        .b => &GPIOB_MODER,
        .c => &GPIOC_MODER,
    };
}

fn getPortBSRR(port: Port) *u32 {
    return switch (port) {
        .a => &GPIOA_BSRR,
        .b => &GPIOB_BSRR,
        .c => &GPIOC_BSRR,
    };
}

pub fn enable(port: Port) void {
    const en: u32 = switch (port) {
        .a => 0x0000_0001,
        .b => 0x0000_0002,
        .c => 0x0000_0004,
    };

    RCC_AHB1ENR |= en;
}

pub fn output(port: Port, pin: u4) void {
    const pin_word = @as(u5, pin);
    const shift = pin_word * 2;

    const shifted: u32 = @as(u32, 0x01) << shift;
    const mask = ~(@as(u32, 0x11) << shift);

    const out = getPortMode(port);

    out.* = (out.* & mask) | shifted;
}

pub fn set(port: Port, pin: u4) void {
    const shift: u32 = @as(u32, 1) << pin;
    const out = getPortBSRR(port);

    out.* = shift;
}

pub fn reset(port: Port, pin: u4) void {
    const pin_word = @as(u5, pin);
    const shift: u32 = @as(u32, 1) << (pin_word + 16);
    const out = getPortBSRR(port);

    out.* = shift;
}
