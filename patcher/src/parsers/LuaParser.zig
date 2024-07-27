const std = @import("std");
const fs = std.fs;
const assert = std.debug.assert;
const utils = @import("../utils.zig");

const Allocator = std.mem.Allocator;
const File = fs.File;
const Dir = fs.Dir;
const Plugin = utils.Plugin;
const Substitution = utils.Substitution;
const BufIter = @import("BufIter.zig");

const Self = @This();

alloc: Allocator,
in_dir: Dir,
out_dir: Dir,
extra_init_config: []const u8,

// TODO: Change paths to dirs
pub fn init(alloc: Allocator, in_path: []const u8, out_path: []const u8, extra_init_config: []const u8) !Self {
    assert(fs.path.isAbsolute(in_path));
    assert(fs.path.isAbsolute(out_path));

    std.log.debug("Attempting to open dir '{s}'", .{in_path});
    const in_dir = try fs.openDirAbsolute(in_path, .{ .iterate = true });

    std.log.debug("Attempting to create '{s}'", .{out_path});

    // Go on if the dir already exists
    fs.accessAbsolute(out_path, .{}) catch {
        try fs.makeDirAbsolute(out_path);
    };

    std.log.debug("Attempting to open '{s}'", .{out_path});
    const out_dir = try fs.openDirAbsolute(out_path, .{});

    return Self{
        .alloc = alloc,
        .in_dir = in_dir,
        .out_dir = out_dir,
        .extra_init_config = extra_init_config,
    };
}

pub fn deinit(self: *Self) void {
    self.in_dir.close();
    self.out_dir.close();
}

/// This function creates the lua config in the specificified location.
///
/// It extracts specific substitutions from the passed in plugins and then
/// iterates over the input directory recursively. It copies non lua files
/// directly and parses lua files for substitutions before copying the parsed
/// files over.
pub fn createConfig(self: Self, subs: []const Substitution) !void {
    // FIXME: Create a loop that asserts subs.from are all unique
    //  - What if we have a custom sub that overrides a patched sub?
    var walker = try self.in_dir.walk(self.alloc);
    defer walker.deinit();

    std.log.info("Starting directory walk", .{});
    while (try walker.next()) |entry| {
        switch (entry.kind) {
            .directory => {
                // Go on if the dir already exists
                self.out_dir.access(entry.path, .{}) catch {
                    try self.out_dir.makeDir(entry.path);
                };
            },
            .file => {
                if (std.mem.eql(u8, ".lua", std.fs.path.extension(entry.basename))) {
                    std.log.info("parsing '{s}'", .{entry.path});
                    const in_file = try self.in_dir.openFile(entry.path, .{});
                    const in_buf = try utils.mmapFile(in_file, .{});
                    defer utils.unMmapFile(in_buf);

                    const out_buf = try parseLuaFile(self.alloc, in_buf, subs);
                    defer self.alloc.free(out_buf);

                    const out_file = try self.out_dir.createFile(entry.path, .{});

                    if (std.mem.eql(u8, entry.path, "init.lua")) {
                        try out_file.writeAll(self.extra_init_config);
                    }

                    try out_file.writeAll(out_buf);
                } else {
                    std.log.info("copying '{s}'", .{entry.path});
                    try self.in_dir.copyFile(
                        entry.path,
                        self.out_dir,
                        entry.path,
                        .{},
                    );
                }
            },
            else => std.log.warn("Kind {}", .{entry.kind}),
        }
    }
}

