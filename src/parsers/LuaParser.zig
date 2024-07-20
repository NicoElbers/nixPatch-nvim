const std = @import("std");
const fs = std.fs;
const assert = std.debug.assert;
const utils = @import("../utils.zig");

const Allocator = std.mem.Allocator;
const File = fs.File;
const Dir = fs.Dir;
const Plugin = utils.Plugin;
const Substitution = utils.Substitution;

const Self = @This();

alloc: Allocator,
in_dir: Dir,
out_dir: Dir,

// TODO: Change paths to dirs
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

fn createSubsitutions(alloc: Allocator, plugins: []const Plugin) ![]Substitution {
    var subs = std.ArrayList(Substitution).init(alloc);

    for (plugins) |plugin| {
        switch (plugin.tag) {
            .UrlNotFound => continue,
            .GitUrl => {
                try subs.append(Substitution{
                    .tag = .url,
                    .from = plugin.url,
                    .to = plugin.path,
                });
            },
            .GithubUrl => {
                try subs.append(Substitution{
                    .tag = .url,
                    .from = plugin.url,
                    .to = plugin.path,
                });

                var url_splitter = std.mem.splitSequence(u8, plugin.url, "://github.com/");
                _ = url_splitter.next().?;
                const short_url = url_splitter.rest();

                try subs.append(Substitution{
                    .tag = .githubShort,
                    .from = short_url,
                    .to = plugin.path,
                });
            },
        }
    }

    return try subs.toOwnedSlice();
}

