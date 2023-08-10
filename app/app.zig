const std = @import("std");
const raylib = @cImport({
    @cInclude("raylib.h");
});

//This is so the app can be run with emscripten.
// see ../entryPoint.c
export fn run() c_int {
    main() catch {
        return -1;
    };
    return 0;
}

pub fn main() !void {

    // Initialization
    //--------------------------------------------------------------------------------------
    const screenWidth = 800;
    const screenHeight = 450;

    raylib.InitWindow(screenWidth, screenHeight, "Zig + Raylib + Web = Fun!");

    raylib.SetTargetFPS(60); // Set our game to run at 60 frames-per-second
    //--------------------------------------------------------------------------------------

    // Main game loop
    while (!raylib.WindowShouldClose()) // Detect window close button or ESC key
    {
        // Update
        //----------------------------------------------------------------------------------
        // TODO: Update your variables here
        //----------------------------------------------------------------------------------

        // Draw
        //----------------------------------------------------------------------------------
        raylib.BeginDrawing();
        raylib.DrawText("your codebase are belong to us", 10, 10, 50, raylib.WHITE);
        raylib.EndDrawing();
        //----------------------------------------------------------------------------------
    }

    // De-Initialization
    //--------------------------------------------------------------------------------------
    raylib.CloseWindow(); // Close window and OpenGL context
    //--------------------------------------------------------------------------------------
}
