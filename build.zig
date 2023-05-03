const std = @import("std");
const GenFormat = @import("src/common.zig").GenFormat;
const sdk = @import("sdk.zig");

pub fn build(b: *std.build.Builder) !void {
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
    const gen_format = b.option(
        GenFormat,
        "gen-format",
        "The output format of generated code.",
    ) orelse .zig;
    const test_filter = b.option(
        []const u8,
        "test-filter",
        "A filter for tests",
    ) orelse "";

    const protobuf_mod = b.createModule(.{
        .source_file = .{ .path = "src/lib.zig" },
    });
    try protobuf_mod.dependencies.put("protobuf", protobuf_mod);

    const build_options = b.addOptions();
    build_options.addOption(std.log.Level, "log_level", log_level);
    build_options.addOption(bool, "echo_hex", echo_hex);
    build_options.addOption(GenFormat, "output_format", gen_format);

    // for capturing output of system installed protoc. just echoes out whatever protoc sends
    const protocgen_echo = b.addExecutable(.{
        .name = "protoc-gen-zig",
        .root_source_file = .{ .path = "src/protoc-gen-zig.zig" },
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(protocgen_echo);
    protocgen_echo.addOptions("build_options", build_options);

    const protoc_zig = b.addExecutable(.{
        .name = "protoc-zig",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(protoc_zig);
    protoc_zig.addOptions("build_options", build_options);
    protoc_zig.addModule("protobuf", protobuf_mod);

    const run_cmd = b.addRunArtifact(protoc_zig);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    // generate files that need to be avaliable in tests
    var gen_step = try sdk.GenStep.create(b, protoc_zig, &.{
        "examples/all_types.proto",
        "examples/only_enum.proto",
        "examples/person.proto",
        "examples/oneof-2.proto",
        "examples/conformance.proto",
        "examples/google/protobuf/wrappers.proto",
        "examples/google/protobuf/timestamp.proto",
        "examples/google/protobuf/field_mask.proto",
        "examples/google/protobuf/duration.proto",
        "examples/google/protobuf/any.proto",
        "examples/google/protobuf/test_messages_proto3.proto",
        "examples/google/protobuf/test_messages_proto2.proto",
        "examples/group.proto",
    });

    const main_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/tests.zig" },
        .target = target,
        .optimize = optimize,
    });
    main_tests.addModule("protobuf", protobuf_mod);
    main_tests.addAnonymousModule("generated", .{
        .source_file = gen_step.module.source_file,
        .dependencies = &.{.{ .name = "protobuf", .module = protobuf_mod }},
    });
    main_tests.step.dependOn(b.getInstallStep());
    main_tests.step.dependOn(&gen_step.step);
    main_tests.filter = test_filter;

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&main_tests.step);

    const conformance_exe = b.addExecutable(.{
        .name = "conformance",
        .root_source_file = .{ .path = "src/conformance.zig" },
        .target = target,
        .optimize = optimize,
    });
    conformance_exe.addOptions("build_options", build_options);
    conformance_exe.addModule("protobuf", protobuf_mod);
    conformance_exe.addAnonymousModule("generated", .{
        .source_file = gen_step.module.source_file,
        .dependencies = &.{.{ .name = "protobuf", .module = protobuf_mod }},
    });
    conformance_exe.step.dependOn(&gen_step.step);
    b.installArtifact(conformance_exe);
}
