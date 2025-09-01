const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "ndmgr",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    // Add version information at compile time
    const version_options = b.addOptions();
    exe.root_module.addOptions("version", version_options);

    // Get git version tag and trim whitespace
    const git_version_raw = b.run(&.{ "git", "describe", "--tags", "--always", "--dirty" });
    const git_version = std.mem.trim(u8, git_version_raw, " \t\n\r");
    version_options.addOption([]const u8, "version", git_version);

    // Get git commit hash and trim whitespace
    const git_commit_raw = b.run(&.{ "git", "rev-parse", "HEAD" });
    const git_commit = std.mem.trim(u8, git_commit_raw, " \t\n\r");
    version_options.addOption([]const u8, "commit", git_commit);

    // Add build timestamp and trim whitespace
    const build_time_raw = b.run(&.{ "date", "-u", "+%Y-%m-%d %H:%M:%S UTC" });
    const build_time = std.mem.trim(u8, build_time_raw, " \t\n\r");
    version_options.addOption([]const u8, "build_time", build_time);

    // Add toml dependency
    const toml_dep = b.dependency("toml", .{
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addImport("toml", toml_dep.module("toml"));


    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    // Tests
    const unit_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tests.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    // Add version information to tests
    unit_tests.root_module.addOptions("version", version_options);

    // Add toml dependency to tests
    unit_tests.root_module.addImport("toml", toml_dep.module("toml"));

    const run_unit_tests = b.addRunArtifact(unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);
}