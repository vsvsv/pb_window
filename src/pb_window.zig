//! Bare minimum cross-platform optionated window creation.
const std = @import("std");

const builtin = @import("builtin");
const os_tag = builtin.os.tag;
pub const c = switch (os_tag) {
    .windows => @cImport({
        @cDefine("WIN32_LEAN_AND_MEAN", "1");
        @cInclude("windows.h");
        @cInclude("wingdi.h");
        @cInclude("GL/gl.h");
        if (builtin.os.isAtLeast(.windows, .win10) orelse false) {
            @cInclude("dwmapi.h");
        }
    }),
    .macos => {
        // No need to include anything, all external function signatures is defined manually in `objc` namespace.
    },
    .linux => @cImport({
        // On Linux, `libx11` and `libgl` libraries are needed for accessing X11 and OpenGL API.
        // They can be installed by `sudo apt install libx11-dev libgl1-mesa-dev` on Debian-based distros.
        // On other distributions, search for `x11` and `opengl` packages with your package manager of choice.
        @cInclude("X11/XKBlib.h");
        @cInclude("X11/Xlib.h");
        @cInclude("X11/keysym.h");
        @cInclude("X11/Xutil.h");
        @cInclude("GL/gl.h");
        @cInclude("GL/glx.h");
    }),
    else => @compileError(std.fmt.comptimePrint(
        "pb_window.zig does not support platform \"{s}\" yet\n",
        .{@tagName(os_tag)},
    )),
};

// --- Root struct fields ---

const PBWindow = @This();

/// Native window handle pointer
handle: if (os_tag == .linux) *anyopaque else *align(4) anyopaque,
width: f64,
height: f64,
scaling_factor: f64 = 1,

/// State of the keyboard and mouse keys.
/// Keycode index for regular characters is just their ASCII value:
/// '"' -> quote key (34); '\'' -> single quote/apostrophe key (39).
/// ',' -> comma (44); '-' -> minus key (45); '.' -> dot (46); '/' -> forward slash key (47).
/// '0..9' -> Number keys 0..9 (corresponds to ASCII codes 48..57).
/// ';' -> semicolon key (59); '=' -> equals/plus key (61); 'A..Z' -> Keys A..Z (NOTE: 'a..z' is not supported).
/// '[' -> open bracket (91); '\' -> backslash(92); ']' -> close bracket (93); '`' backtick/tilde (96).
///
/// For modifier/special keys see `PBWindow.Keys` struct.
/// `const is_shift_pressed = window.key_pressed[PBWindow.Keys.shift];`
/// `const is_a_pressed = window.key_pressed['A'];`
key_pressed: [128]bool = std.mem.zeroes([128]bool),
mouse_x: f32 = 0,
mouse_y: f32 = 0,

interp: enum { nearest, bilinear },
scaling: enum { stretch, keep_aspect },
bg_color: [3]f64,
lock_aspect: bool,
vsync: bool = true,

platform: switch (os_tag) {
    .windows => struct {
        title: [512]u8 = undefined,
        title_utf16: [512]u16 = undefined,
        dev_ctx: c.HDC = null,
        gl_ctx: c.HGLRC = null,
        texture_id: c.GLuint = 0,
        prev_vsync_val: bool = false,
    },
    .macos => struct {
        display_link: objc.CVDisplayLinkRef = null,
        vsync_mutex: std.Thread.Mutex = .{},
        vsync_cond: std.Thread.Condition = .{},
        frame_ready: bool = false,
        previous_modifier_flags: objc.NSUInteger = 0,
        close_requested: bool = false,
    },
    .linux => struct {
        display: *c.struct__XDisplay = undefined,
        gl_ctx: c.GLXContext = null,
        texture_id: c.GLuint = 0,
        prev_vsync_val: bool = false,
        last_title_update: i64 = 0,
        glXSwapIntervalEXT: ?GlSetVsyncFn = null,
        const GlSetVsyncFn = *const fn (dpy: *c.Display, d: c.GLXDrawable, interval: c_int) callconv(.C) void;
    },
    else => @compileError(STR_UNIMPLEMENTED),
} = .{},
internal: struct {
    buffer: ?[]const u8 = null,
    buf_width: usize = 0,
    buf_height: usize = 0,
    buf_aspect: f64 = 0,
} = .{},

