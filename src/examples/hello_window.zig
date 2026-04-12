const std = @import("std");
const PBWindow = @import("pb_window");

var prng_seed: u64 = 0;

fn fillWithNoise(pixel_buffer: []u8, width: usize, height: usize) void {
    prng_seed = prng_seed +% 1;
    var prng = std.Random.DefaultPrng.init(prng_seed);
    const rand = prng.random();
    var i: usize = 0;
    while (i < width * height) : (i += 1) {
        pixel_buffer[i * 4 + 0] = rand.int(u8); // R
        pixel_buffer[i * 4 + 1] = rand.int(u8); // G
        pixel_buffer[i * 4 + 2] = rand.int(u8); // B
        pixel_buffer[i * 4 + 3] = 255; // A
    }
}

pub fn main(init: std.process.Init) !void {
    const WIDTH = 128;
    const HEIGHT = 128;

    const pixel_buffer = try init.gpa.alloc(u8, WIDTH * HEIGHT * 4);
    defer init.gpa.free(pixel_buffer);
    fillWithNoise(pixel_buffer, WIDTH, HEIGHT);

    var window = try PBWindow.init(WIDTH * 4, HEIGHT * 4, "PBWindow Demo", .{});
    defer window.deinit();
    window.setPixelBuffer(pixel_buffer, WIDTH, HEIGHT);

    while (window.update()) {
        fillWithNoise(pixel_buffer, WIDTH, HEIGHT);
    }
}
