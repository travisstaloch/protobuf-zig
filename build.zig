const std = @import("std");

pub fn build(b: *std.build.Builder) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const log_level = b.option(
        std.log.Level,
        "log-level",
        "The log level for the application. default .err",
    ) orelse .err;
    const echo_hex = b.option(
        bool,
        "echo-hex",
        "protoc-gen-zig will echo contents of stdin as hex instead of raw bytes.  useful for capturing results of system protoc commands in hex format.",
    ) orelse false;

    const protobuf_pkg = std.build.Pkg{
        .name = "protobuf",
        .source = .{ .path = "src/lib.zig" },
        // TODO get rid of this nesting
        .dependencies = &.{.{
            .name = "protobuf",
            .source = .{ .path = "src/lib.zig" },
        }},
    };

    const build_options = b.addOptions();
    build_options.addOption(std.log.Level, "log_level", log_level);
    build_options.addOption(bool, "echo_hex", echo_hex);

    // for capturing output of system installed protoc. just echoes out whatever protoc sends
    const protocgen_echo = b.addExecutable(.{
        .name = "protoc-gen-zig",
        .root_source_file = .{ .path = "src/protoc-gen-zig.zig" },
        .target = target,
        .optimize = optimize,
    });
    protocgen_echo.install();
    protocgen_echo.addOptions("build_options", build_options);

    const protoc_zig = b.addExecutable(.{
        .name = "protoc-zig",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });
    protoc_zig.install();
    protoc_zig.addOptions("build_options", build_options);
    protoc_zig.addPackage(protobuf_pkg);

    const run_cmd = protoc_zig.run();
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const main_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/tests.zig" },
        .target = target,
        .optimize = optimize,
    });
    main_tests.addPackage(protobuf_pkg);
    // allow readme test to import from examples/gen
    main_tests.main_pkg_path = ".";

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&main_tests.step);
}