/// Memory owned by out
fn subsFromBlob(alloc: Allocator, subs_blob: []const u8, out: *std.ArrayList(Substitution)) !void {
    var iter = BufIter.init(subs_blob);

    // TODO: Is this ok? Ask someone with more experience
    if (subs_blob.len < 3) {
        return;
    }
    while (!iter.isDone()) {
        const typ = iter.nextUntilBefore("|").?;
        _ = iter.next();
        const from = iter.nextUntilBefore("|").?;
        _ = iter.next();
        const to = iter.nextUntilBefore("|").?;
        _ = iter.next();
        const extra = iter.nextUntilBefore(";") orelse iter.rest() orelse return error.BadSub;
        _ = iter.next();

        if (std.mem.eql(u8, typ, "plugin")) {
            try out.append(try Substitution.initUrlSub(alloc, from, to, extra));
        } else if (std.mem.eql(u8, typ, "string")) {
            if (std.mem.eql(u8, extra, "-")) {
                try out.append(try Substitution.initStringSub(alloc, from, to, null));
            } else {
                try out.append(try Substitution.initStringSub(alloc, from, to, extra));
            }
        } else unreachable;
    }
}

/// Memory owned by caller
fn subsFromPlugins(alloc: Allocator, plugins: []const Plugin, out: *std.ArrayList(Substitution)) !void {
    for (plugins) |plugin| {
        switch (plugin.tag) {
            .UrlNotFound => continue,
            .GitUrl => {
                try out.append(try Substitution.initUrlSub(
                    alloc,
                    plugin.url,
                    plugin.path,
                    plugin.pname,
                ));
            },
            .GithubUrl => {
                try out.append(try Substitution.initUrlSub(
                    alloc,
                    plugin.url,
                    plugin.path,
                    plugin.pname,
                ));

                var url_splitter = std.mem.splitSequence(u8, plugin.url, "://github.com/");
                _ = url_splitter.next().?;
                const short_url = url_splitter.rest();

                try out.append(try Substitution.initUrlSub(
                    alloc,
                    short_url,
                    plugin.path,
                    plugin.pname,
                ));
            },
        }
    }
}

// Good example of url usage:
// https://sourcegraph.com/github.com/Amar1729/dotfiles/-/blob/dot_config/nvim/lua/plugins/treesitter.lua

/// Returns a _new_ buffer, owned by the caller
fn parseLuaFile(alloc: Allocator, input_buf: []const u8, subs: []const Substitution) ![]const u8 {
    var iter = BufIter.init(input_buf);

    // Tack on 10% file size, should remove any resizes unless you do something
    // stupid
    var out_arr = try std.ArrayList(u8).initCapacity(
        alloc,
        @intFromFloat(@as(f32, @floatFromInt(input_buf.len)) * 1.1),
    );

    while (!iter.isDone()) {
        var chosen_sub: ?Substitution = null;
        for (subs) |sub| {
            switch (sub.tag) {
                .string => {
                    const next_str = iter.peekNextLuaString() orelse continue;
                    if (!std.mem.eql(u8, sub.from, next_str)) continue;

                    chosen_sub = sub;
                },
                .url => {
                    const next_str = iter.peekNextLuaString() orelse continue;
                    if (!std.mem.eql(u8, sub.from, next_str)) continue;

                    chosen_sub = sub;
                },
                .raw => unreachable,
            }
        }

        if (chosen_sub) |sub| {
            std.log.debug("Sub '{s}' -> '{s}'\n", .{ sub.from, sub.to });

            switch (sub.tag) {
                .raw => {
                    const until_next_instance = iter.peekUntilBefore(sub.from) orelse unreachable;
                    try out_arr.appendSlice(until_next_instance);
                    try out_arr.appendSlice(sub.to);

                    _ = iter.nextUntilAfter(sub.from) orelse unreachable;
                },
                .string => |key| {
                    const until_next_string = blk: {
                        if (key) |k| {
                            break :blk iter.peekUntilNextLuaStringKey(k) orelse
                                iter.peekNextUntilLuaString() orelse unreachable;
                        } else {
                            break :blk iter.peekNextUntilLuaString() orelse unreachable;
                        }
                    };
                    try out_arr.appendSlice(until_next_string);
                    try out_arr.appendSlice("[["); // String opening
                    try out_arr.appendSlice(sub.to);
                    try out_arr.appendSlice("]]"); // String closing

                    _ = iter.nextUntilAfterLuaString() orelse unreachable;
                },
                .url => |pname| {
                    const before_string = iter.peekUntilNextLuaStringKey("url") orelse
                        iter.peekNextUntilLuaString() orelse unreachable;
                    try out_arr.appendSlice(before_string);
                    try out_arr.appendSlice("dir = "); // Tell lazy this is a dir
                    try out_arr.appendSlice("[["); // String opening
                    try out_arr.appendSlice(sub.to);
                    try out_arr.appendSlice("]]"); // String closing
                    try out_arr.appendSlice(", name = "); // expose the plugin name
                    try out_arr.appendSlice("[["); // String opening
                    try out_arr.appendSlice(pname);
                    try out_arr.appendSlice("]]"); // String closing

                    _ = iter.nextUntilAfterLuaString() orelse unreachable;
                },
            }
        } else {
            const str = iter.nextUntilAfterLuaString() orelse iter.rest() orelse "";
            try out_arr.appendSlice(str);
        }
    }
    std.log.debug("No more subs in this file...", .{});

    return out_arr.toOwnedSlice();
}

