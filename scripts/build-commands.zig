pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const alloc = gpa.allocator();

    const args = try process.argsAlloc(alloc);
    defer process.argsFree(alloc, args);

    assert(args.len >= 1);

    // Zig build --verbose {args[1..]}
    //  1    2      3       args.len -1
    const build_args = try alloc.alloc([]const u8, 3 + args.len - 1);
    defer alloc.free(build_args);

    build_args[0..3].* = .{
        "zig",
        "build",
        "--verbose",
    };

    @memcpy(build_args[3..], args[1..]);

    std.log.info("Running command:\ninfo: {s} \\", .{build_args[0]});
    for (build_args[1..]) |item| {
        std.log.info("\t{s} \\", .{item});
    }

    var stdout: ArrayListUnmanaged(u8) = .empty;
    defer stdout.deinit(alloc);

    var stderr: ArrayListUnmanaged(u8) = .empty;
    defer stderr.deinit(alloc);

    const term = blk: {
        var build_process = Child.init(build_args, alloc);
        build_process.stdin_behavior = .Pipe;
        build_process.stdout_behavior = .Pipe;
        build_process.stderr_behavior = .Pipe;

        try build_process.spawn();

        try build_process.collectOutput(alloc, &stdout, &stderr, std.math.maxInt(isize));

        break :blk try build_process.wait();
    };

    if (term != .Exited or term.Exited != 0) {
        std.log.err(
            \\Build process exited with exit code {d}
            \\stderr: 
            \\{s}
            \\
            \\stdout:
            \\{s}
        , .{ term.Exited, stderr.items, stdout.items });

        return;
    }

    const cwd = std.fs.cwd();
    const pwd = try cwd.realpathAlloc(alloc, ".");
    defer alloc.free(pwd);

    std.log.info("Assuming pwd is {s}", .{pwd});

    const io_stdout = std.io.getStdOut();
    const writer = io_stdout.writer();

    var lines = mem.splitScalar(u8, stderr.items, '\n');
    while (lines.next()) |line| {
        if (line.len == 0) continue;
        var line_args = mem.splitScalar(u8, line, ' ');

        if (!mem.endsWith(u8, line_args.first(), "zig")) continue;
        try writer.writeAll("zig");

        while (line_args.next()) |arg| {
            if (arg.len == 0 or
                mem.eql(u8, arg, "--listen=-")) continue;

            // add a space and "\n\t" to have a somewhat nice command
            try writer.writeAll(" \\\n\t");

            if (mem.eql(u8, arg, "--global-cache-dir")) {
                assert(line_args.next() != null); // --global-cache-dir should have an arg

                // If we see global-cache-dir, we need to replace the next arg
                // with $(pwd)/.cache
                try writer.writeAll("--global-cache-dir $(pwd)/.cache");
            } else if (mem.indexOf(u8, arg, pwd)) |index| {
                // If we reference pwd, replace that with $(pwd)
                try writer.writeAll(arg[0..index]);
                try writer.writeAll("$(pwd)");
                try writer.writeAll(arg[index + pwd.len ..]);
            } else {
                try writer.writeAll(arg);
            }
        }
        try writer.writeAll("\n\n");
    }
}

const std = @import("std");
const process = std.process;
const posix = std.posix;
const windows = std.os.windows;
const builtin = @import("builtin");
const mem = std.mem;

const assert = std.debug.assert;

const Child = process.Child;
const Allocator = std.mem.Allocator;
const ArrayListUnmanaged = std.ArrayListUnmanaged;
