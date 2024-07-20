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
    tag: Tag,
    from: []const u8,
    to: []const u8,

    const Tag = enum { url, githubShort };
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
    return mem.trim(u8, input, " ;{}\"\n");
}

pub fn split(input: []const u8) mem.SplitIterator(u8, .sequence) {
    return mem.splitSequence(u8, input, "=");
}

pub fn eql(expected: []const u8, input: []const u8) bool {
    return mem.eql(u8, expected, trim(input));
}
