//For some reason, emscription has no way to set a custom entry point.
// Emscription can't find any functions defined by Zig that can be used as an entry point.
// But, by adding this C source file into the mix, there is an entry point that emscription can find and use.
// TODO: if emscripten adds the ability to set a custom entry point, 
// remove this hack and set Emscripten's entry point to app.run()
//#include "zig.h"
/*zig_*/extern int run(void);

int main(int argc, char** argv)
{
    return run();
}