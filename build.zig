const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "bt",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
        .use_llvm = true,
    });

    // Link GTK4 libraries
    exe.linkLibC();
    exe.linkSystemLibrary("gtk4");
    exe.linkSystemLibrary("cairo");
    exe.linkSystemLibrary("gobject-2.0");
    exe.linkSystemLibrary("glib-2.0");
    exe.linkSystemLibrary("gio-2.0");

    // Link Bluetooth libraries (bluez on Linux)
    exe.linkSystemLibrary("bluetooth");

    // Create modules
    const core_module = b.addModule("core", .{
        .root_source_file = b.path("src/core.zig"),
    });

    // Add modules to executable
    exe.root_module.addImport("core", core_module);

    b.installArtifact(exe);

    // Run command
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the application");
    run_step.dependOn(&run_cmd.step);

    // Tests
    const exe_tests = b.addTest(.{
        .root_module = exe.root_module,
    });

    const run_exe_tests = b.addRunArtifact(exe_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_exe_tests.step);
}
