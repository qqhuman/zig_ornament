const std = @import("std");
const zmath = @import("libs/zig-gamedev/libs/zmath/build.zig");
const zglfw = @import("libs/zig-gamedev/libs/zglfw/build.zig");
const zstbi = @import("libs/zig-gamedev/libs/zstbi/build.zig");

pub fn build(b: *std.Build) void {
    const target = std.zig.CrossTarget{ .os_tag = .windows, .cpu_arch = .x86_64 };
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "glfw_example",
        .root_source_file = .{ .path = "glfw_example/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    const exe_options = b.addOptions();
    exe.addOptions("build_options", exe_options);
    exe_options.addOption([]const u8, "models_dir", "assets/" ++ "models/");
    exe_options.addOption([]const u8, "textures_dir", "assets/" ++ "textures/");

    const install_assets_step = b.addInstallDirectory(.{
        .source_dir = .{ .path = "glfw_example/assets/" },
        .install_dir = .{ .custom = "" },
        .install_subdir = "bin/" ++ "assets/",
    });
    exe.step.dependOn(&install_assets_step.step);

    exe.addIncludePath(std.Build.LazyPath.relative("libs/assimp/include"));
    exe.addLibraryPath(std.Build.LazyPath.relative("libs/assimp"));
    exe.linkSystemLibraryName("assimp-vc143-mt");
    b.installBinFile("libs/assimp/assimp-vc143-mt.dll", "assimp-vc143-mt.dll");

    var zmath_pkg = zmath.package(b, target, optimize, .{ .options = .{ .enable_cross_platform_determinism = true } });
    const zglfw_pkg = zglfw.package(b, target, optimize, .{});
    const zstbi_pkg = zstbi.package(b, target, optimize, .{});
    const ornament = package(b, .{ .deps = .{ .zmath_pkg = &zmath_pkg } });

    zmath_pkg.link(exe);
    zglfw_pkg.link(exe);
    zstbi_pkg.link(exe);
    ornament.link(exe);

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}

pub const Package = struct {
    ornament: *std.Build.Module,
    install: *std.Build.Step,

    pub fn link(self: Package, exe: *std.Build.CompileStep) void {
        exe.addLibraryPath(std.Build.LazyPath.relative("libs/wgpu-native"));
        exe.linkSystemLibraryName("wgpu_native.dll");

        exe.step.dependOn(self.install);
        exe.addModule("ornament", self.ornament);
    }
};

pub fn package(
    b: *std.Build,
    args: struct {
        deps: struct {
            zmath_pkg: *zmath.Package,
        },
    },
) Package {
    const install_step = b.allocator.create(std.Build.Step) catch @panic("OOM");
    install_step.* = std.Build.Step.init(.{ .id = .custom, .name = "ornament-install", .owner = b });

    install_step.dependOn(
        &b.addInstallFile(
            .{ .path = "libs/wgpu-native/wgpu_native.dll" },
            "bin/wgpu_native.dll",
        ).step,
    );
    return .{
        .ornament = b.createModule(.{
            .source_file = .{ .path = "src/ornament.zig" },
            .dependencies = &.{
                .{ .name = "zmath", .module = args.deps.zmath_pkg.zmath },
            },
        }),
        .install = install_step,
    };
}