/// Mimial Objective-C FFI
const objc = if (os_tag != .macos) void else struct {
    pub const id = ?*align(@alignOf(usize)) anyopaque;
    pub const Class = ?*align(@alignOf(usize)) anyopaque;
    pub const SEL = ?*align(@alignOf(usize)) anyopaque;
    pub const BOOL = i8;
    pub const YES: BOOL = 1;
    pub const NO: BOOL = 0;
    pub const NSUInteger = usize;
    pub const NSInteger = isize;

    pub const CGFloat = f64;
    pub const CGPoint = extern struct { x: CGFloat, y: CGFloat };
    pub const CGSize = extern struct { width: CGFloat, height: CGFloat };
    pub const CGRect = extern struct { origin: CGPoint, size: CGSize };
    pub const CGContextRef = *anyopaque;
    pub const CGImageRef = *anyopaque;
    pub const CGColorSpaceRef = *anyopaque;
    pub const CGDataProviderRef = *anyopaque;
    pub const CVDisplayLinkRef = ?*anyopaque;

    pub extern const NSApp: id;
    pub extern const NSDefaultRunLoopMode: id;
    pub extern const NSEventTrackingRunLoopMode: id;

    pub extern "CoreGraphics" fn CGContextSetInterpolationQuality(c: CGContextRef, quality: i32) void;
    pub extern "CoreGraphics" fn CGColorSpaceCreateDeviceRGB() ?CGColorSpaceRef;
    pub extern "CoreGraphics" fn CGDataProviderCreateWithData(
        info: ?*anyopaque,
        data: ?*const anyopaque,
        size: usize,
        releaseData: ?*const fn (?*anyopaque, ?*const anyopaque, usize) callconv(.c) void,
    ) ?CGDataProviderRef;
    pub extern "CoreGraphics" fn CGImageCreate(
        width: usize,
        height: usize,
        bitsPerComponent: usize,
        bitsPerPixel: usize,
        bytesPerRow: usize,
        space: ?CGColorSpaceRef,
        bitmapInfo: u32,
        provider: ?CGDataProviderRef,
        decode: ?*const CGFloat,
        shouldInterpolate: bool,
        intent: i32,
    ) ?CGImageRef;
    pub extern "CoreGraphics" fn CGColorSpaceRelease(space: ?CGColorSpaceRef) void;
    pub extern "CoreGraphics" fn CGDataProviderRelease(provider: ?CGDataProviderRef) void;
    pub extern "CoreGraphics" fn CGImageRelease(image: ?CGImageRef) void;
    pub extern "CoreGraphics" fn CGContextSetRGBFillColor(
        c: CGContextRef,
        red: CGFloat,
        green: CGFloat,
        blue: CGFloat,
        alpha: CGFloat,
    ) void;
    pub extern "CoreGraphics" fn CGContextFillRect(c: CGContextRef, rect: CGRect) void;
    pub extern "CoreGraphics" fn CGContextDrawImage(c: CGContextRef, rect: CGRect, image: ?CGImageRef) void;

    pub extern "CoreVideo" fn CVDisplayLinkCreateWithActiveCGDisplays(displayLinkOut: *CVDisplayLinkRef) i32;
    pub extern "CoreVideo" fn CVDisplayLinkSetOutputCallback(
        displayLink: CVDisplayLinkRef,
        callback: *const anyopaque,
        userInfo: ?*anyopaque,
    ) i32;
    pub extern "CoreVideo" fn CVDisplayLinkStart(displayLink: CVDisplayLinkRef) i32;
    pub extern "CoreVideo" fn CVDisplayLinkStop(displayLink: CVDisplayLinkRef) i32;
    pub extern "CoreVideo" fn CVDisplayLinkRelease(displayLink: CVDisplayLinkRef) void;

    pub inline fn CGRectMake(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) CGRect {
        return .{ .origin = .{ .x = x, .y = y }, .size = .{ .width = width, .height = height } };
    }
    pub inline fn CGSizeMake(width: CGFloat, height: CGFloat) CGSize {
        return .{ .width = width, .height = height };
    }

    extern "objc" fn objc_msgSend() void;
    extern "objc" fn sel_getUid(str: [*c]const u8) SEL;
    pub fn msg(target: objc.id, comptime ReturnType: type, selector: [:0]const u8, args: anytype) ReturnType {
        const argsInfo = @typeInfo(@TypeOf(args)).@"struct";
        std.debug.assert(argsInfo.is_tuple);

        const ObjcFn = @Fn(
            params: {
                var acc: [argsInfo.fields.len + 2]type = undefined;
                acc[0] = id;
                acc[1] = SEL;
                for (argsInfo.fields, 0..) |field, i| {
                    acc[i + 2] = field.type;
                }
                break :params &acc;
            },
            &@splat(.{}),
            ReturnType,
            .{ .@"callconv" = .c },
        );
        const msg_send_ptr: *const ObjcFn = @ptrCast(&objc_msgSend);
        return @call(.auto, msg_send_ptr, .{ target, sel_getUid(selector.ptr) } ++ args);
    }

    extern "objc" fn objc_getClass(name: [*c]const u8) Class;
    pub inline fn cls(name: [:0]const u8) id {
        return @ptrCast(@alignCast(objc_getClass(name)));
    }

    pub inline fn alloc(class: anytype, selector: [:0]const u8, args: anytype) id {
        return objc.msg(objc.msg(@ptrCast(@alignCast(class)), id, "alloc", .{}), id, selector, args);
    }

    extern "objc" fn objc_allocateClassPair(super: Class, name: [*c]const u8, extraBytes: usize) Class;
    pub inline fn allocateClassPair(super: [:0]const u8, new_class_name: [:0]const u8) Class {
        return objc_allocateClassPair(@ptrCast(objc.cls(super)), new_class_name, 0);
    }

    pub const registerClassPair = @extern(*const fn (class: Class) callconv(.c) void, .{
        .name = "objc_registerClassPair",
    });

    extern "objc" fn objc_setAssociatedObject(obj: id, key: *const anyopaque, value: id, policy: usize) void;
    pub inline fn setAssociatedObject(obj: id, key: *const anyopaque, val: id) void {
        objc_setAssociatedObject(obj, key, val, 0); // 0 == OBJC_ASSOCIATION_ASSIGN
    }

    extern "objc" fn objc_getAssociatedObject(object: id, key: *const anyopaque) id;
    pub inline fn getAssociatedObject(ReturnType: type, obj: id, key: *const anyopaque) ReturnType {
        return @ptrCast(objc_getAssociatedObject(obj, key));
    }

    extern "objc" fn class_addMethod(cls: Class, name: SEL, imp: *const anyopaque, types: [*c]const u8) BOOL;
    pub inline fn addMethod(class: Class, name: [*c]const u8, imp: *const anyopaque, types: [*c]const u8) BOOL {
        return class_addMethod(class, sel_getUid(name), imp, types);
    }
};
