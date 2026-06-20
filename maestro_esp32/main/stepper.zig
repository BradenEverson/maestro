//! Stepper motor control!!

const idf = @import("esp_idf");

const Direction = enum(u32) {
    left = 0,
    right = 1,
};

step_pin: idf.gpio.Num(),
direction_pin: idf.gpio.Num(),
direction: Direction,

const Self = @This();

pub fn init(
    step_pin: idf.gpio.Num(),
    direction_pin: idf.gpio.Num(),
) !Self {
    try idf.gpio.Direction.set(step_pin, .output);
    try idf.gpio.Direction.set(direction_pin, .output);

    try idf.gpio.Level.set(step_pin, 0);
    try idf.gpio.Level.set(direction_pin, 0);

    return .{
        .step_pin = step_pin,
        .direction = @enumFromInt(0),
        .direction_pin = direction_pin,
    };
}

pub fn step(stepper: *Self) !void {
    try idf.gpio.Level.set(stepper.step_pin, 1);
    idf.rtos.Task.delayMs(1);
    try idf.gpio.Level.set(stepper.step_pin, 0);
    idf.rtos.Task.delayMs(1);
}

pub fn switchDirection(stepper: *Self, dir: Direction) !void {
    if (stepper.direction != dir) {
        try idf.gpio.Level.set(
            stepper.direction_pin,
            @intFromEnum(dir),
        );

        stepper.direction = dir;
    }
}
