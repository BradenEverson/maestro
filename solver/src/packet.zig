//! Packet protocol, putting it here so it can be shared commonly amongst the two esp32 images

const root = @import("root.zig");

pub const RightHandOp = enum {
    move,
    press,
    depress,
};

pub const RightHandMessage = union(RightHandOp) {
    move: struct { dir: root.Direction, white_keys: u8 },
    press: u8,
    depress: u8,
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
