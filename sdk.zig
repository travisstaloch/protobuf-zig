const std = @import("std");

pub const GenStep = struct {
    step: std.build.Step,
    b: *std.build.Builder,
    sources: std.ArrayListUnmanaged(std.build.FileSource) = .{},
    cache_path: []const u8,
    lib_file: std.build.GeneratedFile,
    module: *std.Build.Module,

    pub fn create(
        b: *std.build.Builder,
        exe: *std.build.LibExeObjStep,
        files: []const []const u8,
    ) !*GenStep {
        const self = b.allocator.create(GenStep) catch unreachable;
        const cache_path = try std.fs.path.join(
            b.allocator,
            &.{ b.cache_root, "protobuf-zig" },
        );
        const lib_path = try std.fs.path.join(
            b.allocator,
            &.{ cache_path, "lib.zig" },
        );
        self.* = GenStep{
            .step = std.build.Step.init(
                .custom,
                "build-template",
                b.allocator,
                make,
            ),
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

        const run_cmd = exe.run();
        run_cmd.step.dependOn(&exe.step);

        try b.makePath(cache_path);

        run_cmd.addArgs(&.{ "--zig_out", cache_path, "-I", "examples" });

        for (files) |file|
            run_cmd.addArg(file);

        self.step.dependOn(&run_cmd.step);

        return self;
    }

    /// creates a 'lib.zig' file at self.lib_file.path which just all
    /// generated .pb.zig files
    fn make(step: *std.build.Step) !void {
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
            try writer.print(
                \\pub const {s} = @import("{s}.pb.zig");
                \\
            , .{ name, name });
        }
    }
};
