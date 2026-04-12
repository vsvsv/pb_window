# pb_window

A tiny, single-file, cross-platform window creation library for Zig that gives you a
software pixel buffer and gets out of your way.

~1200 LoC in a single `src/pb_window.zig`. No dependencies beyond the system libs
that your OS already ships. That's it.

## What it does

Opens a window. Gives you a raw RGBA8 pixel buffer. Blits it to screen. Handles input.
Does not try to be a "framework". You write pixels, it shows pixels.

Runs on:

- **Linux** (X11 + GLX)
- **macOS** (Cocoa + CoreGraphics, with CVDisplayLink vsync)
- **Windows** (Win32 + WGL, with dark mode support on Win10+)

## Features

- Single-file library, drop `src/pb_window.zig` into your project and go
- Zero third-party dependencies — links only against system libraries (X11/GL on Linux, Cocoa/CoreVideo on macOS, GDI/OpenGL on Windows)
- Keyboard and mouse input with a uniform keycode mapping across all platforms
- Nearest-neighbor or bilinear interpolation for pixel buffer scaling
- Stretch or aspect-ratio-preserving scaling modes, optional window aspect ratio locking
- VSync
- DPI/scaling factor detection
- Set and update window title dynamically
- Can produce small statically-linked executables

## Usage

Add `pb_window` as a Zig package dependency, or just vendor the file.
The minimum Zig version is `0.16.0-dev.2537+52a624244`.

### Linux prerequisites

```
# Debian/Ubuntu
sudo apt install libx11-dev libgl1-mesa-dev

# Other distros: install x11 and opengl dev packages through your package manager
```

### Minimal example

```zig
const PBWindow = @import("pb_window");

pub fn main() !void {
    const W = 256;
    const H = 256;

    // Allocate a pixel buffer (RGBA8, 4 bytes per pixel)
    var pixels: [W * H * 4]u8 = undefined;

    // Fill it with something — a red screen, for instance
    var i: usize = 0;
    while (i < W * H) : (i += 1) {
        pixels[i * 4 + 0] = 200; // R
        pixels[i * 4 + 1] = 30;  // G
        pixels[i * 4 + 2] = 30;  // B
        pixels[i * 4 + 3] = 255; // A
    }

    var window = try PBWindow.init(W * 2, H * 2, "hello", .{});
    defer window.deinit();
    window.setPixelBuffer(&pixels, W, H);

    while (window.update()) {
        // draw stuff into `pixels` here, it will show up on screen
    }
}
```

Window size and pixel buffer size are independent — the library scales the buffer
to fit the window according to the chosen scaling mode.

### Init options

```zig
PBWindow.init(width, height, title, .{
    .resizeable = true,        // allow window resizing
    .vsync = true,             // sync to display refresh rate
    .interp = .nearest,        // .nearest or .bilinear
    .scaling = .keep_aspect,   // .keep_aspect or .stretch
    .lock_aspect = false,      // lock window aspect ratio to buffer aspect ratio
    .bg_color = .{ 0, 0, 0 },  // background color (visible with keep_aspect)
});
```

### Input

Keyboard and mouse state is polled, not event-driven:

```zig
if (window.key_pressed[PBWindow.Keys.escape]) break;
if (window.key_pressed['A']) { /* A is held */ }
if (window.key_pressed[PBWindow.Keys.mouse_left]) { /* left click */ }

const mx = window.mouse_x;
const my = window.mouse_y;
```

## Examples

Look at `src/examples/` for working code, or build and run the demo:

```
zig build run
```

## License

MIT
