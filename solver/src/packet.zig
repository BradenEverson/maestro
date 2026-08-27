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

        switch (msg.*) {
            .move => |mv| {
                buf[2] = @intFromEnum(mv.dir);
                buf[3] = mv.white_keys;
            },

            .press => |p| buf[2] = p,
            .depress => |d| buf[2] = d,
        }

        return buf[0..(2 + msg_len)];
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

    pub fn feedByte(mp: *MessageParser, byte: u8) ?RightHandMessage {
        switch (mp.state) {
            .waiting_for_magic_number => {
                if (byte == MAGIC_NUMBER) {
                    mp.state = .read_opcode;
                }
            },

            .read_opcode => {
                const op: RightHandOp = @enumFromInt(byte);
                mp.op = op;

                mp.state = .read_payload;

                switch (op) {
                    .move => mp.payload_len = 2,
                    .press, .depress => mp.payload_len = 1,
                }
            },

            .read_payload => {},
        }

        return null;
    }
};

test "Messages to bytes" {
    const msg: RightHandMessage = .{ .move = .{ .dir = .left, .white_keys = 10 } };
    var buf: [32]u8 = undefined;
    var res = msg.toBytesToSend(&buf);
    try std.testing.expectEqualSlices(u8, &[_]u8{ 0x72, 0x00, 0, 10 }, res);

    const press: RightHandMessage = .{ .press = 3 };
    res = press.toBytesToSend(&buf);
    try std.testing.expectEqualSlices(u8, &[_]u8{ 0x72, 0x01, 3 }, res);

    const depress: RightHandMessage = .{ .depress = 10 };
    res = depress.toBytesToSend(&buf);
    try std.testing.expectEqualSlices(u8, &[_]u8{ 0x72, 0x02, 10 }, res);
}

test "Feed bytes" {
    var parser: MessageParser = .{};

    var msg = parser.feedByte(0x72);
    try std.testing.expectEqual(null, msg);

    msg = parser.feedByte(0x01);
    try std.testing.expectEqual(null, msg);
}
