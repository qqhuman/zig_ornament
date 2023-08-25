const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "zig_ornament",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    //exe.defineCMacro("_GLFW_WIN32", null);
    exe.addIncludePath(std.Build.LazyPath.relative("libs/glfw/include/GLFW"));
    exe.addObjectFile(std.Build.LazyPath.relative("libs/glfw/lib-mingw-w64/libglfw3dll.a"));
    exe.addObjectFile(std.Build.LazyPath.relative("libs/glfw/lib-mingw-w64/libglfw3.a"));
    b.installFile("libs/glfw/lib-mingw-w64/glfw3.dll", "bin/glfw3.dll");

    exe.addIncludePath(std.Build.LazyPath.relative("libs/wgpu"));
    exe.addLibraryPath(std.Build.LazyPath.relative("libs/wgpu"));
    b.installFile("libs/wgpu/wgpu_native.dll", "bin/wgpu_native.dll");
    exe.linkSystemLibraryName("wgpu_native.dll");
    exe.linkSystemLibraryName("wgpu_native");

    exe.linkSystemLibraryName("user32");
    exe.linkLibC();

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
