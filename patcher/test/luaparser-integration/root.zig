const std = @import("std");
const lib = @import("lib");
const fs = std.fs;
const tst = @import("../root.zig");

const Subs = lib.Substitution;
const alloc = tst.alloc;

test {
    var cwd = try fs.cwd().openDir(".", .{ .iterate = true });
    defer cwd.close();

    try cwd.deleteTree("patcher/test/luaparser-integration/out");
    defer cwd.deleteTree("patcher/test/luaparser-integration/out") catch unreachable;

    const subs = try makeSubs();
    defer Subs.deinitSubs(subs, alloc);

    const extra_init_config = "[[dont_replace_me]]";
    const path = "patcher/test/luaparser-integration";

    try tst.run(cwd, path, extra_init_config, subs);

    try tst.verify(cwd, path);
}

pub fn makeSubs() ![]const Subs {
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
