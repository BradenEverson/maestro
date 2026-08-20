//! Hand specific controls :D

const std = @import("std");

pub const OCTAVE_SIZE: usize = 12;

/// time in ms it takes to move a single key
pub const TIME_TO_MOVE_KEY: usize = 30;

fn isBlackKey(key: usize) bool {
    const octave_idx = key % OCTAVE_SIZE;
    return switch (octave_idx) {
        1, 3, 6, 8, 10 => true,
        else => false,
    };
}

fn whiteKeysBefore(pos: usize) usize {
    var count: usize = 0;
    var i: usize = 0;
    while (i < pos) : (i += 1) {
        if (!isBlackKey(i)) count += 1;
    }
    return count;
}

fn slotTypeMatches(hand_index: usize, key: usize) bool {
    if (isBlackKey(key)) {
        return hand_index % OCTAVE_SIZE == 0;
    }
    return isBlackKey(key) == isBlackKey(key - hand_index);
}

fn whiteKeyDistance(from: usize, to: usize) usize {
    const wb_from = whiteKeysBefore(from);
    const wb_to = whiteKeysBefore(to);

    if (from > to) {
        return wb_from - wb_to;
    } else {
        return wb_to - wb_from;
    }
}

pub const Hand = enum {
    left,
    right,
};

pub const HandInfo = struct {
    index: usize,
    pressing: [OCTAVE_SIZE]bool = @splat(false),

    pub fn isFree(hand: *const HandInfo) bool {
        for (hand.pressing) |key|
            if (key) return false;

        return true;
    }

    pub fn isOctaveAligned(hand: *const HandInfo) bool {
        return hand.index % OCTAVE_SIZE == 0;
    }

    pub fn covers(hand: *const HandInfo, global_key: usize) bool {
        var cond = (global_key >= hand.index) and
            (global_key < hand.index + OCTAVE_SIZE);

        if (isBlackKey(global_key)) {
            cond = cond and hand.isOctaveAligned();
        }

        return cond;
    }

    fn nearestValidIndex(hand: *const HandInfo, go_to: usize) usize {
        if (isBlackKey(go_to)) {
            const octave = go_to / OCTAVE_SIZE;
            return octave * OCTAVE_SIZE;
        }

        const naive: usize = if (go_to > hand.index)
            go_to -| (OCTAVE_SIZE - 1)
        else
            go_to;

        const candidate = naive;
        var offset: usize = 0;
        while (offset < OCTAVE_SIZE) : (offset += 1) {
            const try_idx = if (candidate >= offset) candidate - offset else candidate + offset;
            if (slotTypeMatches(try_idx, go_to) and
                go_to >= try_idx and go_to < try_idx + OCTAVE_SIZE)
            {
                return try_idx;
            }
            const try_idx2 = candidate + offset;
            if (slotTypeMatches(try_idx2, go_to) and
                go_to >= try_idx2 and go_to < try_idx2 + OCTAVE_SIZE)
            {
                return try_idx2;
            }
        }

        const octave = go_to / OCTAVE_SIZE;
        return octave * OCTAVE_SIZE;
    }

    pub fn timeToGetThere(hand: *const HandInfo, go_to: usize, ticks_per_key: usize) usize {
        if (hand.covers(go_to)) return 0;
        const target = hand.nearestValidIndex(go_to);
        return whiteKeyDistance(hand.index, target) * ticks_per_key;
    }

    pub fn moveTo(hand: *HandInfo, go_to: usize) void {
        if (hand.covers(go_to)) return;
        hand.index = hand.nearestValidIndex(go_to);
    }

    pub fn getKey(hand: *HandInfo, key: usize) *bool {
        return &hand.pressing[key];
    }

    pub fn globalToLocal(hand: *const HandInfo, global_key: usize) ?usize {
        if (!hand.covers(global_key)) {
            return null;
        }

        return global_key - hand.index;
    }

    pub fn getGlobalKey(hand: *HandInfo, global_key: usize) ?*bool {
        if (!hand.covers(global_key)) {
            return null;
        }

        return &hand.pressing[global_key - hand.index];
    }

    pub fn lowestUsed(hand: *const HandInfo) ?usize {
        if (!hand.isFree())
            return null;

        var idx: usize = 0;
        for (hand.pressing) |key| {
            if (key)
                break;

            idx += 1;
        }

        return idx;
    }
};

test "black key identification" {
    try std.testing.expect(isBlackKey(58));
    try std.testing.expect(isBlackKey(56));
    try std.testing.expect(isBlackKey(54));
    try std.testing.expect(isBlackKey(51));
    try std.testing.expect(isBlackKey(49));
}
