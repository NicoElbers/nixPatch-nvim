const std = @import("std");
const Build = std.Build;
const Step = Build.Step;

pub const NamedModule = struct {
    mod: *Build.Module,
    name: []const u8,

    pub fn init(b: *Build, name: []const u8, options: Build.Module.CreateOptions) NamedModule {
        const mod = b.addModule(name, options);
        return NamedModule{
            .mod = mod,
            .name = name,
        };
    }
};

pub fn build(b: *Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Parser module
    const parsers_mod = NamedModule.init(b, "parsers", .{
        .root_source_file = b.path("patcher/src/parsers/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Check step
    const check = b.step("check", "Check if project compiles");

    // Create exe
    const exe = addExe(b, check, &.{parsers_mod}, .{
        .name = "config-patcher",
        .root_source_file = b.path("patcher/src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Run command
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    // Tests
    const test_step = b.step("test", "Run unit tests");

    _ = addTest(b, check, &.{parsers_mod}, test_step, .{
        .root_source_file = b.path("patcher/src/parsers/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    _ = addTest(b, check, &.{parsers_mod}, test_step, .{
        .root_source_file = b.path("patcher/test/root.zig"),
        .target = target,
        .optimize = optimize,
    });
}

fn addExe(b: *Build, check: *Step, mods: []const NamedModule, options: Build.ExecutableOptions) *Step.Compile {
    const exe = b.addExecutable(options);
    for (mods) |mod| {
        exe.root_module.addImport(mod.name, mod.mod);
    }
    b.installArtifact(exe);

    const check_exe = b.addExecutable(options);
    for (mods) |mod| {
        check_exe.root_module.addImport(mod.name, mod.mod);
    }
    check.dependOn(&check_exe.step);

    return exe;
}

fn addTest(b: *Build, check: *Step, mods: []const NamedModule, tst_step: *Step, options: Build.TestOptions) *Step.Compile {
    const tst = b.addTest(options);
    for (mods) |mod| {
        tst.root_module.addImport(mod.name, mod.mod);
    }
    const run_tst = b.addRunArtifact(tst);
    run_tst.has_side_effects = true;
    tst_step.dependOn(&run_tst.step);

    const check_tst = b.addTest(options);
    for (mods) |mod| {
        check_tst.root_module.addImport(mod.name, mod.mod);
    }
    check.dependOn(&check_tst.step);

    return tst;
}
