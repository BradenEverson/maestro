//! Stepper motor control!!

const idf = @import("esp_idf");
const Direction = @import("solver").Direction;

relative_position: usize = 0,

step_pin: idf.gpio.Num(),
direction_pin: idf.gpio.Num(),
direction: Direction,

extern fn esp_rom_delay_us(us: u32) void;

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
    esp_rom_delay_us(125);

    try idf.gpio.Level.set(stepper.step_pin, 0);
    esp_rom_delay_us(125);

    if (stepper.direction == .left) {
        stepper.relative_position -= 1;
    } else {
        stepper.relative_position += 1;
    }
}

pub fn goHome(stepper: *Self) !void {
    try stepper.switchDirection(.left);
    while (stepper.relative_position > 0) {
        try stepper.step();
    }
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
