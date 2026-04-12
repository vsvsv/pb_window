const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const pbwindow_mod = b.addModule("pb_window", .{
        .root_source_file = b.path("src/pb_window.zig"),
        .target = target,
        .link_libc = (target.result.os.tag == .windows or target.result.os.tag == .linux),
    });

    if (target.result.os.tag == .macos) {
        pbwindow_mod.linkSystemLibrary("objc", .{});
        pbwindow_mod.linkFramework("Cocoa", .{});
        pbwindow_mod.linkFramework("CoreVideo", .{});
    } else if (target.result.os.tag == .windows) {
        pbwindow_mod.linkSystemLibrary("gdi32", .{});
        pbwindow_mod.linkSystemLibrary("opengl32", .{});
        if (target.result.os.isAtLeast(.windows, .win10) orelse false) {
            pbwindow_mod.linkSystemLibrary("dwmapi", .{});
        }
    } else { // All others are considered Linux-like
        // On Linux, `libx11` and `libgl` libraries are needed for accessing X11 and OpenGL API.
        // They can be installed by `sudo apt install libx11-dev libgl1-mesa-dev` on Debian-based distros.
        // On other distributions, search for `x11` and `opengl` packages with your package manager of choice.
        pbwindow_mod.linkSystemLibrary("X11", .{});
        pbwindow_mod.linkSystemLibrary("GL", .{});
    }

    const exe = b.addExecutable(.{
        .name = "pb_window_demo",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/examples/with_fps_counter.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "pb_window", .module = pbwindow_mod },
            },
        }),
    });
    b.installArtifact(exe);

    const run_step = b.step("run", "Run the app");
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const mod_tests = b.addTest(.{
        .root_module = pbwindow_mod,
    });
    const run_mod_tests = b.addRunArtifact(mod_tests);

    const exe_tests = b.addTest(.{
        .root_module = exe.root_module,
    });
    const run_exe_tests = b.addRunArtifact(exe_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);
    test_step.dependOn(&run_exe_tests.step);
}
