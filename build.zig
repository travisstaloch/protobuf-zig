const std = @import("std");

pub fn build(b: *std.build.Builder) void {
    const target = b.standardTargetOptions(.{});
    const mode = b.standardReleaseOptions();

    const log_level = b.option(
        std.log.Level,
        "log-level",
        "The log level for the application. default .err",
    ) orelse .err;
    const hex_output = b.option(
        bool,
        "hex",
        "protoc-gen-zig output hex instead of raw bytes",
    ) orelse false;
    const build_options = b.addOptions();
    build_options.addOption(std.log.Level, "log_level", log_level);
    build_options.addOption(bool, "hex_output", hex_output);

    // for capturing output of system installed protoc. just echoes out whatever protoc sends
    const protocgen_echo = b.addExecutable("protoc-gen-zig", "src/protoc-gen-zig.zig");
    protocgen_echo.setTarget(target);
    protocgen_echo.setBuildMode(mode);
    protocgen_echo.install();
    protocgen_echo.addOptions("build_options", build_options);

    const protoc_zig = b.addExecutable("protoc-zig", "src/main.zig");
    protoc_zig.setTarget(target);
    protoc_zig.setBuildMode(mode);
    protoc_zig.install();
    protoc_zig.addOptions("build_options", build_options);

    const run_cmd = protoc_zig.run();
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const main_tests = b.addTest("src/tests.zig");
    main_tests.setBuildMode(mode);

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&main_tests.step);
}
