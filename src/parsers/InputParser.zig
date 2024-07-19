const std = @import("std");
const fs = std.fs;
const assert = std.debug.assert;
const utils = @import("../utils.zig");

const Allocator = std.mem.Allocator;
const File = std.fs.File;
const Plugin = utils.Plugin;

const Self = @This();

vim_plugin_buf: []const u8,
alloc: Allocator,

pub fn init(alloc: Allocator, vim_plugin_buf: []const u8) Self {
    return Self{
        .alloc = alloc,
        .vim_plugin_buf = vim_plugin_buf,
    };
}

pub fn deinit(self: *Self) void {
    _ = self;
}

pub fn parseInput(self: Self, input_blob: []const u8) ![]const Plugin {
    var plugins = std.ArrayList(Plugin).init(self.alloc);
    errdefer {
        for (plugins.items) |plugin| {
            plugin.deinit(self.alloc);
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
            .pname = try self.alloc.dupe(u8, pname),
            .version = try self.alloc.dupe(u8, version),
            .path = try self.alloc.dupe(u8, path),
            .tag = .UrlNotFound,
            .url = undefined,
        });
    }

    std.log.debug("Found {d} plugins", .{plugins.items.len});
    return try findPluginUrl(self, try plugins.toOwnedSlice());
}

fn findPluginUrl(self: Self, plugins: []Plugin) ![]Plugin {
    const State = union(enum) {
        findPname,
        verifyVersion: *Plugin,
        getUrl: *Plugin,
        verifyUrl: *Plugin,
    };
    var state: State = .findPname;

    var relevant_urls_found: u32 = 0;

    var line_spliterator = std.mem.splitSequence(u8, self.vim_plugin_buf, "\n");
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
                const nvimVersion = try std.fmt.allocPrint(self.alloc, "-unstable-{s}", .{version});
                defer self.alloc.free(nvimVersion);

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
                        self.alloc,
                        "https://github.com/{s}/{s}/",
                        .{ owner, repo },
                    );
                } else if (utils.eql("fetchgit", fetch_method)) {
                    plugin.tag = .GitUrl;

                    var urlLine = utils.split(line_spliterator.next().?);
                    assert(utils.eql("url", urlLine.first()));
                    const url = utils.trim(urlLine.next().?);

                    plugin.url = try self.alloc.dupe(u8, url);
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
