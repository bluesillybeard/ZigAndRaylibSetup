# Setup with Zig and Raylib

Using Zig and Raylib together is nothing new.<br>
However, what they often don't do us support web, which was the main purpose of this.<br>
This is a proof of concept, the code that makes it work is pretty hacky at times. <br>

Zig is supposedly going to properly support web builds using emscripten in the future, as suggested [here]()


## How to build

The project builds and runs like any other zig project <br>
```bash
zig build run
```

However, if you want a web build, things get a bit more complicated
```bash
zig build run -Dtarget=wasm32-emscripten --sysroot [path to emsdk]/upstream/emscripten
```
the `--sysroot` is required since emscripten itself is required separately from Zig's webassembly compiler.

Once the project has finished building, it can be found in 'zig-out/bin/applicationhtml/'

