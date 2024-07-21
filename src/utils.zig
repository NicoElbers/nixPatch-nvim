const std = @import("std");
const fs = std.fs;
const mem = std.mem;
const assert = std.debug.assert;

const File = fs.File;
const Allocator = mem.Allocator;

pub const Plugin = struct {
    pname: []const u8,
    version: []const u8,
    path: []const u8,

    tag: Tag,
    url: []const u8,

    const Tag = enum {
        /// url field in undefined
        UrlNotFound,

        /// url field is github url
        GithubUrl,

        /// url field is non specific url
        GitUrl,
    };

    pub fn deinit(self: Plugin, alloc: Allocator) void {
        alloc.free(self.pname);
        alloc.free(self.version);
        alloc.free(self.path);

        if (self.tag == .UrlNotFound) return;

        alloc.free(self.url);
    }
};

pub const Substitution = struct {
    from: []const u8,
    to: []const u8,
    pname: []const u8,

    const Tag = enum { url, githubShort };

    pub fn init(
        alloc: Allocator,
        from: []const u8,
        to: []const u8,
        pname: []const u8,
    ) !Substitution {
        return Substitution{
            .from = try std.fmt.allocPrint(alloc, "\"{s}\"", .{from}),
            .to = try std.fmt.allocPrint(alloc, "dir = \"{s}\"", .{to}),
            .pname = try std.fmt.allocPrint(alloc, "name = \"{s}\"", .{pname}),
        };
    }
    pub fn deinit(self: Substitution, alloc: Allocator) void {
        alloc.free(self.to);
        alloc.free(self.from);
        alloc.free(self.pname);
    }
};

const MmapConfig = struct {
    read: bool = true,
    write: bool = false,
};

pub fn mmapFile(file: File, config: MmapConfig) ![]align(mem.page_size) u8 {
    // TODO: make an mmap alternative for windows
    assert(@import("builtin").os.tag != .windows);

    const md = try file.metadata();
    assert(md.size() <= std.math.maxInt(usize));

    var prot: u32 = 0;
    if (config.read) prot |= std.posix.PROT.READ;
    if (config.write) prot |= std.posix.PROT.WRITE;

    return try std.posix.mmap(
        null,
        @intCast(md.size()),
        prot,
        .{ .TYPE = .SHARED },
        file.handle,
        0,
    );
}

pub fn unMmapFile(mapped_file: []align(mem.page_size) u8) void {
    // TODO: make an mmap alternative for windows
    assert(@import("builtin").os.tag != .windows);

    std.posix.munmap(mapped_file);
}

pub fn trim(input: []const u8) []const u8 {
    return mem.trim(u8, input, " \\;{}\"\n");
}

pub fn split(input: []const u8) mem.SplitIterator(u8, .sequence) {
    return mem.splitSequence(u8, input, "=");
}

pub fn eql(expected: []const u8, input: []const u8) bool {
    return mem.eql(u8, expected, trim(input));
}

pub const BufIter = struct {
    buf: []const u8,
    ptr: usize = 0,

    pub fn skipUntil(self: *BufIter, until: []const u8) ?void {
        if ((self.ptr + until.len) >= self.buf.len) return null;

        for ((self.ptr)..self.buf.len) |ptr| {
            std.debug.print("lookin at: '{s}'\n", .{self.buf[ptr..(ptr + until.len)]});
            std.debug.print("lookin to: '{s}'\n", .{until});
            if (!std.mem.eql(u8, self.buf[ptr..(ptr + until.len)], until))
                continue;

            std.debug.print("found    : '{s}'\n", .{until});
            if (!std.mem.eql(u8, self.buf[ptr..(ptr + until.len)], until))
                self.ptr = ptr;

            return;
        }
        return null;
    }

    pub fn isDone(self: BufIter) bool {
        return self.ptr >= self.buf.len;
    }

    pub fn thisChar(self: BufIter) ?u8 {
        if (self.ptr >= self.buf.len) return null;
        return self.buf[self.ptr];
    }

    pub fn thisWord(self: *BufIter) ?[]const u8 {
        const str = self.peekThisWord() orelse return null;
        defer self.ptr += str.len;
        return str;
    }

    pub fn next(self: *BufIter) ?u8 {
        defer self.ptr += 1;
        return self.peek();
    }

    pub fn nextFor(self: *BufIter, n: usize) ?[]const u8 {
        const str = self.peekFor(n) orelse return null;
        defer self.ptr += str.len;
        return str;
    }

    pub fn nextUntil(self: *BufIter, until: []const u8) ?[]const u8 {
        const str = self.peekUntil(until) orelse return null;
        defer self.ptr += str.len;
        return str;
    }

    pub fn nextUntilAny(self: *BufIter, until: []const u8) ?[]const u8 {
        const str = self.peekUntilAny(until) orelse return null;
        defer self.ptr += str.len;
        return str;
    }

    pub fn rest(self: *BufIter) ?[]const u8 {
        const str = self.peekRest() orelse return null;
        defer self.ptr += str.len;
        return str;
    }

    pub fn peek(self: BufIter) ?u8 {
        return self.peekBy(1);
    }

    pub fn peekBy(self: BufIter, n: usize) ?u8 {
        if ((self.ptr + n) >= self.buf.len) return null;
        return self.buf[self.ptr + n];
    }

    pub fn peekFor(self: BufIter, n: usize) ?[]const u8 {
        if ((self.ptr + n) >= self.buf.len) return null;
        return self.buf[self.ptr..(self.ptr + n)];
    }

    pub fn peekRest(self: BufIter) ?[]const u8 {
        if (self.ptr >= self.buf.len) return null;
        return self.buf[self.ptr..];
    }

    pub fn peekThisWord(self: BufIter) ?[]const u8 {
        const char = self.thisChar() orelse return null;
        if (isWhitespace(char)) return null;

        for (self.ptr..self.buf.len) |ptr| {
            if (!isWhitespace(self.buf[ptr])) continue;
            return self.buf[self.ptr..ptr];
        }
        return self.buf[self.ptr..];
    }

    pub fn peekUntil(self: BufIter, until: []const u8) ?[]const u8 {
        if ((self.ptr + until.len) > self.buf.len) return null;

        for ((self.ptr + 1)..self.buf.len) |ptr| {
            if (!std.mem.eql(u8, self.buf[ptr..(ptr + until.len)], until))
                continue;

            return self.buf[self.ptr..(ptr + until.len)];
        }
        return null;
    }

    pub fn peekUntilBefore(self: BufIter, until: []const u8) ?[]const u8 {
        if ((self.ptr + until.len) > self.buf.len) return null;

        for ((self.ptr)..(self.buf.len - until.len + 1)) |ptr| {
            if (!std.mem.eql(u8, self.buf[ptr..(ptr + until.len)], until))
                continue;

            return self.buf[self.ptr..ptr];
        }
        return null;
    }

    pub fn peekUntilAny(self: BufIter, until: []const u8) ?[]const u8 {
        if ((self.ptr + 1) >= self.buf.len) return null;

        for ((self.ptr + 1)..self.buf.len) |ptr| {
            const char = self.buf[ptr];
            for (until) |until_char| {
                if (char != until_char) continue;

                return self.buf[self.ptr..ptr];
            }
        }
        return null;
    }
};

pub fn isWhitespace(char: u8) bool {
    const whitespace = " \n";
    inline for (whitespace) |ws_char| {
        if (char == ws_char) return true;
    }
    return false;
}
