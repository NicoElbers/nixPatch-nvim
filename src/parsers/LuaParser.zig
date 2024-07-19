const std = @import("std");
const fs = std.fs;
const assert = std.debug.assert;

const Allocator = std.mem.Allocator;
const File = fs.File;
const Dir = fs.Dir;

const Self = @This();

alloc: Allocator,
in_dir: Dir,
out_dir: Dir,

pub fn init(alloc: Allocator, in_path: []const u8, out_path: []const u8) !Self {
    assert(fs.path.isAbsolute(in_path));
    assert(fs.path.isAbsolute(out_path));

    std.log.debug("Attempting to open dir {s}", .{in_path});
    const in_dir = try fs.openDirAbsolute(in_path, .{});

    std.log.debug("Attempting to create {s}", .{out_path});
    try fs.makeDirAbsolute(out_path);
    std.log.debug("Attempting to open {s}", .{out_path});
    const out_dir = try fs.openDirAbsolute(out_path, .{});

    return Self{
        .alloc = alloc,
        .in_dir = in_dir,
        .out_dir = out_dir,
    };
}

pub fn deinit(self: *Self) void {
    self.in_dir.close();
    self.out_dir.close();
}
