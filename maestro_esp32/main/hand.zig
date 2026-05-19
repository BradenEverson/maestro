//! One of the two hands that are at any point positioned on one of the scales

const idf = @import("esp_idf");

/// Which level of the scales is tha hand at
level: u8,

/// GPIO pins for the solonoids running each key
note_gpios: [NOTE_COUNT]idf.gpio.Num(),

pub const Note = enum(usize) { c, d, e, f, g, a, b };
const NOTE_COUNT: usize = @typeInfo(Note).@"enum".fields.len;

const Hand = @This();

pub fn init(
    notes: [NOTE_COUNT]idf.gpio.Num(),
    level: u8,
) !Hand {
    for (notes) |note| {
        try idf.gpio.Direction.set(note, .output);
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
