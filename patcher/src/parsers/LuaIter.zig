buf: []const u8,
ptr: usize = 0,
lua_string_cache: ?LuaStringCache = null,

const LuaStringCache = struct {
    ptr_check: usize,

    lua_string_type: LuaStringType,
    next_lua_string_start_on: usize,
    next_lua_string_end: ?usize,

    pub const LuaStringType = enum {
        singleQuote,
        doubleQuote,
        multiLine,
    };

    pub fn isValid(self: LuaStringCache, ptr: usize) bool {
        return self.ptr_check == ptr;
    }

    pub fn getNextLUaStringType(self: LuaStringCache, ptr: usize) ?LuaStringType {
        if (!self.isValid(ptr)) return null;

        return self.lua_string_type;
    }

    pub fn getNextLuaStringOpeningOn(self: LuaStringCache, ptr: usize) ?usize {
        if (!self.isValid(ptr)) return null;

        return self.next_lua_string_start_on;
    }

    pub fn getNextLuaStringEnd(self: LuaStringCache, ptr: usize) ?usize {
        if (!self.isValid(ptr)) return null;

        return self.next_lua_string_end;
    }
};

/// A call to next will show the first character
pub fn init(buf: []const u8) LuaIter {
    return LuaIter{
        .buf = buf,
        .ptr = 0,
        .lua_string_cache = null,
    };
}

/// A call to back will show the last character
pub fn initBack(buf: []const u8) LuaIter {
    return LuaIter{
        .buf = buf,
        .ptr = buf.len,
        .lua_string_cache = null,
    };
}

pub fn isDone(self: LuaIter) bool {
    return self.ptr < 0 or self.ptr >= self.buf.len;
}

pub fn isDoneReverse(self: LuaIter) bool {
    return self.ptr <= 0 or self.ptr > self.buf.len;
}

pub fn peek(self: LuaIter) ?u8 {
    if (self.isDone()) return null;
    return self.buf[self.ptr];
}

pub fn next(self: *LuaIter) ?u8 {
    defer self.ptr += 1;
    return self.peek();
}

pub fn peekBack(self: LuaIter) ?u8 {
    return self.peekBackBy(1);
}

pub fn peekBackBy(self: LuaIter, by: usize) ?u8 {
    if (self.ptr < by) return null;
    return self.buf[self.ptr - by];
}

pub fn back(self: *LuaIter) ?u8 {
    defer if (!self.isDoneReverse()) {
        self.ptr -= 1;
    };
    return self.peekBack();
}

pub fn peekNextLuaString(self: *LuaIter) ?[]const u8 {
    const start = self.findLuaStringOpeningAfter() orelse return null;
    const stop = self.findLuaStringClosingOn() orelse return null;
    return self.buf[start..stop];
}

/// Returns the slice before the next lua string
///    "String"
///    ^
///   Until this is returned
pub fn peekNextUntilLuaString(self: *LuaIter) ?[]const u8 {
    if (self.isDone()) return null;
    const string_start = self.findLuaStringOpeningOn() orelse return null;
    return self.buf[self.ptr..string_start];
}

pub fn peekNextStringTableHasKey(self: *LuaIter, key: []const u8) bool {
    const string_idx = self.findLuaStringOpeningOn() orelse return false;
    var backIter = LuaIter.initBack(self.buf[0..string_idx]);

    // Find the relevant start of table
    var brace_counter: u32 = 0;
    loop: while (backIter.back()) |char| switch (char) {
        '}' => brace_counter += 1,
        '{' => {
            if (brace_counter == 0)
                break :loop
            else
                brace_counter -= 1;
        },
        else => {},
    } else return false;

    // Find the equals
    loop: while (backIter.back()) |char| {
        // Ignore whitespace
        if (isInlineWhitespace(char)) continue;

        // If we do _not_ find an '=', this is invalid or irrelevant lua (I think)
        if (char != '=')
            return false;

        break :loop;
    } else return false;

    // Ignore whitespace
    while (isAnyWhitespace(backIter.back() orelse return false)) {}
    // Make sure we include the last character of the key
    _ = backIter.next();

    // There isn't enough space to fit the key
    if (backIter.ptr < key.len)
        return false;

    // If the key had more characters before it (say `xkey`),
    // then make sure that we return false
    const before_key = backIter.peekBackBy(key.len + 1);
    if (before_key != null and !isAnyWhitespace(before_key.?)) return false;

    const maybe_key = backIter.buf[(backIter.ptr - key.len)..backIter.ptr];
    return std.mem.eql(u8, key, maybe_key);
}

