test {
    _ = @import("luaparser-integration/root.zig");
    _ = @import("lazyvim/root.zig");
}

pub const alloc = testing.allocator;

pub fn run(cwd: Dir, path: []const u8, extra_init_config: []const u8, subs: []const Subs) !void {
    var base_dir = try cwd.openDir(path, .{});

    var in_dir = try base_dir.openDir("input", .{ .iterate = true });
    defer in_dir.close();

    try base_dir.makeDir("out");
    var out_dir = try base_dir.openDir("out", .{ .iterate = true });
    defer out_dir.close();

    var parser = try LuaParser.init(alloc, in_dir, out_dir, extra_init_config);

    try parser.createConfig(subs);
}

pub fn verify(cwd: Dir, path: []const u8) !void {
    var base_dir = try cwd.openDir(path, .{});

    var expected_dir = try base_dir.openDir("expected", .{ .iterate = true });
    defer expected_dir.close();

    var expected_walk = try expected_dir.walk(alloc);
    defer expected_walk.deinit();

    var out_dir = try base_dir.openDir("out", .{ .iterate = true });
    defer out_dir.close();

    var out_walk = try out_dir.walk(alloc);
    defer out_walk.deinit();

    while (try expected_walk.next()) |expected_entry| {
        const out_entry = (try out_walk.next()).?;
        try eqlString(expected_entry.basename, out_entry.basename);

        switch (expected_entry.kind) {
            .file => {
                var expected_file = try expected_entry.dir.openFile(expected_entry.basename, .{});
                defer expected_file.close();

                var out_file = try out_entry.dir.openFile(out_entry.basename, .{});
                defer out_file.close();

                try eqlFile(expected_file, out_file, expected_entry.path);
            },
            else => {},
        }
    }

    try expect(try out_walk.next() == null);
}

pub fn eqlFile(expected_file: File, out_file: File, file_name: []const u8) !void {
    const expected_buf = try utils.mmapFile(expected_file, .{});
    defer utils.unMmapFile(expected_buf);

    const out_buf = try utils.mmapFile(out_file, .{});
    defer utils.unMmapFile(out_buf);

    eqlString(expected_buf, out_buf) catch |err| {
        std.log.err("File '{s}' errored", .{file_name});
        return err;
    };
}

const std = @import("std");
const lib = @import("lib");
const testing = std.testing;
const fs = std.fs;
const utils = lib.utils;

const eqlString = testing.expectEqualStrings;
const expect = testing.expect;

const Dir = fs.Dir;
const File = fs.File;
const LuaParser = lib.LuaParser;
const Subs = lib.Substitution;
