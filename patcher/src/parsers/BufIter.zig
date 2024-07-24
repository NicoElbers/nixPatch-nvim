const std = @import("std");
const mem = std.mem;

const Self = @This();

buf: []const u8,
ptr: usize = 0,

pub fn init(buf: []const u8) Self {
    return Self{
        .buf = buf,
        .ptr = 0,
    };
}

pub fn peek(self: Self) ?u8 {
    return self.buf[self.ptr];
}

pub fn next(self: *Self) ?u8 {
    defer self.ptr += 1;
    return self.peek();
}

const tst = std.testing;
const expect = tst.expect;
const expectEqual = tst.expectEqual;
const alloc = tst.allocator;

test "next" {
    const in = "abc";
    var iter = init(in);
    expect(iter.peek(), 'a');
    expect(iter.next(), 'a');
    expect(iter.peek(), 'b');
    expect(iter.next(), 'b');
    expect(iter.peek(), 'c');
    expect(iter.next(), 'c');
    expect(iter.peek(), null);
    expect(iter.next(), null);
}

// pub fn skipUntil(self: *BufIter, until: []const u8) ?void {
//     if ((self.ptr + until.len) >= self.buf.len) return null;

//     for ((self.ptr)..self.buf.len) |ptr| {
//         if (!mem.eql(u8, self.buf[ptr..(ptr + until.len)], until))
//             continue;

//         if (!mem.eql(u8, self.buf[ptr..(ptr + until.len)], until))
//             self.ptr = ptr;

//         return;
//     }
//     return null;
// }

// pub fn isDone(self: BufIter) bool {
//     return self.ptr >= self.buf.len;
// }

// pub fn thisChar(self: BufIter) ?u8 {
//     if (self.ptr >= self.buf.len) return null;
//     return self.buf[self.ptr];
// }

// pub fn thisWord(self: *BufIter) ?[]const u8 {
//     const str = self.peekThisWord() orelse return null;
//     defer self.ptr += str.len;
//     return str;
// }

// pub fn next(self: *BufIter) ?u8 {
//     defer self.ptr += 1;
//     return self.peek();
// }

// pub fn nextFor(self: *BufIter, n: usize) ?[]const u8 {
//     const str = self.peekFor(n) orelse return null;
//     defer self.ptr += str.len;
//     return str;
// }

// pub fn nextUntil(self: *BufIter, until: []const u8) ?[]const u8 {
//     const str = self.peekUntil(until) orelse return null;
//     defer self.ptr += str.len;
//     return str;
// }

// pub fn nextUntilExcluding(self: *BufIter, until: []const u8) ?[]const u8 {
//     const str = self.peekUntilBefore(until) orelse return null;
//     defer self.ptr += str.len + 1;
//     return str;
// }

// pub fn nextUntilAny(self: *BufIter, until: []const u8) ?[]const u8 {
//     const str = self.peekUntilAny(until) orelse return null;
//     defer self.ptr += str.len;
//     return str;
// }

// pub fn rest(self: *BufIter) ?[]const u8 {
//     const str = self.peekRest() orelse return null;
//     defer self.ptr += str.len;
//     return str;
// }

// pub fn peek(self: BufIter) ?u8 {
//     return self.peekBy(1);
// }

// pub fn peekBy(self: BufIter, n: usize) ?u8 {
//     if ((self.ptr + n) >= self.buf.len) return null;
//     return self.buf[self.ptr + n];
// }

// pub fn peekFor(self: BufIter, n: usize) ?[]const u8 {
//     if ((self.ptr + n) >= self.buf.len) return null;
//     return self.buf[self.ptr..(self.ptr + n)];
// }

// pub fn peekRest(self: BufIter) ?[]const u8 {
//     if (self.ptr >= self.buf.len) return null;
//     return self.buf[self.ptr..];
// }

// pub fn peekThisWord(self: BufIter) ?[]const u8 {
//     const char = self.thisChar() orelse return null;
//     if (isWhitespace(char)) return null;

//     for (self.ptr..self.buf.len) |ptr| {
//         if (!isWhitespace(self.buf[ptr])) continue;
//         return self.buf[self.ptr..ptr];
//     }
//     return self.buf[self.ptr..];
// }

// pub fn peekUntil(self: BufIter, until: []const u8) ?[]const u8 {
//     if ((self.ptr + until.len) > self.buf.len) return null;

//     for ((self.ptr + 1)..self.buf.len) |ptr| {
//         if (!mem.eql(u8, self.buf[ptr..(ptr + until.len)], until))
//             continue;

//         return self.buf[self.ptr..(ptr + until.len)];
//     }
//     return null;
// }

// pub fn peekUntilBefore(self: BufIter, until: []const u8) ?[]const u8 {
//     if ((self.ptr + until.len) > self.buf.len) return null;

//     for ((self.ptr)..(self.buf.len - until.len + 1)) |ptr| {
//         if (!mem.eql(u8, self.buf[ptr..(ptr + until.len)], until))
//             continue;

//         return self.buf[self.ptr..ptr];
//     }
//     return null;
// }

// pub fn peekUntilAny(self: BufIter, until: []const u8) ?[]const u8 {
//     if ((self.ptr + 1) >= self.buf.len) return null;

//     for ((self.ptr + 1)..self.buf.len) |ptr| {
//         const char = self.buf[ptr];
//         for (until) |until_char| {
//             if (char != until_char) continue;

//             return self.buf[self.ptr..ptr];
//         }
//     }
//     return null;
// }
