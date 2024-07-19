// FIXME: Think about the case where a user adds their own plugin to nixpkgs

const std = @import("std");
const InputParser = @import("parsers/InputParser.zig");
const LuaParser = @import("parsers/LuaParser.zig");

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const alloc = arena.allocator();

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

    var input_parser = try InputParser.init(alloc, nixpkgs_path);
    defer input_parser.deinit();

    const plugins = try input_parser.parseInput(input_blob);
    _ = plugins;

    var lua_parser = try LuaParser.init(alloc, in_path, out_path);
    defer lua_parser.deinit();
}
