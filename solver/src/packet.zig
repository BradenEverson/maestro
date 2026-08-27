//! Packet protocol, putting it here so it can be shared commonly amongst the two esp32 images

const std = @import("std");
const root = @import("root.zig");

pub const MAGIC_NUMBER: u8 = 0x72;

pub const RightHandOp = enum(u8) {
    move,
    press,
    depress,
};

pub const RightHandMessage = union(RightHandOp) {
    move: struct { dir: root.Direction, white_keys: u8 },
    press: u8,
    depress: u8,

    /// Writes a message as bytes to the resulting buffer
    ///
    /// Real important that the buffer is big enough to support the max
    /// message size
    pub fn toBytesToSend(msg: *const RightHandMessage, buf: []u8) []u8 {
        buf[0] = MAGIC_NUMBER;
        const msg_op: RightHandOp = msg.*;

        buf[1] = @intFromEnum(msg_op);

        const msg_len: u8 = switch (msg.*) {
            .move => 2,
            .press, .depress => 1,
        };

        buf[2] = msg_len;

        switch (msg.*) {
            .move => |mv| {
                buf[3] = @intFromEnum(mv.dir);
                buf[4] = mv.white_keys;
            },

            .press => |p| buf[3] = p,
            .depress => |d| buf[3] = d,
        }

        return buf[0..(3 + msg_len)];
    }
};

const ParserState = enum {
    waiting_for_magic_number,
    read_opcode,
    read_payload,
};

pub const MessageParser = struct {
    op: RightHandOp = undefined,
    curr_message: RightHandMessage = undefined,

    payload_len: usize = 0,
    payload_ptr: usize = 0,

    state: ParserState = .waiting_for_magic_number,
};

test "Messages to bytes" {
    const msg: RightHandMessage = .{ .move = .{ .dir = .left, .white_keys = 10 } };
    var buf: [32]u8 = undefined;
    var res = msg.toBytesToSend(&buf);
    try std.testing.expectEqualSlices(u8, &[_]u8{ 0x72, 0x00, 2, 0, 10 }, res);

    const press: RightHandMessage = .{ .press = 3 };
    res = press.toBytesToSend(&buf);
    try std.testing.expectEqualSlices(u8, &[_]u8{ 0x72, 0x01, 1, 3 }, res);

    const depress: RightHandMessage = .{ .depress = 10 };
    res = depress.toBytesToSend(&buf);
    try std.testing.expectEqualSlices(u8, &[_]u8{ 0x72, 0x02, 1, 10 }, res);
}
