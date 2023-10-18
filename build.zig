const std = @import("std");
const zmath = @import("libs/zig-gamedev/libs/zmath/build.zig");
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

    const exe_options = b.addOptions();
    exe.addOptions("build_options", exe_options);
    exe_options.addOption([]const u8, "models_dir", "assets/" ++ "models/");
    exe_options.addOption([]const u8, "textures_dir", "assets/" ++ "textures/");

    const install_assets_step = b.addInstallDirectory(.{
        .source_dir = .{ .path = "src/glfw_example/assets/" },
        .install_dir = .{ .custom = "" },
        .install_subdir = "bin/" ++ "assets/",
    });
    exe.step.dependOn(&install_assets_step.step);

    exe.addIncludePath(std.Build.LazyPath.relative("libs/assimp/include"));
    exe.addLibraryPath(std.Build.LazyPath.relative("libs/assimp"));
    exe.linkSystemLibraryName("assimp-vc143-mt");
    b.installBinFile("libs/assimp/assimp-vc143-mt.dll", "assimp-vc143-mt.dll");

    exe.addLibraryPath(std.Build.LazyPath.relative("libs/wgpu-native"));
    exe.linkSystemLibraryName("wgpu_native.dll");
    b.installBinFile("libs/wgpu-native/wgpu_native.dll", "wgpu_native.dll");

    const zmath_pkg = zmath.package(b, target, optimize, .{ .options = .{ .enable_cross_platform_determinism = true } });
    const zglfw_pkg = zglfw.package(b, target, optimize, .{});
    const zstbi_pkg = zstbi.package(b, target, optimize, .{});

    zmath_pkg.link(exe);
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
