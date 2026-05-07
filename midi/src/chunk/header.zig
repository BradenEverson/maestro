//! Header Chunk Definition

/// The overall organization of the MIDI file. Only three values are valid, making most of the 16
/// bits irrelevant
pub const Format = enum {
    /// The file contains a single multi-channel track
    Zero,
    /// The file contains one or more simultaneous tracks (or MIDI outputs) of a sequence
    One,
    /// The file contains one or more sequentially independent single-track patterns
    Two,
};

/// The meaning of the delta-times in the MIDI sequence,
pub const Division = union(enum) {
    /// When bit 15 is a 0, bits 14-0 represent ticks per quarter note
    metrical: u16,
    /// When bit 15 is 1, bits 14-8 represent the negative SMPTE format,
    /// and bits 7-0 represent ticks per frame
    time_code: SmpteTicks,
};

/// Division defined by time-code-based time
pub const SmpteTicks = union(enum) {
    /// 7 bits of negative timecode
    smpte: i8,
    /// 8 bits of ticks per frame
    tpf: u8,
};

/// The format of the rest of the file
format: Format,
/// How many tracks we've got
ntrks: u16,
/// Time signature or division
division: Division,
