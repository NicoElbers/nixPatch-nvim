pub fn parseFiles(alloc: Allocator, input_blob: []const u8, nixpkgs_files: []const File) ![]const Plugin {
    const user_plugins = try parseBlob(alloc, input_blob);

    for (nixpkgs_files) |file| {
        const file_buf = try utils.mmapFile(file, .{});
        defer utils.unMmapFile(file_buf);

        try findPluginUrl(
            alloc,
            file_buf,
            user_plugins,
        );
    }

    for (user_plugins) |plugin| {
        if (plugin.tag != .UrlNotFound) continue;

        std.log.warn("Did not find a url for {s}", .{plugin.pname});
    }

    // Error if any plugin names are not unique
    for (0..user_plugins.len) |needle_idx| {
        const needle_plugin = user_plugins[needle_idx];
        for (0..user_plugins.len) |haystack_idx| {
            if (needle_idx == haystack_idx) continue;
            const haystack_plugin = user_plugins[haystack_idx];

            if (std.mem.eql(u8, needle_plugin.pname, haystack_plugin.pname)) {
                @setCold(true);

                std.log.err(
                    "Found plugin '{s}' twice, cannot patch unambigiously. exiting",
                    .{needle_plugin.pname},
                );
                std.log.err("You may have the same plugin twice in your flake, this is disallowed", .{});
                std.process.exit(1);
            }
        }
    }

    return user_plugins;
}

