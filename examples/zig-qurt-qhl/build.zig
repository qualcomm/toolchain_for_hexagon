const std = @import("std");

pub fn build(b: *std.Build) !void {
    // Read environment variables from Hexagon SDK setup
    const hexagon_sdk_root = b.graph.environ_map.get("HEXAGON_SDK_ROOT") orelse "/opt/Hexagon_SDK/6.4.0.2";

    // Architecture version (v68, v69, v73, v75, v79, v81)
    const arch_option = b.option([]const u8, "arch", "Hexagon architecture version (v68, v73, v75, etc.)") orelse "v75";

    // Determine toolchain version
    const tool_version = "hexagon_toolv19";

    // Paths
    const hexagon_tools = try std.fmt.allocPrint(
        b.allocator,
        "{s}/tools/HEXAGON_Tools/19.0.04/Tools",
        .{hexagon_sdk_root},
    );

    const qurt_dir = try std.fmt.allocPrint(
        b.allocator,
        "{s}/rtos/qurt/compute{s}",
        .{ hexagon_sdk_root, arch_option },
    );

    const qhl_hvx_dir = try std.fmt.allocPrint(
        b.allocator,
        "{s}/libs/qhl_hvx/prebuilt/{s}_{s}",
        .{ hexagon_sdk_root, tool_version, arch_option },
    );

    const qhl_dir = try std.fmt.allocPrint(
        b.allocator,
        "{s}/libs/qhl/prebuilt/{s}_{s}",
        .{ hexagon_sdk_root, tool_version, arch_option },
    );

    // Output directory
    const build_dir = "zig-out/build";
    const main_obj = try std.fmt.allocPrint(b.allocator, "{s}/main.o", .{build_dir});
    const output_so = try std.fmt.allocPrint(
        b.allocator,
        "{s}/libqurt-qhl-demo.so",
        .{build_dir},
    );

    // hexagon-clang path
    const hexagon_clang = try std.fmt.allocPrint(
        b.allocator,
        "{s}/bin/hexagon-clang",
        .{hexagon_tools},
    );

    // Architecture flags
    const arch_flag = try std.fmt.allocPrint(b.allocator, "-m{s}", .{arch_option});

    // Create build directory
    const mkdir_cmd = b.addSystemCommand(&[_][]const u8{
        "mkdir",
        "-p",
        build_dir,
    });

    // Step 1: Compile Zig source to object file
    const zig_compile = b.addSystemCommand(&[_][]const u8{
        "zig",
        "build-obj",
        "src/main.zig",
        "-target",
        "hexagon-freestanding-none",
        "-mcpu",
        try std.fmt.allocPrint(b.allocator, "hexagon{s}+hvx+hvx{s}+hvx_length128b", .{ arch_option, arch_option }),
        "-fPIC",
        "-O",
        "ReleaseFast",
        try std.fmt.allocPrint(b.allocator, "-femit-bin={s}", .{main_obj}),
    });

    zig_compile.step.dependOn(&mkdir_cmd.step);

    // Step 2: Link everything using hexagon-clang (which uses ld.qcld)
    const compile_cmd = b.addSystemCommand(&[_][]const u8{
        hexagon_clang,
        // Uncomment the following to use ld.lld instead of ld.qcld:
        // "-fuse-ld=lld",
        // "-Wl,-z,max-page-size=4096",   // QuRT uses 4K pages
        // "-Wl,-z,common-page-size=4096",
        // "-Wl,-z,separate-loadable-segments", // keep PT_LOAD segments distinct for QuRT
        arch_flag,
        "-G0",
        "-mhvx",
        "-mhvx-length=128B",
        "-fno-zero-initialized-in-bss",
        "-fdata-sections",
        "-fpic",
        "-shared",
        "-o",
        output_so,
        main_obj,
    });

    // Add include paths
    compile_cmd.addArgs(&[_][]const u8{
        "-I",
        try std.fmt.allocPrint(b.allocator, "{s}/include", .{qurt_dir}),
        "-I",
        try std.fmt.allocPrint(b.allocator, "{s}/include/qurt", .{qurt_dir}),
        "-I",
        try std.fmt.allocPrint(b.allocator, "{s}/include/posix", .{qurt_dir}),
        "-I",
        try std.fmt.allocPrint(b.allocator, "{s}/incs", .{hexagon_sdk_root}),
        "-I",
        try std.fmt.allocPrint(b.allocator, "{s}/incs/stddef", .{hexagon_sdk_root}),
        "-I",
        try std.fmt.allocPrint(b.allocator, "{s}/libs/qhl_hvx/inc", .{hexagon_sdk_root}),
        "-I",
        try std.fmt.allocPrint(b.allocator, "{s}/libs/qhl/inc", .{hexagon_sdk_root}),
        "-I",
        try std.fmt.allocPrint(b.allocator, "{s}/libs/qhl/inc/qhcomplex", .{hexagon_sdk_root}),
    });

    // Add library paths and libraries
    compile_cmd.addArgs(&[_][]const u8{
        "-L",
        qhl_hvx_dir,
        "-L",
        qhl_dir,
        "-L",
        try std.fmt.allocPrint(b.allocator, "{s}/lib", .{qurt_dir}),
        try std.fmt.allocPrint(b.allocator, "{s}/libqhmath_hvx.a", .{qhl_hvx_dir}),
        try std.fmt.allocPrint(b.allocator, "{s}/libqhblas_hvx.a", .{qhl_hvx_dir}),
        try std.fmt.allocPrint(b.allocator, "{s}/libqhdsp_hvx.a", .{qhl_hvx_dir}),
        try std.fmt.allocPrint(b.allocator, "{s}/libqhcomplex.a", .{qhl_dir}),
        try std.fmt.allocPrint(b.allocator, "{s}/libqhmath.a", .{qhl_dir}),
        "-lc",
        "-lgcc",
    });

    compile_cmd.step.dependOn(&zig_compile.step);

    // Add to default install step
    b.default_step.dependOn(&compile_cmd.step);

    // Run step for QEMU execution
    const run_main_on_hexagon = try std.fmt.allocPrint(
        b.allocator,
        "{s}/libs/run_main_on_hexagon/ship/{s}_{s}/run_main_on_hexagon_sim",
        .{ hexagon_sdk_root, tool_version, arch_option },
    );

    const runelf_path = try std.fmt.allocPrint(
        b.allocator,
        "{s}/sdksim_bin/runelf.pbn",
        .{qurt_dir},
    );

    const qemu_path = try std.fmt.allocPrint(
        b.allocator,
        "{s}/tools/Tools/QEMUHexagon/bin/qemu-system-hexagon",
        .{hexagon_sdk_root},
    );

    const run_cmd = b.addSystemCommand(&[_][]const u8{
        qemu_path,
        "-kernel",
        runelf_path,
        "-append",
    });

    // Get absolute path to the output .so file for QEMU to access
    const absolute_so_path = try b.build_root.join(b.allocator, &[_][]const u8{output_so});

    const append_arg = try std.fmt.allocPrint(
        b.allocator,
        "{s} -- {s}",
        .{ run_main_on_hexagon, absolute_so_path },
    );
    run_cmd.addArg(append_arg);
    run_cmd.step.dependOn(&compile_cmd.step);

    const run_step = b.step("run", "Run the QuRT demo on QEMU");
    run_step.dependOn(&run_cmd.step);
}
