const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Exact tier: no FP contraction. The codec is integer, so this is exact.
    const flags = [_][]const u8{ "-O3", "-ffp-contract=off" };

    // Pin the CPU model explicitly: Zig maps -march to -mcpu and a native build
    // would widen *every* file to the host CPU (see V1.4). The distribution
    // baseline is x86-64-v2; optional kernels carry their own target attrs.
    var q = target.query;
    if (target.result.cpu.arch == .x86_64) {
        q.cpu_model = .{ .explicit = &std.Target.x86.cpu.x86_64_v2 };
    } else {
        q.cpu_model = .baseline;
    }
    const pinned = b.resolveTargetQuery(q);

    const mod = b.createModule(.{
        .target = pinned,
        .optimize = optimize,
        .link_libc = true,
    });
    mod.addIncludePath(b.path("src"));
    mod.addCSourceFiles(.{
        .files = &.{
            "src/miniz.c",
            "src/miniz_tdef.c",
            "src/miniz_tinfl.c",
            "src/miniz_zip.c",
        },
        .flags = &flags,
    });

    const lib = b.addLibrary(.{
        .name = "miniz-opt",
        .root_module = mod,
        .linkage = .static,
    });
    b.installArtifact(lib);

    // Public headers (unchanged upstream API; miniz_export.h is generated).
    b.installFile("src/miniz.h", "include/miniz.h");
    b.installFile("src/miniz_common.h", "include/miniz_common.h");
    b.installFile("src/miniz_tdef.h", "include/miniz_tdef.h");
    b.installFile("src/miniz_tinfl.h", "include/miniz_tinfl.h");
    b.installFile("src/miniz_zip.h", "include/miniz_zip.h");
    b.installFile("src/miniz_export.h", "include/miniz_export.h");
}
