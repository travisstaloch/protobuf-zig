const std = @import("std");

pub const plugin_arg = "--plugin=zig-out/bin/protoc-gen-zig" ++
    (if (@import("builtin").target.os.tag == .windows) ".exe" else "");

pub const GenStep = struct {
    step: std.build.Step,
    b: *std.build.Builder,
    sources: std.ArrayListUnmanaged(std.build.FileSource) = .{},
    cache_path: []const u8,
    lib_file: std.build.GeneratedFile,
    module: *std.Build.Module,

    /// init a GenStep, create zig-cache/protobuf-zig if not exists, setup
    /// dependencies, and setup args to exe.run()
    pub fn create(
        b: *std.build.Builder,
        exe: *std.build.LibExeObjStep,
        files: []const []const u8,
    ) !*GenStep {
        const self = b.allocator.create(GenStep) catch unreachable;
        const cache_root = std.fs.path.resolve(
            b.allocator,
            &.{b.cache_root.path orelse "."},
        ) catch @panic("OOM");
        const protobuf_zig_path = "protobuf-zig";
        const cache_path = try std.fs.path.join(
            b.allocator,
            &.{ cache_root, protobuf_zig_path },
        );
        const lib_path = try std.fs.path.join(
            b.allocator,
            &.{ cache_path, "lib.zig" },
        );
        self.* = GenStep{
            .step = std.build.Step.init(.{
                .id = .custom,
                .name = "build-template",
                .owner = b,
                .makeFn = &make,
            }),
            .b = b,
            .cache_path = cache_path,
            .lib_file = .{
                .step = &self.step,
                .path = lib_path,
            },
            .module = b.createModule(.{
                .source_file = .{ .path = lib_path },
            }),
        };

        for (files) |file| {
            const source = try self.sources.addOne(b.allocator);
            source.* = .{ .path = file };
            source.addStepDependencies(&self.step);
        }

        const run_cmd = b.addSystemCommand(&.{
            "protoc",
            plugin_arg,
            "--zig_out",
            cache_path,
            "-I",
            "examples",
        });
        run_cmd.step.dependOn(&exe.step);
        for (files) |file| run_cmd.addArg(file);
        self.step.dependOn(&run_cmd.step);

        try b.cache_root.handle.makePath(protobuf_zig_path);

        return self;
    }

    /// creates a 'lib.zig' file at self.lib_file.path which exports all
    /// generated .pb.zig files
    fn make(step: *std.build.Step, prog_node: *std.Progress.Node) anyerror!void {
        _ = prog_node;
        const self = @fieldParentPtr(GenStep, "step", step);

        var file = try std.fs.cwd().createFile(self.lib_file.path.?, .{});
        defer file.close();
        const writer = file.writer();
        for (self.sources.items) |source| {
            const endidx = std.mem.lastIndexOf(u8, source.path, ".proto") orelse {
                std.log.err(
                    "invalid path '{s}'. expected to end with '.proto'",
                    .{source.path},
                );
                return error.InvalidPath;
            };
            const startidx = if (std.mem.lastIndexOfScalar(
                u8,
                source.path[0..endidx],
                '/',
            )) |i| i + 1 else 0;
            const name = source.path[startidx..endidx];
            // remove illegal characters to make a zig identifier
            var buf: [256]u8 = undefined;
            std.mem.copy(u8, &buf, name);
            if (!std.ascii.isAlphabetic(name[0]) and name[0] != '_') {
                std.log.err(
                    "invalid identifier '{s}'. filename must start with alphabetic or underscore",
                    .{name},
                );
                return error.InvalidIdentifier;
            }
            for (name[1..], 0..) |c, i| {
                if (!std.ascii.isAlphanumeric(c)) buf[i + 1] = '_';
            }
            const path = if (std.mem.startsWith(u8, source.path, "examples/"))
                source.path[0..endidx]["examples/".len..]
            else
                source.path[0..endidx];
            try writer.print(
                \\pub const {s} = @import("{s}.pb.zig");
                \\
            , .{ buf[0..name.len], path });
        }
    }
};