/// This function is equal to the following:
/// `{key}\s*=\s*{string}`
/// where:
///   {key}    is your input,
///   \s*      is any amount of whitespace excluding \n,
///   =        is the literal character,
///   {string} is the lua string,
///
/// It returns a slice from self.ptr to the first character of the key
pub fn peekUntilNextLuaStringKey(self: *LuaIter, key: []const u8) ?[]const u8 {
    const before_string = self.peekNextUntilLuaString() orelse return null;

    if (before_string.len <= key.len) return null;

    var iter = initBack(before_string);
    while (iter.back()) |char| {
        if (isInlineWhitespace(char)) continue;
        if (char == '=') break;

        // Non white space character is not '='
        return null;
    }

    const last_key_char = key[key.len - 1];

    while (iter.back()) |char| {
        if (isInlineWhitespace(char)) continue;
        if (char != last_key_char) return null;

        // Make sure to include the end char
        _ = iter.next();
        break;
    }

    if (iter.ptr >= key.len and
        mem.eql(u8, key, iter.buf[(iter.ptr - key.len)..iter.ptr]))
    {
        return iter.buf[0..(iter.ptr - key.len)];
    } else {
        return null;
    }
}
pub fn nextUntilBefore(self: *LuaIter, until: []const u8) ?[]const u8 {
    const str = self.peekUntilBefore(until) orelse return null;
    self.ptr += str.len;
    return str;
}

pub fn peekUntilBefore(self: LuaIter, until: []const u8) ?[]const u8 {
    if ((self.ptr + until.len) >= self.buf.len) return null;

    for ((self.ptr)..(self.buf.len - until.len + 1)) |ptr| {
        if (!std.mem.eql(u8, self.buf[ptr..(ptr + until.len)], until))
            continue;

        return self.buf[self.ptr..ptr];
    }
    return null;
}

pub fn nextUntilAfter(self: *LuaIter, until: []const u8) ?[]const u8 {
    const str = self.peekUntilAfter(until) orelse return null;
    self.ptr += str.len;
    return str;
}

pub fn peekUntilAfter(self: LuaIter, until: []const u8) ?[]const u8 {
    if ((self.ptr + until.len) >= self.buf.len) return null;

    for ((self.ptr)..(self.buf.len - until.len + 1)) |ptr| {
        if (!std.mem.eql(u8, self.buf[ptr..(ptr + until.len)], until))
            continue;

        return self.buf[self.ptr..(ptr + until.len)];
    }
    return null;
}

pub fn nextUntilAfterLuaString(self: *LuaIter) ?[]const u8 {
    const end_ptr = self.findLuaStringClosingAfter() orelse return null;
    defer self.ptr = end_ptr;
    return self.buf[self.ptr..end_ptr];
}

pub fn rest(self: *LuaIter) ?[]const u8 {
    if (self.isDone()) return null;
    defer self.ptr = self.buf.len;
    return self.buf[self.ptr..];
}

pub fn peekRest(self: *LuaIter) ?[]const u8 {
    if (self.isDone()) return null;
    return self.buf[self.ptr..];
}

pub const whitespace_inline = [_]u8{ ' ', '\t' };
fn isInlineWhitespace(char: u8) bool {
    inline for (whitespace_inline) |w| {
        if (char == w) return true;
    }
    return false;
}

