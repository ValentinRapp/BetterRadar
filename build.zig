const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const raylib_dep = b.dependency("raylib_zig", .{
        .target = target,
        .optimize = optimize,
    });
    const raylib = raylib_dep.module("raylib");
    const raylib_artifact = raylib_dep.artifact("raylib");

    const exe = b.addExecutable(.{
        .name = "betterradar",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "raylib", .module = raylib },
            },
        }),
    });
    exe.linkLibrary(raylib_artifact);

    b.installArtifact(exe);

    const run_step = b.step("run", "Run the app");

    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    // Fast release build with native CPU optimizations (AVX2/NEON)
    const release_step = b.step("release", "release build");
    const release_target = b.resolveTargetQuery(.{
        .cpu_model = .native,
    });
    const release_exe = b.addExecutable(.{
        .name = "betterradar",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = release_target,
            .optimize = .ReleaseFast,
            .imports = &.{
                .{ .name = "raylib", .module = raylib },
            },
        }),
    });
    release_exe.linkLibrary(raylib_artifact);
    const release_install = b.addInstallArtifact(release_exe, .{});
    const release_run = b.addRunArtifact(release_exe);
    release_run.step.dependOn(&release_install.step);
    release_step.dependOn(&release_run.step);
}
