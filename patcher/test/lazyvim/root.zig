const std = @import("std");
const lib = @import("lib");
const fs = std.fs;
const tst = @import("../root.zig");

const Subs = lib.Substitution;
const alloc = tst.alloc;

test {
    var cwd = try fs.cwd().openDir(".", .{ .iterate = true });
    defer cwd.close();

    try cwd.deleteTree("patcher/test/lazyvim/out");
    defer cwd.deleteTree("patcher/test/lazyvim/out") catch unreachable;

    const subs = try makeSubs();
    defer Subs.deinitSubs(subs, alloc);

    const extra_init_config = "-- start";
    const path = "patcher/test/lazyvim";

    try tst.run(cwd, path, extra_init_config, subs);

    try tst.verify(cwd, path);
}

pub fn makeSubs() ![]const Subs {
    var out = std.ArrayList(Subs).init(alloc);

    try out.append(try Subs.initUrlSub(alloc, "nvim-lualine/lualine.nvim", "LUALINE REPLACED", "lualine"));

    return out.toOwnedSlice();
}
