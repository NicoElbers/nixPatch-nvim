const std = @import("std");
const testing = std.testing;
const parsers = @import("parsers");
const fs = std.fs;
const utils = parsers.utils;

const eqlString = testing.expectEqualStrings;
const expect = testing.expect;

const Dir = fs.Dir;
const File = fs.File;
const LuaParser = parsers.LuaParser;
const Subs = utils.Substitution;

test {
    var cwd = try fs.cwd().openDir(".", .{ .iterate = true });
    defer cwd.close();

    try cwd.deleteTree("patcher/test/luaparser-integration/out");
    defer cwd.deleteTree("patcher/test/luaparser-integration/out") catch unreachable;

    const subs = try makeSubs();
    defer Subs.deinitSubs(subs, alloc);

    const extra_init_config = "[[dont_replace_me]]";

    try run(cwd, extra_init_config, subs);

    try verify(cwd);
}

fn makeSubs() ![]const Subs {
    var out = std.ArrayList(Subs).init(alloc);

    // Should not be replaced
    try out.append(try Subs.initStringSub(alloc, "dont_replace_me", "ERROR I WAS REPLACED", null));

    // String replacements
    try out.append(try Subs.initStringSub(alloc, "replace_me", "I_was_replaced", null));
    try out.append(try Subs.initStringSub(alloc, "replace_keyed", "I_was_key_replaced", "str"));

    // Url replacements
    try out.append(try Subs.initUrlSub(alloc, "plugin/url", "plugin/path", "plugin-name"));
    try out.append(try Subs.initUrlSub(alloc, "other/url", "other/path", "other-name"));
    try out.append(try Subs.initUrlSub(alloc, "third/url", "third/path", "third-name"));

    return out.toOwnedSlice();
}

const alloc = testing.allocator;

fn run(cwd: Dir, extra_init_config: []const u8, subs: []const Subs) !void {
    var in_dir = try cwd.openDir("patcher/test/luaparser-integration/input", .{ .iterate = true });
    defer in_dir.close();

    try cwd.makeDir("patcher/test/luaparser-integration/out");
    var out_dir = try cwd.openDir("patcher/test/luaparser-integration/out", .{ .iterate = true });
    defer out_dir.close();

    var parser = try LuaParser.init(alloc, in_dir, out_dir, extra_init_config);

    try parser.createConfig(subs);
}

fn verify(cwd: Dir) !void {
    var expected_dir = try cwd.openDir("patcher/test/luaparser-integration/expected", .{ .iterate = true });
    defer expected_dir.close();

    var expected_walk = try expected_dir.walk(alloc);
    defer expected_walk.deinit();

    var out_dir = try cwd.openDir("patcher/test/luaparser-integration/out", .{ .iterate = true });
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

fn eqlFile(expected_file: File, out_file: File, file_name: []const u8) !void {
    const expected_buf = try utils.mmapFile(expected_file, .{});
    defer utils.unMmapFile(expected_buf);

    const out_buf = try utils.mmapFile(out_file, .{});
    defer utils.unMmapFile(out_buf);

    eqlString(expected_buf, out_buf) catch |err| {
        std.log.err("File '{s}' errored", .{file_name});
        return err;
    };
}
