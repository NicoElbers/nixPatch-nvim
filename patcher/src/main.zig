// FIXME: Think about the case where a user adds their own plugin to nixpkgs
// TODO: Create an end to end test on a sample config
const std = @import("std");
const fs = std.fs;
const assert = std.debug.assert;
const util = @import("utils.zig");

const InputParser = @import("parsers/InputParser.zig");
const LuaParser = @import("parsers/LuaParser.zig");
const Plugin = util.Plugin;
const Substitution = util.Substitution;

// FIXME: Why is BufIter in parsers???
const BufIter = @import("parsers/BufIter.zig");

const Allocator = std.mem.Allocator;
const File = std.fs.File;

pub const log_level: std.log.Level = .info;

pub fn main() !void {
    const start_time = try std.time.Instant.now();
    defer {
        const end_time = std.time.Instant.now() catch unreachable;
        const elapsed = end_time.since(start_time);
        std.log.info("Patching took {d}ms", .{elapsed / std.time.ns_per_ms});
    }

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const alloc = gpa.allocator();

    const args = try std.process.argsAlloc(alloc);
    defer std.process.argsFree(alloc, args);

    if (args.len < 5) {
        std.log.err(
            \\Not enough arguments, expected 4 got {d}
            \\  Expected order:
            \\    path to nixpkgs
            \\    The path to read the config from
            \\    Path to put config
            \\    Plugins in the format `pname|version|path;pname|version|path;...`
            \\    Substitutions in the format `type|from|to|extra;`
            \\    Extra Lua config put at the top of init.lua
            \\ For more information read the readme (TODO: Make readme)
        ,
            .{args.len - 1},
        );
        return error.NotEnoughArguments;
    }

    const nixpkgs_path = args[1];
    const in_path = args[2];
    const out_path = args[3];
    const input_blob = args[4];
    const extra_subs: []const u8 = if (args.len > 5) args[5] else "-";
    const extra_config: []const u8 = if (args.len > 6) args[6] else "-";

    assert(std.fs.path.isAbsolute(nixpkgs_path));
    assert(std.fs.path.isAbsolute(in_path));
    assert(std.fs.path.isAbsolute(out_path));

    const plugins = try getPlugins(alloc, nixpkgs_path, input_blob);
    defer Plugin.deinitPlugins(plugins, alloc);

    const subs = try getSubs(alloc, plugins, extra_subs);
    defer Substitution.deinitSubs(subs, alloc);

    try patchConfig(alloc, subs, in_path, out_path, extra_config);
}

// TEST: Make an end to end test here!!
pub fn patchConfig(
    alloc: Allocator,
    subs: []const Substitution,
    in_path: []const u8,
    out_path: []const u8,
    extra_config: []const u8,
) !void {
    var lua_parser = try LuaParser.init(
        alloc,
        in_path,
        out_path,
        extra_config,
    );
    defer lua_parser.deinit();

    try lua_parser.createConfig(subs);
}

fn getPlugins(alloc: Allocator, nixpkgs_path: []const u8, input_blob: []const u8) ![]const Plugin {
    assert(fs.path.isAbsolute(nixpkgs_path));

    // Get the plugin file
    const vim_plugins_path = try fs.path.join(alloc, &.{
        nixpkgs_path,
        "pkgs",
        "applications",
        "editors",
        "vim",
        "plugins",
        "generated.nix",
    });
    defer alloc.free(vim_plugins_path);

    std.log.debug("Attempting to open file '{s}'", .{vim_plugins_path});
    const vim_plugins_file = try fs.openFileAbsolute(vim_plugins_path, .{});
    defer vim_plugins_file.close();
    //
    // Get the plugin file
    const lua_plugins_path = try fs.path.join(alloc, &.{
        nixpkgs_path,
        "pkgs",
        "development",
        "lua-modules",
        "generated-packages.nix",
    });
    defer alloc.free(lua_plugins_path);

    std.log.debug("Attempting to open file '{s}'", .{lua_plugins_path});
    const lua_plugins_file = try fs.openFileAbsolute(lua_plugins_path, .{});
    defer lua_plugins_file.close();

    const files: []const File = &.{ vim_plugins_file, lua_plugins_file };

    return try InputParser.parseInput(alloc, input_blob, files);
}

fn getSubs(alloc: Allocator, plugins: []const Plugin, extra_subs: []const u8) ![]const Substitution {
    // Most plugins are a github short and long url
    // extra subs is the amount of semicolons plus the final sub
    const estimated_cap = plugins.len * 2 + std.mem.count(u8, extra_subs, ";") + 1;
    var subs = try std.ArrayList(Substitution).initCapacity(alloc, estimated_cap);
    errdefer {
        for (subs.items) |sub| {
            sub.deinit(alloc);
        }
        subs.deinit();
    }

    try subsFromPlugins(alloc, plugins, &subs);
    try subsFromBlob(alloc, extra_subs, &subs);

    // pretty print all subs for debugging
    // for (subs) |sub| {
    //     std.debug.print("\n", .{});
    //     switch (sub.tag) {
    //         .url => |pname| {
    //             std.debug.print(
    //                 \\try Substitution.initUrlSub(
    //                 \\    alloc,
    //                 \\    "{s}",
    //                 \\    "{s}",
    //                 \\    "{s}",
    //                 \\),
    //             , .{ sub.from, sub.to, pname });
    //         },
    //         .string => |key| {
    //             std.debug.print(
    //                 \\try Substitution.initStringSub(
    //                 \\    alloc,
    //                 \\    "{s}",
    //                 \\    "{s}",
    //                 \\    key,
    //                 \\),
    //             , .{ sub.from, sub.to });
    //         },
    //     }
    // }

    return try subs.toOwnedSlice();
}

/// Memory owned by caller
fn subsFromBlob(alloc: Allocator, subs_blob: []const u8, out: *std.ArrayList(Substitution)) !void {
    var iter = BufIter.init(subs_blob);

    // If the blob is less than 3 characters, the blob must not contain any subs
    // as at least 3 seperator characters are required
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

test {
    _ = @import("parsers/InputParser.zig");
    _ = @import("parsers/LuaParser.zig");
    _ = @import("utils.zig");
    _ = @import("parsers/BufIter.zig");
}
