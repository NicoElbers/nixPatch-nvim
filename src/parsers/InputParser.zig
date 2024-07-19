const std = @import("std");
const fs = std.fs;
const assert = std.debug.assert;

const Allocator = std.mem.Allocator;
const File = std.fs.File;

const Self = @This();

generated_vim_plugin_file: File,
input_blob: []const u8,
alloc: Allocator,

pub fn init(alloc: Allocator, nixpkgs_path: []const u8, input_blob: []const u8) !Self {
    assert(fs.path.isAbsolute(nixpkgs_path));

    const full_path = try fs.path.join(alloc, &.{
        nixpkgs_path,
        "pkgs",
        "applications",
        "editors",
        "vim",
        "plugins",
        "generated.nix",
    });
    defer alloc.free(full_path);

    std.log.debug("Attempting to open file {s}", .{full_path});
    const file = try fs.openFileAbsolute(full_path, .{});

    return Self{
        .alloc = alloc,
        .generated_vim_plugin_file = file,
        .input_blob = input_blob,
    };
}

pub fn deinit(self: *Self) void {
    self.generated_vim_plugin_file.close();
}
