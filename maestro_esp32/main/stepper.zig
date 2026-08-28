//! Stepper motor control!!

const idf = @import("esp_idf");
const Direction = @import("solver").Direction;

relative_position: usize = 0,

step_pin: idf.gpio.Num(),
direction_pin: idf.gpio.Num(),
endstop_pin: idf.gpio.Num(),
direction: Direction,

extern fn esp_rom_delay_us(us: u32) void;

const Self = @This();

pub fn init(
    step_pin: idf.gpio.Num(),
    direction_pin: idf.gpio.Num(),
    endstop_pin: idf.gpio.Num(),
) !Self {
    try idf.gpio.Direction.set(step_pin, .output);
    try idf.gpio.Direction.set(direction_pin, .output);
    try idf.gpio.Direction.set(endstop_pin, .input);

    try idf.gpio.Level.set(step_pin, 0);
    try idf.gpio.Level.set(direction_pin, 0);

    return .{
        .step_pin = step_pin,
        .direction = @enumFromInt(1),
        .direction_pin = direction_pin,
        .endstop_pin = endstop_pin,
    };
}

pub fn home(stepper: *Self, home_direction: Direction) !void {
    try stepper.switchDirection(home_direction);

    var homed = false;
    stepper.relative_position = 255;

    while (!homed) {
        try stepper.step();
        homed = idf.gpio.Level.get(stepper.endstop_pin);
    }

    stepper.relative_position = 0;
}

pub fn step(stepper: *Self) !void {
    try idf.gpio.Level.set(stepper.step_pin, 1);
    esp_rom_delay_us(500);

    try idf.gpio.Level.set(stepper.step_pin, 0);
    esp_rom_delay_us(500);

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
