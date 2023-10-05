const std = @import("std");
const zmath = @import("libs/zig-gamedev/libs/zmath/build.zig");
const zgpu = @import("libs/zig-gamedev/libs/zgpu/build.zig");
const zpool = @import("libs/zig-gamedev/libs/zpool/build.zig");
const zglfw = @import("libs/zig-gamedev/libs/zglfw/build.zig");
const zstbi = @import("libs/zig-gamedev/libs/zstbi/build.zig");

pub fn build(b: *std.Build) void {
    const target = std.zig.CrossTarget{ .os_tag = .windows, .cpu_arch = .x86_64 };
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "zig_ornament",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    exe.addIncludePath(std.Build.LazyPath.relative("libs/assimp/include"));
    exe.addLibraryPath(std.Build.LazyPath.relative("libs/assimp"));
    exe.linkSystemLibraryName("assimp-vc143-mt");
    b.installBinFile("libs/assimp/assimp-vc143-mt.dll", "assimp-vc143-mt.dll");

    const zmath_pkg = zmath.package(b, target, optimize, .{ .options = .{ .enable_cross_platform_determinism = true } });
    const zglfw_pkg = zglfw.package(b, target, optimize, .{});
    const zpool_pkg = zpool.package(b, target, optimize, .{});
    const zgpu_pkg = zgpu.package(b, target, optimize, .{ .deps = .{ .zpool = zpool_pkg.zpool, .zglfw = zglfw_pkg.zglfw } });
    const zstbi_pkg = zstbi.package(b, target, optimize, .{});

    zmath_pkg.link(exe);
    zgpu_pkg.link(exe);
    zglfw_pkg.link(exe);
    zstbi_pkg.link(exe);

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