// TODO: Make a test folder for this shit
test "parseLuaFile copy" {
    const alloc = std.testing.allocator;
    const input_buf = "Hello world";
    const expected = "Hello world";

    const subs: []const Substitution = &.{
        try Substitution.initStringSub(alloc, "asdf", "fdsa", null),
    };
    defer {
        for (subs) |sub| {
            sub.deinit(alloc);
        }
    }

    const out_buf = try parseLuaFile(alloc, input_buf, subs);
    defer alloc.free(out_buf);

    try std.testing.expectEqualStrings(expected, out_buf);
}

test "parseLuaFile simple sub" {
    const alloc = std.testing.allocator;
    const input_buf = "'Hello' world";
    const expected = "[[hi]] world";

    const subs: []const Substitution = &.{
        try Substitution.initStringSub(alloc, "Hello", "hi", null),
    };
    defer {
        for (subs) |sub| {
            sub.deinit(alloc);
        }
    }

    const out_buf = try parseLuaFile(alloc, input_buf, subs);
    defer alloc.free(out_buf);

    try std.testing.expectEqualStrings(expected, out_buf);
}

test "parseLuaFile multiple subs" {
    const alloc = std.testing.allocator;
    const input_buf = "'Hello' 'world'";
    const expected = "[[world]] [[Hello]]";

    const subs: []const Substitution = &.{
        try Substitution.initStringSub(alloc, "Hello", "world", null),
        try Substitution.initStringSub(alloc, "world", "Hello", null),
    };
    defer {
        for (subs) |sub| {
            sub.deinit(alloc);
        }
    }

    const out_buf = try parseLuaFile(alloc, input_buf, subs);
    defer alloc.free(out_buf);

    try std.testing.expectEqualStrings(expected, out_buf);
}

test "appendFromBlob empty" {
    const alloc = std.testing.allocator;
    var out_arr = std.ArrayList(Substitution).init(alloc);

    const in = "-";

    try subsFromBlob(alloc, in, &out_arr);

    try std.testing.expectEqual(0, out_arr.items.len);
}

test "appendFromBlob normal" {
    const alloc = std.testing.allocator;
    var out_arr = std.ArrayList(Substitution).init(alloc);
    defer {
        for (out_arr.items) |sub| {
            sub.deinit(alloc);
        }
        out_arr.deinit();
    }

    const in = "plugin|from|to|pname;string|from2|to2|key;";

    try subsFromBlob(alloc, in, &out_arr);

    try std.testing.expectEqual(2, out_arr.items.len);

    try std.testing.expectEqualStrings("pname", out_arr.items[0].tag.url);
    try std.testing.expectEqualStrings("from", out_arr.items[0].from);
    try std.testing.expectEqualStrings("to", out_arr.items[0].to);

    try std.testing.expectEqualStrings("key", out_arr.items[1].tag.string.?);
    try std.testing.expectEqualStrings("from2", out_arr.items[1].from);
    try std.testing.expectEqualStrings("to2", out_arr.items[1].to);
}

