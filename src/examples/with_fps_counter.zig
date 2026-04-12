const std = @import("std");
const PBWindow = @import("pb_window");

/// Simple FPS counter.
/// Call `tick()` every cycle inside update loop to count. Current FPS will be stored in `fps` field.
/// Set `.enable_debug_log = true` to enable logging current FPS to stdout.
pub const FrameCounter = struct {
    const Self = @This();

    last_frame_time: ?u64 = null,
    current_frame_count: usize = 0,
    fps: usize = 0,
    enable_debug_log: bool = false,

    /// Updates counter stats. Should be called every frame.
    pub fn tick(self: *Self) void {
        var t_io = std.Io.Threaded.init_single_threaded;
        const now: u64 = @intCast(std.Io.Clock.awake.now(t_io.ioBasic()).toNanoseconds());
        if (self.last_frame_time == null) {
            self.last_frame_time = now;
            return;
        }
        var should_log = false;
        const delta_ns = now - self.last_frame_time.?;
        if (delta_ns >= std.time.ns_per_s) {
            self.fps = @divFloor(
                self.current_frame_count,
                @as(usize, @intCast(@divFloor(delta_ns, std.time.ns_per_s))),
            );
            self.current_frame_count = 0;
            self.last_frame_time = now;
            should_log = true;
        } else self.current_frame_count += 1;
        if (self.enable_debug_log and should_log) {
            std.log.debug("{d} fps", .{self.fps});
        }
    }
};

var prng_seed: u64 = 0;

fn fillWithNoise(pixel_buffer: []u8, width: usize, height: usize) void {
    prng_seed = prng_seed +% 1;
    var prng = std.Random.DefaultPrng.init(prng_seed);
    const rand = prng.random();
    var i: usize = 0;
    while (i < width * height) : (i += 1) {
        const base = i * 4;
        pixel_buffer[base + 0] = rand.int(u8); // R
        pixel_buffer[base + 1] = rand.int(u8); // G
        pixel_buffer[base + 2] = rand.int(u8); // B
        pixel_buffer[base + 3] = 255; // A
    }
}

pub fn main(init: std.process.Init) !void {
    const WIDTH = 128;
    const HEIGHT = 128;

    const pixel_buffer = try init.gpa.alloc(u8, WIDTH * HEIGHT * 4);
    defer init.gpa.free(pixel_buffer);
    fillWithNoise(pixel_buffer, WIDTH, HEIGHT);

    var window = try PBWindow.init(WIDTH * 4, HEIGHT * 4, "PBWindow Demo", .{
        .vsync = false, // Run at maximum speed to see how many fps is possible.
        // TIP: run with `zig build run -Doptimize=ReleaseFast` to measure maximum fps with all the optimisations
    });
    defer window.deinit();

    window.setPixelBuffer(pixel_buffer, WIDTH, HEIGHT);

    var counter = FrameCounter{ .enable_debug_log = true };
    var title_buf = [_]u8{0} ** 256;
    while (window.update()) {
        window.updateTitle(try std.fmt.bufPrintZ(&title_buf, "PBWindow Demo — {d:.2} fps", .{counter.fps}));
        fillWithNoise(pixel_buffer, WIDTH, HEIGHT);
        counter.tick();
    }
}
