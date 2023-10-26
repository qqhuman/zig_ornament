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
    dep_steps: *std.Build.Step,

    pub fn link(self: Package, exe: *std.Build.CompileStep) void {
        exe.linkLibC();
        exe.linkLibCpp();

        exe.addLibraryPath(std.Build.LazyPath.relative("libs/wgpu-native"));
        exe.linkSystemLibraryName("wgpu_native.dll");

        const hip_sdk_dir = "C:/Program Files/AMD/ROCm/5.5/";
        exe.addIncludePath(std.build.LazyPath{ .path = hip_sdk_dir ++ "include" });
        exe.addLibraryPath(std.build.LazyPath{ .path = hip_sdk_dir ++ "lib" });
        exe.linkSystemLibrary("amdhip64");

        exe.defineCMacro("__HIP_PLATFORM_AMD__", null);
        exe.addIncludePath(std.Build.LazyPath.relative("src/hip"));
        exe.addCSourceFile(.{ .file = .{ .path = "src/hip/hip.cpp" }, .flags = &.{""} });

        exe.step.dependOn(self.dep_steps);
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
    const install_wgpu = b.addInstallBinFile(std.build.LazyPath.relative("libs/wgpu-native/wgpu_native.dll"), "wgpu_native.dll");
    const build_hip_kernals = b.addSystemCommand(&.{
        "hipcc",
        "--genco",
        "--offload-arch=gfx1031",
        "-o",
        b.pathJoin(&.{ b.exe_dir, "pathtracer.co" }),
        "src/hip/kernels/pathtracer.cpp",
    });

    const dep_steps = b.allocator.create(std.Build.Step) catch @panic("OOM");
    dep_steps.* = std.Build.Step.init(.{ .id = .custom, .name = "ornament. install wgpu. build hip kernels", .owner = b });
    dep_steps.dependOn(&install_wgpu.step);
    dep_steps.dependOn(&build_hip_kernals.step);
    return .{
        .ornament = b.createModule(.{
            .source_file = .{ .path = "src/ornament.zig" },
            .dependencies = &.{
                .{ .name = "zmath", .module = args.deps.zmath_pkg.zmath },
            },
        }),
        .dep_steps = dep_steps,
    };
}