test "test plugin double quote" {
    const alloc = std.testing.allocator;
    const input_buf =
        \\"short/url"
    ;
    const expected =
        \\dir = [[local/path]], name = [[pname]]
    ;

    const subs: []const Substitution = &.{
        try Substitution.initUrlSub(
            alloc,
            "short/url",
            "local/path",
            "pname",
        ),
    };
    defer {
        for (subs) |sub| {
            sub.deinit(alloc);
        }
    }

    const out_buf = try parseLuaFile(alloc, input_buf, subs);
    defer alloc.free(out_buf);

    try std.testing.expectEqualStrings(expected, out_buf);
}

test "test plugin single quote" {
    const alloc = std.testing.allocator;
    const input_buf =
        \\'short/url'
    ;
    const expected =
        \\dir = [[local/path]], name = [[pname]]
    ;

    const subs: []const Substitution = &.{
        try Substitution.initUrlSub(
            alloc,
            "short/url",
            "local/path",
            "pname",
        ),
    };
    defer {
        for (subs) |sub| {
            sub.deinit(alloc);
        }
    }

    const out_buf = try parseLuaFile(alloc, input_buf, subs);
    defer alloc.free(out_buf);

    try std.testing.expectEqualStrings(expected, out_buf);
}

test "test plugin multi line" {
    const alloc = std.testing.allocator;
    const input_buf =
        \\[[short/url]]
    ;
    const expected =
        \\dir = [[local/path]], name = [[pname]]
    ;

    const subs: []const Substitution = &.{
        try Substitution.initUrlSub(
            alloc,
            "short/url",
            "local/path",
            "pname",
        ),
    };
    defer {
        for (subs) |sub| {
            sub.deinit(alloc);
        }
    }

    const out_buf = try parseLuaFile(alloc, input_buf, subs);
    defer alloc.free(out_buf);

    try std.testing.expectEqualStrings(expected, out_buf);
}

test "test plugin url" {
    const alloc = std.testing.allocator;
    const input_buf =
        \\url =[[short/url]]
    ;
    const expected =
        \\dir = [[local/path]], name = [[pname]]
    ;

    const subs: []const Substitution = &.{
        try Substitution.initUrlSub(
            alloc,
            "short/url",
            "local/path",
            "pname",
        ),
    };
    defer {
        for (subs) |sub| {
            sub.deinit(alloc);
        }
    }

    const out_buf = try parseLuaFile(alloc, input_buf, subs);
    defer alloc.free(out_buf);

    try std.testing.expectEqualStrings(expected, out_buf);
}

test "Markdown failing in config" {
    const alloc = std.testing.allocator;
    const in =
        \\local utils = require("utils")
        \\
        \\return {
        \\    {
        \\        "iamcco/markdown-preview.nvim",
        \\        cmd = { "MarkdownPreviewToggle", "MarkdownPreview", "MarkdownPreviewStop" },
        \\        ft = { "markdown" },
        \\        build = utils.set(function()
        \\            vim.fn["mkdp#util#install"]()
        \\        end),
        \\    },
        \\}
    ;

    const expected =
        \\local utils = require("utils")
        \\
        \\return {
        \\    {
        \\        dir = [[/nix/store/7zf18anjyk8k57knlfpx0gg6ji03scq0-vimplugin-markdown-preview.nvim-2023-10-17]], name = [[markdown-preview]],
        \\        cmd = { "MarkdownPreviewToggle", "MarkdownPreview", "MarkdownPreviewStop" },
        \\        ft = { "markdown" },
        \\        build = utils.set(function()
        \\            vim.fn["mkdp#util#install"]()
        \\        end),
        \\    },
        \\}
    ;

    const subs: []const Substitution = &.{
        try Substitution.initUrlSub(
            alloc,
            "iamcco/markdown-preview.nvim",
            "/nix/store/7zf18anjyk8k57knlfpx0gg6ji03scq0-vimplugin-markdown-preview.nvim-2023-10-17",
            "markdown-preview",
        ),
    };
    defer {
        for (subs) |sub| {
            sub.deinit(alloc);
        }
    }

    const out_buf = try parseLuaFile(alloc, in, subs);
    defer alloc.free(out_buf);

    try std.testing.expectEqualStrings(expected, out_buf);
}

