const std = @import("std");
const fs = std.fs;
const assert = std.debug.assert;
const utils = @import("../utils.zig");

const Allocator = std.mem.Allocator;
const File = std.fs.File;
const Plugin = utils.Plugin;

const Self = @This();

vim_plugin_file: File,
alloc: Allocator,

pub fn init(alloc: Allocator, vim_plugin_file: File) Self {
    return Self{
        .alloc = alloc,
        .vim_plugin_file = vim_plugin_file,
    };
}

pub fn deinit(self: *Self) void {
    self.vim_plugin_file.close();
}

pub fn parseInput(self: Self, input_blob: []const u8) ![]const Plugin {
    const half_plugins = try parseBlob(self.alloc, input_blob);

    const vim_plugin_buf = try utils.mmapFile(self.vim_plugin_file, .{});
    defer utils.unMmapFile(vim_plugin_buf);

    const final_plugins = try findPluginUrl(
        self.alloc,
        vim_plugin_buf,
        half_plugins,
    );
    return final_plugins;
}

fn parseBlob(alloc: Allocator, input_blob: []const u8) ![]Plugin {
    var plugins = std.ArrayList(Plugin).init(alloc);
    errdefer {
        for (plugins.items) |plugin| {
            plugin.deinit(alloc);
        }
        plugins.deinit();
    }

    var blob_spliterator = std.mem.splitSequence(u8, input_blob, ";");
    while (blob_spliterator.next()) |plugin_str| {
        var plugin_spliterator = std.mem.splitSequence(u8, plugin_str, "|");

        const pname = plugin_spliterator.next().?;
        const version = plugin_spliterator.next().?;
        const path = plugin_spliterator.next().?;

        // Assert the spliterator is now empty
        assert(plugin_spliterator.next() == null);

        try plugins.append(.{
            .pname = try alloc.dupe(u8, pname),
            .version = try alloc.dupe(u8, version),
            .path = try alloc.dupe(u8, path),
            .tag = .UrlNotFound,
            .url = undefined,
        });
    }

    std.log.debug("Found {d} plugins", .{plugins.items.len});
    return try plugins.toOwnedSlice();
}

