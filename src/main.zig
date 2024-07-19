// FIXME: Think about the case where a user adds their own plugin to nixpkgs
const std = @import("std");
const fs = std.fs;
const assert = std.debug.assert;
const util = @import("utils.zig");

const InputParser = @import("parsers/InputParser.zig");
const LuaParser = @import("parsers/LuaParser.zig");
const Plugin = util.Plugin;

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
            \\    path to put config
            \\    plugins in the format `pname|version|path;pname|version|path;...`
            \\    All additional arguments will be put at the start of init.lua
        ,
            .{args.len},
        );
        return error.NotEnoughArguments;
    }

    const nixpkgs_path = args[1];
    const in_path = args[2];
    const out_path = args[3];
    const input_blob = args[4];
    const extra_args: ?[]const []const u8 = if (args.len > 5) args[5..] else null;
    _ = extra_args;

    const plugins = try getPlugins(alloc, nixpkgs_path, input_blob);
    defer {
        for (plugins) |plugin| {
            plugin.deinit(alloc);
        }
        alloc.free(plugins);
    }

    // Create config
    var lua_parser = try LuaParser.init(alloc, in_path, out_path);
    defer lua_parser.deinit();
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

    std.log.debug("Attempting to open file {s}", .{full_path});
    const vim_plugins_file = try fs.openFileAbsolute(full_path, .{});

    // Get plugins
    var input_parser = InputParser.init(alloc, vim_plugins_file);
    defer input_parser.deinit();

    return try input_parser.parseInput(input_blob);
}

test {
    _ = @import("parsers/InputParser.zig");
    _ = @import("parsers/LuaParser.zig");
    _ = @import("utils.zig");
}
