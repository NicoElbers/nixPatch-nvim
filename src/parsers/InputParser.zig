const std = @import("std");
const fs = std.fs;
const assert = std.debug.assert;
const utils = @import("../utils.zig");

const Allocator = std.mem.Allocator;
const File = std.fs.File;

const Self = @This();

generated_vim_plugin_file: File,
alloc: Allocator,

const Plugin = struct {
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

pub fn init(alloc: Allocator, nixpkgs_path: []const u8) !Self {
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
    };
}

pub fn deinit(self: *Self) void {
    self.generated_vim_plugin_file.close();
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
    const file_buf = try utils.mmapFile(self.generated_vim_plugin_file, .{});
    defer utils.unMmapFile(file_buf);

    var relevant_urls_found: u32 = 0;

    const State = union(enum) {
        findPname,
        verifyVersion: *Plugin,
        getUrl: *Plugin,
        verifyUrl: *Plugin,
    };
    var state: State = .findPname;

    var line_spliterator = std.mem.splitSequence(u8, file_buf, "\n");
    outer: while (line_spliterator.next()) |line| {
        switch (state) {
            .findPname => {
                var split = utils.split(line);
                if (!utils.eql("pname", split.first()))
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
                const first = split.first();

                assert(!utils.eql("pname", first));
                if (!utils.eql("version", first))
                    continue :outer;

                const version = utils.trim(split.next().?);

                // TODO: Is this always true?
                assert(utils.eql(version, plugin.version));

                state = .{ .getUrl = plugin };
            },

            .getUrl => |plugin| {
                var split = utils.split(line);
                const first = split.first();

                assert(!utils.eql("pname", first));
                if (!utils.eql("src", first))
                    continue :outer;

                assert(plugin.tag == .UrlNotFound);

                const fetch_method = utils.trim(split.next().?);

                if (utils.eql("fetchFromGitHub", fetch_method)) {
                    plugin.tag = .GithubUrl;

                    var ownerLine = utils.split(line_spliterator.next().?);
                    assert(utils.eql("owner", ownerLine.first()));
                    const owner = ownerLine.next().?;

                    var repoLine = utils.split(line_spliterator.next().?);
                    assert(utils.eql("repo", repoLine.first()));
                    const repo = repoLine.next().?;

                    plugin.url = try std.fmt.allocPrint(
                        self.alloc,
                        "https://github.com/{s}/{s}/",
                        .{ owner, repo },
                    );
                } else if (utils.eql("fetchgit", fetch_method)) {
                    plugin.tag = .GitUrl;

                    var urlLine = utils.split(line_spliterator.next().?);
                    assert(utils.eql("url", urlLine.first()));
                    const url = urlLine.next().?;

                    plugin.url = try self.alloc.dupe(u8, url);
                } else unreachable;

                state = .{ .verifyUrl = plugin };
            },

            .verifyUrl => |plugin| {
                var split = utils.split(line);
                const first = split.first();

                assert(!utils.eql("pname", first));
                if (!utils.eql("meta.homepage", first))
                    continue :outer;

                const url = split.next().?;
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