pub const whitespace_any = whitespace_inline ++ [_]u8{'\n'};
fn isAnyWhitespace(char: u8) bool {
    inline for (whitespace_any) |w| {
        if (char == w) return true;
    }
    return false;
}

fn findLuaStringOpeningOn(self: *LuaIter) ?usize {
    if (self.isDone()) {
        return null;
    }

    if (self.lua_string_cache) |cache| {
        if (cache.getNextLuaStringOpeningOn(self.ptr)) |start_on| {
            return start_on;
        }
    }

    var iter = init(self.buf[self.ptr..]);

    var string_type: ?LuaStringCache.LuaStringType = null;
    while (iter.next()) |char| {
        if (char == '\'') {
            string_type = .singleQuote;
            break;
        }

        if (char == '"') {
            string_type = .doubleQuote;
            break;
        }

        if (char == '[' and iter.peek() != null and iter.peek() == '[') {
            string_type = .multiLine;
            break;
        }
    }

    if (iter.isDone()) {
        return null;
    } else {
        self.lua_string_cache = LuaStringCache{
            .ptr_check = self.ptr,
            .lua_string_type = string_type.?,
            .next_lua_string_start_on = self.ptr + iter.ptr - 1,
            .next_lua_string_end = null,
        };
        return self.ptr + iter.ptr - 1;
    }
}
fn findLuaStringOpeningAfter(self: *LuaIter) ?usize {
    const ptr = self.findLuaStringOpeningOn() orelse return null;
    if (self.buf[ptr] == '[') {
        return ptr + 2;
    } else {
        return ptr + 1;
    }
}

fn findLuaStringClosingOn(self: *LuaIter) ?usize {
    if (self.isDone()) {
        return null;
    }

    if (self.lua_string_cache) |cache| {
        if (cache.getNextLuaStringEnd(self.ptr)) |end| {
            return end;
        }
    }

    const start = self.findLuaStringOpeningAfter() orelse return null;
    assert(self.lua_string_cache != null); // The cache must exist after finding the opening
    var cache = &self.lua_string_cache.?;

    var iter = init(self.buf[start..]);

    while (iter.next()) |char| {
        switch (cache.lua_string_type) {
            .singleQuote => if (char != '\'') continue,
            .doubleQuote => if (char != '\"') continue,
            .multiLine => if (char != ']' or iter.peek() != ']') continue,
        }

        // Make sure the closing character is not escaped AND
        // that the escape is not escaped
        if (iter.peekBackBy(2) == '\\' and iter.peekBackBy(3) != '\\') continue;

        break;
    }

    if (iter.isDone() and iter.ptr != iter.buf.len) {
        return null;
    } else {
        cache.next_lua_string_end = (start + iter.ptr - 1);
        return cache.next_lua_string_end;
    }
}

fn findLuaStringClosingAfter(self: *LuaIter) ?usize {
    const ptr = self.findLuaStringClosingOn() orelse return null;
    if (self.buf[ptr] == ']') {
        return ptr + 2;
    } else {
        return ptr + 1;
    }
}

// TODO: Make a test folder for this shit
const tst = std.testing;
const expect = tst.expect;
const expectEqual = tst.expectEqual;
const expectEqualStrings = tst.expectEqualStrings;
const alloc = tst.allocator;

test "next/ peek" {
    const in = "abc";
    var iter = init(in);
    try expectEqual('a', iter.peek());
    try expectEqual('a', iter.peek());
    try expectEqual('a', iter.next());

    try expectEqual('b', iter.peek());
    try expectEqual('b', iter.peek());
    try expectEqual('b', iter.next());

    try expectEqual('c', iter.peek());
    try expectEqual('c', iter.peek());
    try expectEqual('c', iter.next());

    try expectEqual(null, iter.peek());
    try expectEqual(null, iter.peek());
    try expectEqual(null, iter.next());
    try expectEqual(null, iter.next());
}

