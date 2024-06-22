const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const lib = b.addStaticLibrary(.{
        .name = "xstd",
        .root_source_file = .{ .src_path = .{ .owner = b, .sub_path = "src/lib.zig" } },
        .target = target,
        .optimize = optimize,
    });

    b.installArtifact(lib);

    // examples
    const examples_step = b.step("examples", "build all examples");

    inline for ([_]struct {
        name: []const u8,
        src: []const u8,
    }{
        .{ .name = "list-circular", .src = "examples/list/circular.zig" },
        .{ .name = "logger", .src = "examples/log/logger.zig" },
        .{ .name = "pool-utf8buffer", .src = "examples/pool/utf8buffer.zig" },
        .{ .name = "time-zoneinfo", .src = "examples/time/zoneinfo.zig" },
        .{ .name = "zip", .src = "examples/archive/zip.zig" },
        .{ .name = "buffer-stream", .src = "examples/buffer/flexible_stream.zig" },
        .{ .name = "utf8buffer_split", .src = "examples/buffer/utf8buffer_split.zig" },
        .{ .name = "alignment", .src = "examples/alignment/alignment.zig" },
    }) |excfg| {
        const ex_name = excfg.name;
        const ex_src = excfg.src;
        const ex_build_desc = try std.fmt.allocPrint(
            b.allocator,
            "build the {s} example",
            .{ex_name},
        );
        const ex_run_stepname = try std.fmt.allocPrint(
            b.allocator,
            "run-{s}",
            .{ex_name},
        );
        const ex_run_stepdesc = try std.fmt.allocPrint(
            b.allocator,
            "run the {s} example",
            .{ex_name},
        );
        const example_run_step = b.step(ex_run_stepname, ex_run_stepdesc);
        const example_step = b.step(ex_name, ex_build_desc);

        var example = b.addExecutable(.{
            .name = ex_name,
            .root_source_file = .{ .src_path = .{ .owner = b, .sub_path = ex_src } },
            .target = target,
            .optimize = optimize,
            .single_threaded = false,
        });

        example.linkLibrary(lib);
        example.root_module.addAnonymousImport("xstd", .{
            .root_source_file = .{ .src_path = .{ .owner = b, .sub_path = "src/lib.zig" } },
        });

        // const example_run = example.run();
        const example_run = b.addRunArtifact(example);
        example_run_step.dependOn(&example_run.step);

        // install the artifact - depending on the "example"
        const example_build_step = b.addInstallArtifact(example, .{});
        example_step.dependOn(&example_build_step.step);
        examples_step.dependOn(&example_build_step.step);
    }

    // Creates a step for unit testing. This only builds the test executable
    // but does not run it.
    var tests_suite = b.step("test-suite", "Run unit tests");
    {
        const dir = try std.fs.cwd().openDir("./src", .{});

        var iter = try dir.walk(b.allocator);

        const allowed_exts = [_][]const u8{".zig"};
        while (try iter.next()) |entry| {
            const ext = std.fs.path.extension(entry.basename);
            const include_file = for (allowed_exts) |e| {
                if (std.mem.eql(u8, ext, e))
                    break true;
            } else false;
            if (include_file) {
                // we have to clone the path as walker.next() or walker.deinit() will override/kill it

                var buff: [1024]u8 = undefined;
                const testPath = try std.fmt.bufPrint(&buff, "src/{s}", .{entry.path});
                //std.debug.print("Testing: {s}\n", .{testPath});

                tests_suite.dependOn(&b.addRunArtifact(b.addTest(.{
                    .root_source_file = .{ .src_path = .{ .owner = b, .sub_path = testPath } },
                    .target = target,
                    .optimize = optimize,
                })).step);
            }
        }
    }
}
