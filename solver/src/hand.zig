//! Hand specific controls :D

const std = @import("std");

pub const OCTAVE_SIZE: usize = 12;

/// time in ms it takes to move a single key
pub const TIME_TO_MOVE_KEY: usize = 37;

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
        const in_range = (global_key >= hand.index) and
            (global_key < hand.index + OCTAVE_SIZE);

        if (!in_range) return false;

        const local = global_key - hand.index;

        if (isBlackKey(global_key)) {
            return isBlackKey(local) and hand.isOctaveAligned();
        }

        return !isBlackKey(local);
    }

    fn nearestValidIndex(hand: *const HandInfo, go_to: usize) usize {
        if (isBlackKey(go_to)) {
            const octave = go_to / OCTAVE_SIZE;
            return octave * OCTAVE_SIZE;
        }

        const lo: usize = go_to -| (OCTAVE_SIZE - 1);

        var best_idx: usize = go_to;
        var best_dist: usize = whiteKeyDistance(hand.index, go_to);

        var try_idx = lo;
        while (try_idx < go_to) : (try_idx += 1) {
            if (slotTypeMatches(try_idx, go_to)) {
                const dist = whiteKeyDistance(hand.index, try_idx);
                if (dist < best_dist) {
                    best_dist = dist;
                    best_idx = try_idx;
                }
            }
        }

        return best_idx;
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