fn parseBlob(alloc: Allocator, input_blob: []const u8) ![]Plugin {
    var plugins = std.ArrayList(Plugin).init(alloc);
    errdefer {
        for (plugins.items) |plugin| {
            plugin.deinit(alloc);
        }
        plugins.deinit();
    }

    // then the blob is empty
    if (input_blob.len < 3) {
        return plugins.toOwnedSlice();
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

fn findPluginUrl(alloc: Allocator, buf: []const u8, plugins: []Plugin) !void {
    const State = union(enum) {
        findPname,
        verifyVersion: *Plugin,
        getUrl: *Plugin,
        verifyUrl: *Plugin,
    };

    var state: State = .findPname;
    defer parseAssert(state == .findPname, "Parsing ended in an invalid state");

    var relevant_urls_found: u32 = 0;

    var line_spliterator = std.mem.splitSequence(u8, buf, "\n");
    outer: while (line_spliterator.next()) |line| {
        switch (state) {
            .findPname => {
                var split = splitOnEq(line);
                if (!eql("pname", trim(split.first())))
                    continue :outer;

                const pname = trim(split.next().?);

                inner: for (plugins) |*plugin| {
                    if (!eql(pname, plugin.pname))
                        continue :inner;

                    // We break because we already found the url, no need for double work
                    if (plugin.tag != .UrlNotFound) continue :outer;

                    state = .{ .verifyVersion = plugin };
                    continue :outer;
                }
            },

            .verifyVersion => |plugin| {
                var split = splitOnEq(line);
                const first = trim(split.first());

                parseAssert(!eql("pname", first), "Skipped to next plugin");
                if (!eql("version", first))
                    continue :outer;

                const version = trim(split.next().?);

                // https://github.com/NixOS/nixpkgs/blob/493f07fef3bdc5c7dc09f642ce12b7777d294a71/pkgs/applications/editors/neovim/build-neovim-plugin.nix#L36
                const nvimVersion = try std.fmt.allocPrint(alloc, "-unstable-{s}", .{version});
                defer alloc.free(nvimVersion);

                const nvimEql = std.mem.endsWith(u8, plugin.version, nvimVersion);
                const vimEql = eql(version, plugin.version);
                parseAssert(vimEql or nvimEql, "Version was not a known vim or nvim plugin version");

                state = .{ .getUrl = plugin };
            },

            .getUrl => |plugin| {
                var split = splitOnEq(line);
                const first = trim(split.first());

                parseAssert(!eql("pname", first), "Skipped to next plugin");
                if (!eql("src", first))
                    continue :outer;

                parseAssert(plugin.tag == .UrlNotFound, "Url already found");

                const fetch_method = trim(split.next().?);

                if (eql("fetchFromGitHub", fetch_method)) {
                    plugin.tag = .GithubUrl;

                    var ownerLine = splitOnEq(line_spliterator.next().?);
                    parseAssert(eql("owner", ownerLine.first()), "Github repo owner not found");
                    const owner = trim(ownerLine.next().?);

                    var repoLine = splitOnEq(line_spliterator.next().?);
                    parseAssert(eql("repo", repoLine.first()), "Github repo name not found");
                    const repo = trim(repoLine.next().?);

                    plugin.url = try std.fmt.allocPrint(
                        alloc,
                        "https://github.com/{s}/{s}",
                        .{ owner, repo },
                    );
                } else if (eql("fetchgit", fetch_method)) {
                    plugin.tag = .GitUrl;

                    var urlLine = splitOnEq(line_spliterator.next().?);
                    parseAssert(eql("url", utils.trim(urlLine.first())), "fetchgit URL not found");
                    const url = trim(urlLine.next().?);

                    plugin.url = try alloc.dupe(u8, trim(url));
                } else if (eql("fetchzip", fetch_method)) {
                    var urlLine = splitOnEq(line_spliterator.next().?);
                    parseAssert(eql("url", utils.trim(urlLine.first())), "fetchzip URL not found");
                    const url_with_zip = trim(urlLine.next().?);

                    if (mem.startsWith(u8, url_with_zip, "https://github.com/")) {
                        plugin.tag = .GithubUrl;
                        const last_idx = mem.lastIndexOfScalar(u8, url_with_zip, '/').?;
                        const second_last_idx = mem.lastIndexOfScalar(u8, url_with_zip[0..last_idx], '/').?;

                        plugin.url = try alloc.dupe(u8, trim(url_with_zip[0..second_last_idx]));
                    } else {
                        std.log.err(
                            \\Cannot properly parse url for '{s}'. Please parse the URL manually and add it to your patches
                            \\  '{s}'
                        ,
                            .{ plugin.pname, url_with_zip },
                        );
                        state = .findPname;
                        continue :outer;
                    }
                } else {
                    std.log.err("Found fetch method '{s}'", .{fetch_method});
                    unreachable;
                }

                state = .{ .verifyUrl = plugin };
            },

            .verifyUrl => |plugin| {
                var split = splitOnEq(line);
                const first = trim(split.first());

                parseAssert(!eql("pname", first), "Skipped to next plugin");
                if (!eql("meta.homepage", first) and !eql("meta", first))
                    continue :outer;

                const url = blk: {
                    if (eql("meta.homepage", first)) {
                        break :blk trim(split.next().?);
                    } else {
                        // TODO: This assumes that "homepage" will always be the
                        // next line, make it more robust
                        var homepage_split = splitOnEq(line_spliterator.next().?);
                        parseAssert(eql("homepage", homepage_split.first()), "Found neither meta.homepage or homepage");

                        break :blk trim(homepage_split.next().?);
                    }
                };

                parseAssert(eql(url, plugin.url), "git URL and homepage URL are not the same");

                relevant_urls_found += 1;
                state = .findPname;
            },
        }
    }

    std.log.debug("Found {d} relevant urls", .{relevant_urls_found});
}

fn parseAssert(ok: bool, assumption: []const u8) void {
    if (ok) return;

    std.log.err("Parsing failed: {s}", .{assumption});
    std.log.err("Please file a github issue :)", .{});
}

fn eqlPlugin(a: Plugin, b: Plugin) !void {
    try std.testing.expectEqualSlices(u8, a.pname, b.pname);
    try std.testing.expectEqualSlices(u8, a.version, b.version);
    try std.testing.expectEqualSlices(u8, a.path, b.path);
    try std.testing.expectEqual(a.tag, b.tag);

    if (a.tag == .UrlNotFound) return;

    try std.testing.expectEqualSlices(u8, a.url, b.url);
}

// ---- Tests ----

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

    var plugins = [_]Plugin{
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

    try findPluginUrl(
        alloc,
        input_buf,
        plugins[0..],
    );
    defer {
        for (plugins) |plugin| {
            alloc.free(plugin.url);
        }
    }

    try std.testing.expectEqual(plugins.len, 3);

    const expected: []const Plugin = &.{
        Plugin{
            .pname = "BetterLua.vim",
            .version = "2020-08-14",
            .path = "path",
            .tag = .GithubUrl,
            .url = "https://github.com/euclidianAce/BetterLua.vim",
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
            .url = "https://github.com/j-hui/fidget.nvim",
        },
    };

    for (0..3) |idx| {
        try eqlPlugin(plugins[idx], expected[idx]);
    }
}

// input parser utils
const mem = std.mem;

pub fn trim(input: []const u8) []const u8 {
    return mem.trim(u8, input, " /\\;{}\"\n");
}

fn splitOnEq(input: []const u8) mem.SplitIterator(u8, .sequence) {
    return mem.splitSequence(u8, input, "=");
}

fn eql(expected: []const u8, input: []const u8) bool {
    return mem.eql(u8, expected, trim(input));
}

const std = @import("std");
const root = @import("root.zig");
const fs = std.fs;
const utils = root.utils;
const assert = std.debug.assert;

const Allocator = std.mem.Allocator;
const File = std.fs.File;
const Plugin = root.Plugin;