fn findPluginUrl(alloc: Allocator, vim_plugin_buf: []const u8, plugins: []Plugin) ![]Plugin {
    const State = union(enum) {
        findPname,
        verifyVersion: *Plugin,
        getUrl: *Plugin,
        verifyUrl: *Plugin,
    };
    var state: State = .findPname;

    var relevant_urls_found: u32 = 0;

    var line_spliterator = std.mem.splitSequence(u8, vim_plugin_buf, "\n");
    outer: while (line_spliterator.next()) |line| {
        switch (state) {
            .findPname => {
                var split = utils.split(line);
                if (!utils.eql("pname", utils.trim(split.first())))
                    continue :outer;

                const pname = utils.trim(split.next().?);

                inner: for (plugins) |*plugin| {
                    if (!utils.eql(pname, plugin.pname))
                        continue :inner;

                    state = .{ .verifyVersion = plugin };
                    continue :outer;
                }
            },

            .verifyVersion => |plugin| {
                var split = utils.split(line);
                const first = utils.trim(split.first());

                assert(!utils.eql("pname", first));
                if (!utils.eql("version", first))
                    continue :outer;

                const version = utils.trim(split.next().?);

                // https://github.com/NixOS/nixpkgs/blob/493f07fef3bdc5c7dc09f642ce12b7777d294a71/pkgs/applications/editors/neovim/build-neovim-plugin.nix#L36
                const nvimVersion = try std.fmt.allocPrint(alloc, "-unstable-{s}", .{version});
                defer alloc.free(nvimVersion);

                const nvimEql = std.mem.endsWith(u8, plugin.version, nvimVersion);
                const vimEql = utils.eql(version, plugin.version);
                assert(vimEql or nvimEql);

                state = .{ .getUrl = plugin };
            },

            .getUrl => |plugin| {
                var split = utils.split(line);
                const first = utils.trim(split.first());

                assert(!utils.eql("pname", first));
                if (!utils.eql("src", first))
                    continue :outer;

                assert(plugin.tag == .UrlNotFound);

                const fetch_method = utils.trim(split.next().?);

                if (utils.eql("fetchFromGitHub", fetch_method)) {
                    plugin.tag = .GithubUrl;

                    var ownerLine = utils.split(line_spliterator.next().?);
                    assert(utils.eql("owner", ownerLine.first()));
                    const owner = utils.trim(ownerLine.next().?);

                    var repoLine = utils.split(line_spliterator.next().?);
                    assert(utils.eql("repo", repoLine.first()));
                    const repo = utils.trim(repoLine.next().?);

                    plugin.url = try std.fmt.allocPrint(
                        alloc,
                        "https://github.com/{s}/{s}/",
                        .{ owner, repo },
                    );
                } else if (utils.eql("fetchgit", fetch_method)) {
                    plugin.tag = .GitUrl;

                    var urlLine = utils.split(line_spliterator.next().?);
                    assert(utils.eql("url", urlLine.first()));
                    const url = utils.trim(urlLine.next().?);

                    plugin.url = try alloc.dupe(u8, url);
                } else unreachable;

                state = .{ .verifyUrl = plugin };
            },

            .verifyUrl => |plugin| {
                var split = utils.split(line);
                const first = utils.trim(split.first());

                assert(!utils.eql("pname", first));
                if (!utils.eql("meta.homepage", first))
                    continue :outer;

                const url = utils.trim(split.next().?);
                assert(utils.eql(url, plugin.url));

                relevant_urls_found += 1;
                state = .findPname;
            },
        }
    }

    std.log.debug("Found {d} relevant urls", .{relevant_urls_found});
    // FIXME: check if this could be valid behavior
    for (plugins) |plugin| {
        assert(plugin.tag != .UrlNotFound);
    }

    // We didn't end in the middle of looking something up
    assert(state == .findPname);
    return plugins;
}

// ---- Tests ----

fn eqlPlugin(a: Plugin, b: Plugin) !void {
    try std.testing.expectEqualSlices(u8, a.pname, b.pname);
    try std.testing.expectEqualSlices(u8, a.version, b.version);
    try std.testing.expectEqualSlices(u8, a.path, b.path);
    try std.testing.expectEqual(a.tag, b.tag);

    if (a.tag == .UrlNotFound) return;

    try std.testing.expectEqualSlices(u8, a.url, b.url);
}

test parseBlob {
    const alloc = std.testing.allocator;

    const input = "name|version|path;name2|version2|path2;name3|version3|path3";
    const output = try parseBlob(alloc, input);
    defer {
        for (output) |plugin| {
            plugin.deinit(alloc);
        }
        alloc.free(output);
    }

    const expected: []const Plugin = &.{
        Plugin{
            .pname = "name",
            .version = "version",
            .path = "path",
            .tag = .UrlNotFound,
            .url = undefined,
        },
        Plugin{
            .pname = "name2",
            .version = "version2",
            .path = "path2",
            .tag = .UrlNotFound,
            .url = undefined,
        },
        Plugin{
            .pname = "name3",
            .version = "version3",
            .path = "path3",
            .tag = .UrlNotFound,
            .url = undefined,
        },
    };

    for (0..3) |idx| {
        try eqlPlugin(output[idx], expected[idx]);
    }
}

