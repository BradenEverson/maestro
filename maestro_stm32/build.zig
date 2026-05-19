const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.resolveTargetQuery(.{
        .cpu_arch = .thumb,
        .cpu_model = .{ .explicit = &std.Target.arm.cpu.cortex_m4 },
        .os_tag = .freestanding,
        .abi = .eabihf,
    });
    const optimize = b.standardOptimizeOption(.{ .preferred_optimize_mode = .ReleaseSmall });

    const obj = b.addObject(.{
        .name = "ztm32",
        .root_module = b.createModule(.{
            .optimize = optimize,
            .target = target,
            .root_source_file = b.path("src/main.zig"),
        }),
    });

    const midi = b.dependency("midi", .{
        .target = target,
        .optimize = optimize,
    });

    obj.root_module.addImport("midi", midi.module("midi"));

    const ld_cmd = b.addSystemCommand(&.{ "arm-none-eabi-ld", "-T", "flash.ld", "-o" });
    const elf_file = ld_cmd.addOutputFileArg("maestro.elf");
    ld_cmd.addArtifactArg(obj);

    const objcopy_cmd = b.addSystemCommand(&.{ "arm-none-eabi-objcopy", "-O", "binary" });
    objcopy_cmd.addFileArg(elf_file);
    const bin_file = objcopy_cmd.addOutputFileArg("maestro.bin");

    const install_bin = b.addInstallFile(bin_file, "maestro.bin");
    b.getInstallStep().dependOn(&install_bin.step);
}
