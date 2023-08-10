const std = @import("std");

const BuildError = error{
    RaylibBuildError,
};
pub fn build(b: *std.Build) !void {
    const allocator = b.allocator;
    const stdout = std.io.getStdOut().writer();
    //get the working directory
    var workingDirectory = std.fs.cwd();
    //defer workingDirectory.close();
    //print it for debugging purposes.
    var outBuffer: [std.fs.MAX_PATH_BYTES]u8 = .{};
    const dir = try workingDirectory.realpath(".", &outBuffer);
    try stdout.print("Working directory: {s}\n", .{dir});

    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    //There's probably a "proper" way to import a library from a build.zig file,
    // but Zig's build system lacks ANY kind of decent documentation AT ALL
    // and I can't for the life of me find a proper way to do this.
    //So what I do instead is build raylib, then link the static library with the app.

    //First, build raylib.
    var raylibDir = try workingDirectory.openDir("raylib", std.fs.Dir.OpenDirOptions{});
    //Note that this makes workingDirectoryStr invalid
    const raylibDirStr = try raylibDir.realpath(".", &outBuffer);
    defer raylibDir.close();

    //two of the arguments need to be built separately
    // idk if this is the best way to do it in Zig.
    const targetStr = try target.allocDescription(allocator);
    defer allocator.free(targetStr);
    //build the argument strings - there's probably a better way to do this but I don't really care tbh
    var targetArgument = try allocator.alloc(u8, "-Dtarget=".len + targetStr.len);
    defer allocator.free(targetArgument);
    targetArgument = try std.fmt.bufPrint(targetArgument, "-Dtarget={s}", .{targetStr});
    //Always build Raylib in fast release, since it's stable and doesn't really need to be the same as our program.
    // The code that builds the argument to match is commented below
    const optimizeArgument = "-Doptimize=ReleaseFast";
    // const optimizeArgument = switch (optimize) {
    //     .Debug => "-Dtarget=Debug",
    //     .ReleaseSafe => "-Dtarget=ReleaseSafe",
    //     .ReleaseFast => "-Dtarget=ReleaseFast",
    //     .ReleaseSmall => "-Dtarget=ReleaseSmall",
    // };
    //If we are using emscripten, then we need to use emscripten's sysroot
    var argv: []const []const u8 = &[_][]const u8{ "zig", "build", targetArgument, optimizeArgument };
    if (target.getOsTag() == .emscripten) {
        if (b.sysroot == null) {
            @panic("Pass '--sysroot \"[path to emsdk installation]/upstream/emscripten\"'");
        }
        argv = &[_][]const u8{ "zig", "build", targetArgument, optimizeArgument, "--sysroot", b.sysroot.? };
    }
    try stdout.print("Running command \"", .{});
    for (0..argv.len) |i| {
        try stdout.print("{s} ", .{argv[i]});
    }
    try stdout.print("\" in folder {s}\n", .{raylibDirStr});
    const result = try std.ChildProcess.exec(.{
        .allocator = allocator,
        .argv = argv,
        .cwd_dir = raylibDir,
        .max_output_bytes = 50 * 1024,
    });
    if (result.stdout.len > 0) try stdout.print("raylib build output:\"\n{s}\"\n", .{result.stdout});
    if (result.stderr.len > 0) try stdout.print("raylib build errors:\"\n{s}\"\n", .{result.stderr});
    if (result.stderr.len > 0) {
        return BuildError.RaylibBuildError;
    }
    if (target.getOsTag() == .emscripten) {
        //if we are building for webassembly,
        // things need to be done differently
        // since Zig and Emscripten are a work on progress.
        try BuildExeEmscripten(b, target, optimize);
        return;
    }
    try BuildExeNonEmscripten(b, target, optimize);
}
fn BuildExeNonEmscripten(b: *std.Build, target: std.zig.CrossTarget, optimize: std.builtin.OptimizeMode) !void {
    const exe = b.addExecutable(.{
        .name = "application",
        .root_source_file = .{ .path = "app/app.zig" },
        .target = target,
        .optimize = optimize,
    });
    //Raylib uses libc so we need libc as well
    exe.linkLibC();
    //Raylib also uses some system libraries.
    // If you're building on the same platform you're targeting,
    // It will work without this,
    // but it's a bit of a trick that it works
    // since zig can link our program to installed system libraries anyway.
    switch (target.getOsTag()) {
        .windows => {
            exe.linkSystemLibrary("winmm");
            exe.linkSystemLibrary("gdi32");
            exe.linkSystemLibrary("opengl32");
        },
        .linux => {
            exe.linkSystemLibrary("GL");
            exe.linkSystemLibrary("rt");
            exe.linkSystemLibrary("dl");
            exe.linkSystemLibrary("m");
            exe.linkSystemLibrary("X11");
        },
        .freebsd, .openbsd, .netbsd, .dragonfly => {
            exe.linkSystemLibrary("GL");
            exe.linkSystemLibrary("rt");
            exe.linkSystemLibrary("dl");
            exe.linkSystemLibrary("m");
            exe.linkSystemLibrary("X11");
            exe.linkSystemLibrary("Xrandr");
            exe.linkSystemLibrary("Xinerama");
            exe.linkSystemLibrary("Xi");
            exe.linkSystemLibrary("Xxf86vm");
            exe.linkSystemLibrary("Xcursor");
        },
        .macos => {
            exe.linkFramework("Foundation");
            exe.linkFramework("CoreServices");
            exe.linkFramework("CoreGraphics");
            exe.linkFramework("AppKit");
            exe.linkFramework("IOKit");
        },
        //Emscripten is handled separately
        else => {
            @panic("Unsupported OS");
        },
    }
    //actually link with Raylib
    exe.addObjectFile(.{
        .path = switch (target.getOsTag()) {
            .windows => "raylib/zig-out/lib/raylib.lib",
            .linux => "raylib/zig-out/lib/libraylib.a",
            .macos => "raylib/zig-out/lib/libraylib.a",
            //emscripten is handled separately
            else => @panic("Unsupported OS"),
        },
    });
    //So we can include Raylib headers to actually call functions
    exe.addIncludePath(.{ .path = "raylib/zig-out/include" });
    b.installArtifact(exe);
}
fn BuildExeEmscripten(b: *std.Build, target: std.zig.CrossTarget, optimize: std.builtin.OptimizeMode) !void {
    //Zig doesn't build emscripten executables properly,
    // So as a workaround, build a "library" out of the project
    // then manually link it into an executable using emscripten

    //According to this issue https://github.com/ziglang/zig/issues/10836
    // They will be properly supporting emscripten in the future.
    // Which will make all this work for nothing,
    // But it's ok because it means I don't have to maintain this mess.
    //this is our "library" that will later be linked into an executable with Emscripten

    //zig building to emscripten doesn't really work,
    // So we build to wasi instead.
    const newTarget = std.zig.CrossTarget{
        .cpu_arch = target.cpu_arch,
        .cpu_model = target.cpu_model,
        .cpu_features_add = target.cpu_features_add,
        .cpu_features_sub = target.cpu_features_sub,
        .os_tag = .wasi,
        .os_version_min = target.os_version_min,
        .os_version_max = target.os_version_max,
        .glibc_version = target.glibc_version,
        .abi = target.abi,
        .dynamic_linker = target.dynamic_linker,
        .ofmt = target.ofmt,
    };
    const appLib = b.addStaticLibrary(.{
        .name = "application",
        .root_source_file = .{ .path = "app/app.zig" },
        .target = newTarget,
        .optimize = optimize,
    });
    //appLib.addCSourceFile("app/entryPoint.c", &[_][]const u8{});
    //Raylib uses libc so we need libc as well
    appLib.linkLibC();
    //actually link with Raylib
    appLib.addObjectFile(.{ .path = "raylib/zig-out/lib/libraylib.a" });
    //So we can include Raylib headers to actually call functions
    appLib.addIncludePath(.{ .path = "raylib/zig-out/include" });
    b.installArtifact(appLib);

    //We need to make sure the user has set the sysroot directory to the correct value.
    // Raylib already does this, and so does earlier in the build file,
    // but may as well check it again.
    if (b.sysroot == null) {
        @panic("Pass '--sysroot \"[path to emsdk installation]/upstream/emscripten\"'");
    }
    //It's worth noting that emcc is actually a shell script that runs a python file.
    var emccRunArg = try b.allocator.alloc(u8, 2 + b.sysroot.?.len + 5);
    defer b.allocator.free(emccRunArg);
    emccRunArg = try std.fmt.bufPrint(emccRunArg, "{s}/emcc", .{b.sysroot.?});

    //Emscription is utterly incapible of finding Zig's entry point.
    // However, by creating an external function in our app.zig file that runs the main function,
    // then creating a .c file that calls that function, compiling it separately and linking it later,
    // that problem can be fixed.
    const compileEntrypoint = b.addSystemCommand(&[_][]const u8{ emccRunArg, "-c", "entryPoint.c", "-o", "zig-out/bin/entrypoint.o" });
    compileEntrypoint.step.dependOn(&appLib.step);
    //We need to make the output directory
    // because emcc isn't smart enough to create it itself.
    try std.fs.cwd().makePath("zig-out/bin/applicationhtml");
    //                                                             emcc    zig-out/lib/libapplication.a    raylib/zig-out/lib/libraylib.a    -o    zig-out/bin/applicationhtml/index.html    -s FULL_ES3=1    -s    USE_GLFW=3    -s    ASYNCIFY    -s    STANDALONE_WASM    -s    EXPORTED_FUNCTIONS=_run    --no-entry    -O3
    const linkWithEmscripten = b.addSystemCommand(&[_][]const u8{ emccRunArg, "zig-out/bin/entrypoint.o", "zig-out/lib/libapplication.a", "raylib/zig-out/lib/libraylib.a", "-o", "zig-out/bin/applicationhtml/index.html", "-sFULL-ES3=1", "-sUSE_GLFW=3", "-sASYNCIFY", "-sSTANDALONE_WASM", "-sEXPORTED_FUNCTIONS=_run", "-O3" });
    //The app needs to be build first before we can call emcc.
    linkWithEmscripten.step.dependOn(&compileEntrypoint.step);
    b.getInstallStep().dependOn(&linkWithEmscripten.step);
}
