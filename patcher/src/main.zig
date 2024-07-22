// FIXME: Think about the case where a user adds their own plugin to nixpkgs
const std = @import("std");
const fs = std.fs;
const assert = std.debug.assert;
const util = @import("utils.zig");

const InputParser = @import("parsers/InputParser.zig");
const LuaParser = @import("parsers/LuaParser.zig");
const Plugin = util.Plugin;
const Substitution = util.Substitution;

const Allocator = std.mem.Allocator;

pub fn main() !void {
    // var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    // defer arena.deinit();

    // const alloc = arena.allocator();

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
            \\    Substitutions in the format `from|to;`
            \\    Extra Lua config put at the top of init.lua
        ,
            .{args.len},
        );
        return error.NotEnoughArguments;
    }

    const nixpkgs_path = args[1];
    const in_path = args[2];
    const out_path = args[3];
    const input_blob = args[4];
    const extra_subs: []const u8 = if (args.len > 5) args[5] else "";
    const extra_config: []const u8 = if (args.len > 6) args[6] else "";

    assert(std.fs.path.isAbsolute(nixpkgs_path));
    assert(std.fs.path.isAbsolute(in_path));
    assert(std.fs.path.isAbsolute(out_path));

    const plugins = try getPlugins(alloc, nixpkgs_path, input_blob);
    defer {
        for (plugins) |plugin| {
            plugin.deinit(alloc);
        }
        alloc.free(plugins);
    }

    // Extra subs
    // TODO: Very ugly, pls fix
    var extra_sub_arr = try getSubs(alloc, extra_subs);

    // Create config
    var lua_parser = try LuaParser.init(
        alloc,
        in_path,
        out_path,
        extra_config,
    );
    defer lua_parser.deinit();

    try lua_parser.createConfig(plugins, &extra_sub_arr);
}

fn getPlugins(alloc: Allocator, nixpkgs_path: []const u8, input_blob: []const u8) ![]const Plugin {
    // Get the plugin file
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

    std.log.debug("Attempting to open file '{s}'", .{full_path});
    const vim_plugins_file = try fs.openFileAbsolute(full_path, .{});

    // Get plugins
    var input_parser = InputParser.init(alloc, vim_plugins_file);
    defer input_parser.deinit();

    return try input_parser.parseInput(input_blob);
}

fn getSubs(alloc: Allocator, extra_subs: []const u8) !std.ArrayList(Substitution) {
    var iter = util.BufIter{ .buf = extra_subs };
    var sub_arr = std.ArrayList(Substitution).init(alloc);
    errdefer sub_arr.deinit();

    while (!iter.isDone()) {
        const from = iter.nextUntilExcluding("|").?;
        const to = iter.nextUntilExcluding(";") orelse iter.rest() orelse return error.BadSub;
        try sub_arr.append(Substitution{
            .from = try alloc.dupe(u8, from),
            .to = try alloc.dupe(u8, to),
        });
    }
    return sub_arr;
}

test {
    _ = @import("parsers/InputParser.zig");
    _ = @import("parsers/LuaParser.zig");
    _ = @import("utils.zig");
}