test "back/ peekBack" {
    const in = "abc";
    var iter = initBack(in);
    try expectEqual('c', iter.peekBack());
    try expectEqual('c', iter.peekBack());
    try expectEqual('c', iter.back());

    try expectEqual('b', iter.peekBack());
    try expectEqual('b', iter.peekBack());
    try expectEqual('b', iter.back());

    try expectEqual('a', iter.peekBack());
    try expectEqual('a', iter.peekBack());
    try expectEqual('a', iter.back());

    try expectEqual(null, iter.peekBack());
    try expectEqual(null, iter.peekBack());
    try expectEqual(null, iter.back());
    try expectEqual(null, iter.back());
}

test "nextLuaString double" {
    const in =
        \\garbage"hello"garbage"garbage"
    ;
    var iter = init(in);
    try expectEqualStrings("hello", iter.peekNextLuaString().?);
    try expectEqualStrings("hello", iter.peekNextLuaString().?);
}

test "nextLuaString single" {
    const in =
        \\garbage'hello'garbage'garbage'
    ;
    var iter = init(in);
    try expectEqualStrings("hello", iter.peekNextLuaString().?);
    try expectEqualStrings("hello", iter.peekNextLuaString().?);
}

test "nextLuaString multiline" {
    const in =
        \\garbage[[hello
        \\world]]garbage[[garbage]]
    ;
    var iter = init(in);
    try expectEqualStrings("hello\nworld", iter.peekNextLuaString().?);
    try expectEqualStrings("hello\nworld", iter.peekNextLuaString().?);
}

test "nextLuaString empty" {
    const in =
        \\[[]]
    ;
    var iter = init(in);
    try expectEqualStrings("", iter.peekNextLuaString().?);
    try expectEqualStrings("", iter.peekNextLuaString().?);
}

test "nextLuaString first char" {
    const in =
        \\[[hello world]]
    ;
    var iter = init(in);
    try expectEqualStrings("hello world", iter.peekNextLuaString().?);
    try expectEqualStrings("hello world", iter.peekNextLuaString().?);
}

test "nextLuaStringHasKey no key" {
    const in = "[[hello]]";
    var iter = init(in);
    try expectEqual(null, iter.peekUntilNextLuaStringKey("some-key"));
}

test "nextLuaStringHasKey wrong key" {
    const in = "some-key = [[hello]]";
    var iter = init(in);
    try expectEqual(null, iter.peekUntilNextLuaStringKey("other-key"));
}

test "nextLuaStringHasKey right key" {
    const in = "some-key = [[hello]]";
    var iter = init(in);
    try expectEqualStrings("", iter.peekUntilNextLuaStringKey("some-key").?);
}

test "nextLuaStringHasKey no whitespace" {
    const in = "some-key=[[hello]]";
    var iter = init(in);
    try expectEqualStrings("", iter.peekUntilNextLuaStringKey("some-key").?);
}

test "nextLuaStringHasKey lost of whitespace" {
    const in = "   some-key    =       [[hello]]";
    var iter = init(in);
    try expectEqualStrings("   ", iter.peekUntilNextLuaStringKey("some-key").?);
}

test "nextLuaStringHasKey newline after =" {
    const in = "some-key =\n [[hello]]";
    var iter = init(in);
    try expectEqual(null, iter.peekUntilNextLuaStringKey("some-key"));
}

test "nextLuaStringHasKey newline before =" {
    const in = "some-key\n = [[hello]]";
    var iter = init(in);
    try expectEqual(null, iter.peekUntilNextLuaStringKey("some-key"));
}

test "nextLuaStringHasKey key obstructed" {
    const in = "some-key, = [[hello]]";
    var iter = init(in);
    try expectEqual(null, iter.peekUntilNextLuaStringKey("some-key"));
}

test "nextLuaStringHasKey no string" {
    const in = "garbage garbage";
    var iter = init(in);
    try expectEqual(null, iter.peekUntilNextLuaStringKey("some-key"));
}

test "skipAfterLuaString" {
    const in = "garbage[[hello]]x";
    var iter = init(in);
    try expect(iter.nextUntilAfterLuaString() != null);
    try expectEqual('x', iter.next());
}

