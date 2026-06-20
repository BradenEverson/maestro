//! One of the two hands that are at any point positioned on one
//! of the scales

const idf = @import("esp_idf");
const Stepper = @import("stepper.zig");

/// Which level of the scales is tha hand at
level: u8,

/// GPIO pins for the solonoids running each key
note_gpios: [NOTE_COUNT]idf.gpio.Num(),

stepper: Stepper,

pub const Note = enum(usize) {
    c,
    d,
    e,
    f,
    g,
    a,
    b,

    csharp,
    dsharp,
    fsharp,
    gsharp,
    asharp,
};
const NOTE_COUNT: usize = @typeInfo(Note).@"enum".fields.len;

const Hand = @This();

pub fn noteFromInt(n: u8) Note {
    return switch (n) {
        24 => .c,
        25 => .csharp,
        26 => .d,
        27 => .dsharp,
        28 => .e,
        29 => .f,
        30 => .fsharp,
        31 => .g,
        32 => .gsharp,
        33 => .a,
        34 => .asharp,
        35 => .b,

        else => .c, // TODO: Not this (but if we do option we'll just unwrap it anyway)
    };
}

pub fn init(
    notes: [NOTE_COUNT]idf.gpio.Num(),
    step: idf.gpio.Num(),
    dir: idf.gpio.Num(),
    level: u8,
) !Hand {
    for (notes) |note| {
        try idf.gpio.Direction.set(note, .output);
        try idf.gpio.Level.set(note, 0);
    }

    const stepper = try Stepper.init(
        step,
        dir,
    );

    return .{
        .note_gpios = notes,
        .level = level,
        .stepper = stepper,
    };
}

pub fn pressNote(self: *Hand, note: Note) !void {
    const selection = self
        .note_gpios[@intFromEnum(note)];

    try idf.gpio.Level.set(selection, 1);
}

pub fn depressNote(self: *Hand, note: Note) !void {
    const selection = self
        .note_gpios[@intFromEnum(note)];

    try idf.gpio.Level.set(selection, 0);
}

const stepsToLevel: usize = 1;

pub fn moveToLevel(self: *Hand, to: usize) void {
    _ = self;
    _ = to;
}