test findPluginUrl {
    const alloc = std.testing.allocator;

    const input_buf =
        \\# GENERATED by ./pkgs/applications/editors/vim/plugins/update.py. Do not edit!
        \\{ lib, buildVimPlugin, buildNeovimPlugin, fetchFromGitHub, fetchgit }:
        \\
        \\final: prev:
        \\{
        \\  // Parse this one normally
        \\  BetterLua-vim = buildVimPlugin {
        \\    pname = "BetterLua.vim";
        \\    version = "2020-08-14";
        \\    src = fetchFromGitHub {
        \\      owner = "euclidianAce";
        \\      repo = "BetterLua.vim";
        \\      rev = "d2d6c115575d09258a794a6f20ac60233eee59d5";
        \\      sha256 = "1rvlx21kw8865dg6q97hx9i2s1n8mn1nyhn0m7dkx625pghsx3js";
        \\    };
        \\    meta.homepage = "https://github.com/euclidianAce/BetterLua.vim/";
        \\  };
        \\
        \\  // Ignore this one
        \\  BufOnly-vim = buildVimPlugin {
        \\    pname = "BufOnly.vim";
        \\    version = "2010-10-18";
        \\    src = fetchFromGitHub {
        \\      owner = "vim-scripts";
        \\      repo = "BufOnly.vim";
        \\      rev = "43dd92303979bdb234a3cb2f5662847f7a3affe7";
        \\      sha256 = "1gvpaqvvxjma0dl1zai68bpv42608api4054appwkw9pgczkkcdl";
        \\    };
        \\    meta.homepage = "https://github.com/vim-scripts/BufOnly.vim/";
        \\  };
        \\
        \\  // Garbage for fun
        \\  src = "fdafasdf";
        \\  version = "adfasdf";
        \\
        \\  // NeovimPlugin
        \\  fidget-nvim = buildNeovimPlugin {
        \\    pname = "fidget.nvim";
        \\    version = "2024-05-19";
        \\    src = fetchFromGitHub {
        \\      owner = "j-hui";
        \\      repo = "fidget.nvim";
        \\      rev = "ef99df04a1c53a453602421bc0f756997edc8289";
        \\      sha256 = "1j0s31k8dszb0sq46c492hj27w0ag2zmxy75y8204f3j80dkz68s";
        \\    };
        \\    meta.homepage = "https://github.com/j-hui/fidget.nvim/";
        \\  };
        \\
        \\  // Fetchgit plugin
        \\  hare-vim = buildVimPlugin {
        \\    pname = "hare.vim";
        \\    version = "2024-05-24";
        \\    src = fetchgit {
        \\      url = "https://git.sr.ht/~sircmpwn/hare.vim";
        \\      rev = "e0d38c0563224aa7b0101f64640788691f6c15b9";
        \\      sha256 = "1csc5923acy7awgix0qfkal39v4shzw5vyvw56vkmazvc8n8rqs6";
        \\    };
        \\    meta.homepage = "https://git.sr.ht/~sircmpwn/hare.vim";
        \\  };
    ;

    var input_plugins = [_]Plugin{
        Plugin{
            .pname = "BetterLua.vim",
            .version = "2020-08-14",
            .path = "path",
            .tag = .UrlNotFound,
            .url = undefined,
        },
        Plugin{
            .pname = "hare.vim",
            .version = "2024-05-24",
            .path = "path2",
            .tag = .UrlNotFound,
            .url = undefined,
        },
        Plugin{
            .pname = "fidget.nvim",
            .version = "2024-05-19",
            .path = "path3",
            .tag = .UrlNotFound,
            .url = undefined,
        },
    };

    const output = try findPluginUrl(
        alloc,
        input_buf,
        input_plugins[0..],
    );
    defer {
        for (output) |plugin| {
            alloc.free(plugin.url);
        }
    }

    try std.testing.expectEqual(output.len, 3);

    const expected: []const Plugin = &.{
        Plugin{
            .pname = "BetterLua.vim",
            .version = "2020-08-14",
            .path = "path",
            .tag = .GithubUrl,
            .url = "https://github.com/euclidianAce/BetterLua.vim/",
        },
        Plugin{
            .pname = "hare.vim",
            .version = "2024-05-24",
            .path = "path2",
            .tag = .GitUrl,
            .url = "https://git.sr.ht/~sircmpwn/hare.vim",
        },
        Plugin{
            .pname = "fidget.nvim",
            .version = "2024-05-19",
            .path = "path3",
            .tag = .GithubUrl,
            .url = "https://github.com/j-hui/fidget.nvim/",
        },
    };

    for (0..3) |idx| {
        try eqlPlugin(output[idx], expected[idx]);
    }
}
