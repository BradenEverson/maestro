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
        26 => .d,
        28 => .e,
        29 => .f,
        31 => .g,
        33 => .a,
        35 => .b,

        else => .c, // TODO: Not this (but if we do option we'll just unwrap it anyway)
    };
}

pub fn init(
    notes: [NOTE_COUNT]idf.gpio.Num(),
    level: u8,
) !Hand {
    for (notes) |note| {
        try idf.gpio.Direction.set(note, .output);
        try idf.gpio.Level.set(note, 0);
    }

    return .{ .note_gpios = notes, .level = level };
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