test "cmp_luasnip failing in config" {
    const alloc = std.testing.allocator;
    const in =
        \\"luasnip"
        \\"saadparwaiz1/cmp_luasnip",
        \\"L3MON4D3/LuaSnip",
    ;

    const expected =
        \\"luasnip"
        \\dir = [[/nix/store/g60hd3lbr3vj0vzdz1q2rjjvn38l6s09-vimplugin-cmp_luasnip-2023-10-09]], name = [[cmp_luasnip]],
        \\dir = [[/nix/store/ma7l3pplq1v4kpw6myg3i4b59dfls8lz-vimplugin-lua5.1-luasnip-2.3.0-1-unstable-2024-06-28]], name = [[luasnip]],
    ;

    const subs: []const Substitution = &.{
        try Substitution.initUrlSub(
            alloc,
            "L3MON4D3/LuaSnip",
            "/nix/store/ma7l3pplq1v4kpw6myg3i4b59dfls8lz-vimplugin-lua5.1-luasnip-2.3.0-1-unstable-2024-06-28",
            "luasnip",
        ),

        try Substitution.initUrlSub(
            alloc,
            "saadparwaiz1/cmp_luasnip",
            "/nix/store/g60hd3lbr3vj0vzdz1q2rjjvn38l6s09-vimplugin-cmp_luasnip-2023-10-09",
            "cmp_luasnip",
        ),
    };
    defer {
        for (subs) |sub| {
            sub.deinit(alloc);
        }
    }

    const out_buf = try parseLuaFile(alloc, in, subs);
    defer alloc.free(out_buf);

    try std.testing.expectEqualStrings(expected, out_buf);
}

test "cmp-nvim-lsp failing in config" {
    const alloc = std.testing.allocator;
    const in =
        \\"luasnip"
        \\"hrsh7th/cmp-nvim-lsp",
        \\"L3MON4D3/LuaSnip",
    ;

    const expected =
        \\"luasnip"
        \\dir = [[/nix/store/a876kd0xckljpb8j45wwby3fdrqk14aj-vimplugin-cmp-nvim-lsp-2024-05-17]], name = [[cmp-nvim-lsp]],
        \\dir = [[/nix/store/ma7l3pplq1v4kpw6myg3i4b59dfls8lz-vimplugin-lua5.1-luasnip-2.3.0-1-unstable-2024-06-28]], name = [[luasnip]],
    ;

    const subs: []const Substitution = &.{
        try Substitution.initUrlSub(
            alloc,
            "L3MON4D3/LuaSnip",
            "/nix/store/ma7l3pplq1v4kpw6myg3i4b59dfls8lz-vimplugin-lua5.1-luasnip-2.3.0-1-unstable-2024-06-28",
            "luasnip",
        ),

        try Substitution.initUrlSub(
            alloc,
            "hrsh7th/cmp-nvim-lsp",
            "/nix/store/a876kd0xckljpb8j45wwby3fdrqk14aj-vimplugin-cmp-nvim-lsp-2024-05-17",
            "cmp-nvim-lsp",
        ),
    };
    defer {
        for (subs) |sub| {
            sub.deinit(alloc);
        }
    }

    const out_buf = try parseLuaFile(alloc, in, subs);
    defer alloc.free(out_buf);

    try std.testing.expectEqualStrings(expected, out_buf);
}