test "string after skip" {
    const in = "[[Hello]] 'world'";
    var iter = init(in);
    try expect(iter.nextUntilAfterLuaString() != null);
    try expectEqualStrings("world", iter.peekNextLuaString().?);
}

test "findLuaStringClosing multiline" {
    const in = "[[h]]";
    var iter = init(in);
    try expectEqual(3, iter.findLuaStringClosingOn().?);
    try expectEqual(5, iter.findLuaStringClosingAfter().?);
}

test "findLuaStringClosing normal" {
    const in = "'h'";
    var iter = init(in);
    try expectEqual(2, iter.findLuaStringClosingOn().?);
    try expectEqual(3, iter.findLuaStringClosingAfter().?);
}

test "findLuaStringOpening multiline" {
    const in = "[[h]]";
    var iter = init(in);
    try expectEqual(0, iter.findLuaStringOpeningOn().?);
    try expectEqual(2, iter.findLuaStringOpeningAfter().?);
}

test "findLuaStringOpening normal" {
    const in = "'h'";
    var iter = init(in);
    try expectEqual(0, iter.findLuaStringOpeningOn().?);
    try expectEqual(1, iter.findLuaStringOpeningAfter().?);
}

test "nextUntilBefore single char" {
    const in = "hello|world|";
    var iter = init(in);
    try expectEqualStrings("hello", iter.nextUntilBefore("|").?);
    try expectEqual('|', iter.next().?);
    try expectEqualStrings("world", iter.nextUntilBefore("|").?);
    try expectEqual('|', iter.next().?);

    try expectEqual(null, iter.nextUntilBefore("|"));
}

test "nextUntilBefore rest" {
    const in = "hello|world";
    var iter = init(in);
    try expectEqualStrings("hello", iter.nextUntilBefore("|").?);
    try expectEqual('|', iter.next().?);
    try expectEqual(null, iter.nextUntilBefore("|"));
}

test "nextUntilBefore multi char" {
    const in = "hello|world|||";
    var iter = init(in);
    try expectEqualStrings("hello|world", iter.nextUntilBefore("|||").?);
    try expectEqual(null, iter.nextUntilBefore("|||"));
}

test "nextUntilBefore not present" {
    const in = "hello|world";
    var iter = init(in);
    try expectEqual(null, iter.nextUntilBefore("||"));
}

test "nextUntilBefore larger than str" {
    const in = "-";
    var iter = init(in);
    try expectEqual(null, iter.nextUntilBefore("||"));
}

test "Different string characters, valid string" {
    const in = "[[ \" ' ]]";
    var iter = init(in);
    const expected = " \" ' ";
    try expectEqualStrings(expected, iter.peekNextLuaString() orelse return error.failed);
}

test "Different string characters, no valid string" {
    const in = "]] \" ' [[";
    var iter = init(in);
    const expected = null;
    try expectEqual(expected, iter.peekNextLuaString());
}

test "poorly ended multiline" {
    const in = "[[ hello ]";
    var iter = init(in);
    const expected = null;
    try expectEqual(expected, iter.peekNextLuaString());
}

test "poorly started multiline" {
    const in = "[ hello ]]";
    var iter = init(in);
    const expected = null;
    try expectEqual(expected, iter.peekNextLuaString());
}

test "escaped double quote in string" {
    const in = "\" \\\" \""; // convertes to " \" "
    var iter = init(in);
    const expected = " \\\" ";
    try expectEqualStrings(expected, iter.peekNextLuaString() orelse return error.failed);
}

test "not escaped double quote in string" {
    const in = "\" \\\\\" \""; // converts to " \\" "
    var iter = init(in);
    const expected = " \\\\";
    try expectEqualStrings(expected, iter.peekNextLuaString() orelse return error.failed);
}

const std = @import("std");
const mem = std.mem;
const assert = std.debug.assert;

const LuaIter = @This();
