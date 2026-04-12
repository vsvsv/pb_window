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
    else => @compileError(ERROR_STR_UNIMPLEMENTED),
};

const ERROR_STR_UNIMPLEMENTED = std.fmt.comptimePrint(
    "PBWindow does not support platform \"{s}\" yet\n",
    .{@tagName(os_tag)},
);

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

/// OS-specific native API fields
const PlatformNativeData = switch (os_tag) {
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
        vsync_mutex: std.Io.Mutex = .init,
        vsync_cond: std.Io.Condition = .init,
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
    else => @compileError(ERROR_STR_UNIMPLEMENTED),
};

/// Special/modifier key codes.
/// All keys are named according to the standard 101-key US keyboard layout.
/// See the picture at section 1.1.2: https://www.w3.org/TR/2015/WD-uievents-code-20151215
pub const Keys = struct {
    pub const mouse_left: u8 = 0;
    pub const mouse_right: u8 = 1;
    pub const mouse_middle: u8 = 2;
    pub const arrow_up: u8 = 3;
    pub const arrow_down: u8 = 4;
    pub const arrow_left: u8 = 5;
    pub const arrow_right: u8 = 6;
    pub const super: u8 = 7;
    pub const backspace: u8 = 8;
    pub const tab: u8 = 9;
    pub const delete: u8 = 10;
    pub const control_l: u8 = 11;
    pub const control_r: u8 = 12;
    pub const enter: u8 = 13;
    pub const shift_l: u8 = 14;
    pub const shift_r: u8 = 15;
    pub const alt_l: u8 = 16;
    pub const alt_r: u8 = 17;
    pub const menu: u8 = 18;
    pub const pause_break: u8 = 19;
    pub const caps_lock: u8 = 20;
    pub const insert: u8 = 21;
    pub const home: u8 = 22;
    pub const end: u8 = 23;
    pub const page_up: u8 = 24;
    pub const page_down: u8 = 25;
    pub const print_screen: u8 = 26;
    pub const escape: u8 = 27;
    pub const space: u8 = 32;
    pub const f1: u8 = 101;
    pub const f2: u8 = 102;
    pub const f3: u8 = 103;
    pub const f4: u8 = 104;
    pub const f5: u8 = 105;
    pub const f6: u8 = 106;
    pub const f7: u8 = 107;
    pub const f8: u8 = 108;
    pub const f9: u8 = 109;
    pub const f10: u8 = 110;
    pub const f11: u8 = 111;
    pub const f12: u8 = 112;
    pub const unknown: u8 = 127;

    pub fn mapPlatformKeycode(key_code: u64) u8 {
        return switch (os_tag) { // zig fmt: off
        .windows => switch (key_code) {
            0x00B => '0', 0x002 => '1', 0x003 => '2', 0x004 => '3', 0x005 => '4', 0x006 => '5', 0x007 => '6',
            0x008 => '7', 0x009 => '8', 0x00A => '9', 0x01E => 'A', 0x030 => 'B', 0x02E => 'C', 0x020 => 'D',
            0x012 => 'E',0x021 => 'F', 0x022 => 'G', 0x023 => 'H', 0x017 => 'I', 0x024 => 'J', 0x025 => 'K',
            0x026 => 'L', 0x032 => 'M', 0x031 => 'N', 0x018 => 'O', 0x019 => 'P', 0x010 => 'Q', 0x013 => 'R',
            0x01F => 'S', 0x014 => 'T', 0x016 => 'U', 0x02F => 'V', 0x011 => 'W', 0x02D => 'X', 0x015 => 'Y',
            0x02C => 'Z', 0x028 => '\'', 0x02B => '\\', 0x033 => ',', 0x00D => '=', 0x029 => '`', 0x01A => '[',
            0x00C => '-', 0x034 => '.', 0x01B => ']', 0x027 => ';', 0x035 => '/',
            0x01C => Keys.enter, 0x001 => Keys.escape, 0x153 => Keys.delete, 0x039 => Keys.space,
            0x00E => Keys.backspace, 0x00F => Keys.tab, 0x03A => Keys.caps_lock,
            0x147 => Keys.home, 0x14F => Keys.end, 0x152 => Keys.insert, 0x15D => Keys.menu,
            0x151 => Keys.page_down, 0x149 => Keys.page_up, 0x045 => Keys.pause_break,
            0x03B => Keys.f1, 0x03C => Keys.f2, 0x03D => Keys.f3, 0x03E => Keys.f4,
            0x03F => Keys.f5, 0x040 => Keys.f6, 0x041 => Keys.f7, 0x042 => Keys.f8,
            0x043 => Keys.f9, 0x044 => Keys.f10, 0x057 => Keys.f11, 0x058 => Keys.f12,
            0x137 => Keys.print_screen, 0x02A => Keys.shift_l, 0x036 => Keys.shift_r,
            0x138 => Keys.alt_r, 0x038 => Keys.alt_l,0x15C => Keys.super, 0x15B => Keys.super,
            0x150 => Keys.arrow_down, 0x148 => Keys.arrow_up, 0x11D => Keys.control_r,
            0x14B => Keys.arrow_left, 0x14D => Keys.arrow_right, 0x01D => Keys.control_l,
            else => Keys.unknown
        },
        .macos => switch (key_code) {
            0x1D => '0', 0x12 => '1', 0x13 => '2', 0x14 => '3', 0x15 => '4', 0x17 => '5', 0x16 => '6',
            0x1A => '7', 0x1C => '8',0x19 => '9', 0x00 => 'A', 0x0B => 'B', 0x08 => 'C', 0x02 => 'D',
            0x0E => 'E',0x03 => 'F', 0x05 => 'G', 0x04 => 'H', 0x22 => 'I', 0x26 => 'J', 0x28 => 'K',
            0x25 => 'L', 0x2E => 'M', 0x2D => 'N', 0x1F => 'O', 0x23 => 'P', 0x0C => 'Q', 0x0F => 'R',
            0x01 => 'S', 0x11 => 'T', 0x20 => 'U', 0x09 => 'V', 0x0D => 'W', 0x07 => 'X', 0x10 => 'Y',
            0x06 => 'Z', 0x27 => '\'', 0x2A => '\\', 0x2B => ',', 0x18 => '=', 0x32 => '`', 0x21 => '[',
            0x1B => '-', 0x2F => '.', 0x1E => ']', 0x29 => ';', 0x2C => '/',
            0x24 => Keys.enter, 0x35 => Keys.escape, 0x75 => Keys.delete,
            0x33 => Keys.backspace, 0x39 => Keys.caps_lock, 0x31 => Keys.space, 0x30 => Keys.tab,
            0x3A => Keys.alt_l, 0x3D => Keys.alt_r, 0x38 => Keys.shift_l, 0x3C => Keys.shift_r,
            0x7D => Keys.arrow_down, 0x7E => Keys.arrow_up, 0x3B => Keys.control_l,
            0x7B => Keys.arrow_left, 0x7C => Keys.arrow_right, 0x3E => Keys.control_r,
            0x7A => Keys.f1, 0x78 => Keys.f2, 0x63 => Keys.f3, 0x76 => Keys.f4, 0x60 => Keys.f5,
            0x61 => Keys.f6, 0x62 => Keys.f7, 0x64 => Keys.f8, 0x65 => Keys.f9, 0x6D => Keys.f10,
            0x67 => Keys.f11, 0x6F => Keys.f12, 0x73 => Keys.home, 0x77 => Keys.end,
            0x72 => Keys.insert, 0x79 => Keys.page_down, 0x74 => Keys.page_up,
            0x69 => Keys.print_screen, 0x6E => Keys.menu, 0x36 => Keys.super, 0x37 => Keys.super,
            else => Keys.unknown,
        },
        .linux => switch (key_code) {
            c.XK_0 => '0', c.XK_1 => '1', c.XK_2 => '2', c.XK_3 => '3', c.XK_4 => '4', c.XK_5 => '5',
            c.XK_6 => '6', c.XK_7 => '7', c.XK_8 => '8', c.XK_9 => '9', c.XK_A => 'A', c.XK_B => 'B',
            c.XK_C => 'C', c.XK_D => 'D', c.XK_E => 'E', c.XK_F => 'F', c.XK_G => 'G', c.XK_H => 'H',
            c.XK_I => 'I', c.XK_J => 'J', c.XK_K => 'K', c.XK_L => 'L', c.XK_M => 'M', c.XK_N => 'N',
            c.XK_O => 'O', c.XK_P => 'P', c.XK_Q => 'Q', c.XK_R => 'R', c.XK_S => 'S', c.XK_T => 'T',
            c.XK_U => 'U', c.XK_V => 'V', c.XK_W => 'W', c.XK_X => 'X', c.XK_Y => 'Y', c.XK_Z => 'Z',
            c.XK_apostrophe => '\'', c.XK_backslash => '\\', c.XK_comma => ',', c.XK_equal => '=',
            c.XK_grave => '`', c.XK_bracketleft => '[', c.XK_minus => '-', c.XK_period => '.',
            c.XK_bracketright => ']', c.XK_semicolon => ';', c.XK_slash => '/',
            c.XK_Escape => Keys.escape, c.XK_Tab => Keys.tab, c.XK_BackSpace => Keys.backspace,
            c.XK_Return => Keys.enter, c.XK_Delete => Keys.delete, c.XK_Home => Keys.home, c.XK_End => Keys.end,
            c.XK_Page_Up => Keys.page_up, c.XK_Page_Down => Keys.page_down, c.XK_Caps_Lock => Keys.caps_lock,
            c.XK_Scroll_Lock => Keys.caps_lock, c.XK_Pause => Keys.pause_break, c.XK_Print => Keys.print_screen,
            c.XK_Menu => Keys.menu, c.XK_Insert => Keys.insert, c.XK_space => Keys.space,
            c.XK_Alt_L => Keys.alt_l, c.XK_Alt_R => Keys.alt_r, c.XK_Super_L => Keys.super,
            c.XK_Control_L => Keys.control_l, c.XK_Control_R => Keys.control_r, c.XK_Super_R => Keys.super,
            c.XK_Shift_L => Keys.shift_l, c.XK_Shift_R => Keys.shift_r,
            c.XK_Up => Keys.arrow_up, c.XK_Down => Keys.arrow_down,
            c.XK_Left => Keys.arrow_left, c.XK_Right => Keys.arrow_right,
            c.XK_F1 => Keys.f1, c.XK_F2 => Keys.f2, c.XK_F3 => Keys.f3, c.XK_F4 => Keys.f4,
            c.XK_F5 => Keys.f5, c.XK_F6 => Keys.f6, c.XK_F7 => Keys.f7, c.XK_F8 => Keys.f8,
            c.XK_F9 => Keys.f9, c.XK_F10 => Keys.f10, c.XK_F11 => Keys.f11, c.XK_F12 => Keys.f12,
            else => Keys.unknown,
        },
        else => @compileError(ERROR_STR_UNIMPLEMENTED),
        };
    } // zig fmt: on
};

//////////////////////////////////////
//     PBWindow struct fields
//////////////////////////////////////

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
/// Pixel buffer interpolation mode
interp: enum { nearest, bilinear },
/// Scaling mode:
/// * `stretch` -- stretch the pixel buffer to fill the window
/// * `keep_aspect` -- keep original aspect ratio of the pixel buffer (adds vertical or horizontal bars)
scaling: enum { stretch, keep_aspect },
/// Background color of the window (will be used if `scaling == .keep_aspect`)
bg_color: [3]f64,
/// Lock the aspect ratio of the window when resizing
lock_aspect: bool,
vsync: bool = true,
allocator: std.mem.Allocator,
platform: PlatformNativeData = .{},
__internal: struct {
    buffer: ?[]const u8 = null,
    buf_width: usize = 0,
    buf_height: usize = 0,
    buf_aspect: f64 = 0,
} = .{},

//////////////////////////////////////
//    PBWindow struct functions
//////////////////////////////////////

pub const PBWindowInitParams = struct {
    resizeable: bool = true,
    bg_color: @FieldType(PBWindow, "bg_color") = .{ 0, 0, 0 }, // black by default
    vsync: bool = true,
    /// How to interpolate pixel buffer when window size dont match buffer dimensions
    interp: @FieldType(PBWindow, "interp") = .nearest,
    /// How pixel buffer should be resized
    scaling: @FieldType(PBWindow, "scaling") = .keep_aspect,
    /// Lock window aspect ratio to the aspect ratio of the pixel buffer
    lock_aspect: bool = false,
    /// Allocator which will be used to allocate the `PBWindow` struct.
    /// Note that OS-specific window creation APIs typically use their own allocation methods,
    /// so this parameter is only responsible for the allocation of `PBWindow` struct itself.
    allocator: std.mem.Allocator = std.heap.c_allocator,
};

/// Creates the window and displays it
pub fn init(
    desired_width: usize,
    desired_height: usize,
    title: [:0]const u8,
    params: PBWindowInitParams,
) !*PBWindow {
    const self = try params.allocator.create(PBWindow);
    errdefer params.allocator.destroy(self);
    self.* = .{
        .handle = undefined,
        .width = @floatFromInt(desired_width),
        .height = @floatFromInt(desired_height),
        .scaling_factor = 1,
        .interp = params.interp,
        .scaling = params.scaling,
        .bg_color = params.bg_color,
        .lock_aspect = params.lock_aspect,
        .vsync = params.vsync,
        .allocator = params.allocator,
    };
    const window_create_err = error.unableToCreateNativeWindow;
    switch (os_tag) {
        .windows => {
            const window_class_name = std.unicode.utf8ToUtf16LeStringLiteral("GlorpWindowClass");
            const h_inst = c.GetModuleHandleW(null);
            var wc: c.WNDCLASSEXW = std.mem.zeroes(c.WNDCLASSEXW);
            wc.cbSize = @sizeOf(c.WNDCLASSEXW);
            wc.style = c.CS_HREDRAW | c.CS_VREDRAW;
            if (c.GetModuleHandleA("user32.dll")) |user32| {
                if (c.GetProcAddress(user32, "SetProcessDPIAware")) |setProcessDPIAware| {
                    _ = setProcessDPIAware(); // Set this to obtain scaling factor later
                }
            }
            wc.lpfnWndProc = struct {
                pub fn func(hwnd: c.HWND, msg: c_uint, wp: c.WPARAM, lp: c.LPARAM) callconv(.winapi) c.LRESULT {
                    const window_ptr_int: usize = @intCast(c.GetWindowLongPtrW(hwnd, c.GWLP_USERDATA));
                    const window_ptr: ?*PBWindow = if (window_ptr_int == 0) null else @ptrFromInt(window_ptr_int);
                    switch (msg) {
                        c.WM_SIZE => {
                            if (window_ptr) |window| {
                                window.width = @floatFromInt(lp & 0xFFFF);
                                window.height = @floatFromInt((lp >> 16) & 0xFFFF);
                            }
                            return 0;
                        },
                        c.WM_SIZING => {
                            if (window_ptr) |window| {
                                if (!window.lock_aspect or window.__internal.buf_aspect <= 0) {
                                    return c.DefWindowProcW(hwnd, msg, wp, lp);
                                }
                                const bounds: *c.RECT = @ptrFromInt(@as(usize, @intCast(lp)));
                                const style = c.GetWindowLongPtrW(hwnd, c.GWL_STYLE);
                                const ex_style = c.GetWindowLongPtrW(hwnd, c.GWL_EXSTYLE);
                                var border = c.RECT{};
                                _ = c.AdjustWindowRectEx(&border, @intCast(style), 0, @intCast(ex_style));
                                const non_client_w = border.right - border.left;
                                const non_client_h = border.bottom - border.top;
                                const client_w: f64 = @floatFromInt(bounds.right - bounds.left - non_client_w);
                                const client_h: f64 = @floatFromInt(bounds.bottom - bounds.top - non_client_h);
                                var new_w, var new_h = .{ client_w, client_h };
                                switch (wp) {
                                    c.WMSZ_LEFT, c.WMSZ_RIGHT => new_h = new_w / window.__internal.buf_aspect,
                                    c.WMSZ_TOP, c.WMSZ_BOTTOM => new_w = new_h / window.__internal.buf_aspect,
                                    else => {
                                        if (client_h <= new_w / window.__internal.buf_aspect) {
                                            new_h = new_w / window.__internal.buf_aspect;
                                        } else {
                                            new_w = client_h * window.__internal.buf_aspect;
                                            new_h = client_h;
                                        }
                                    },
                                }
                                bounds.right = bounds.left + non_client_w + @as(c_long, @intFromFloat(new_w));
                                bounds.bottom = bounds.top + non_client_h + @as(c_long, @intFromFloat(new_h));
                                return 1;
                            }
                            return c.DefWindowProcW(hwnd, msg, wp, lp);
                        },
                        c.WM_PAINT => {
                            var window = window_ptr.?;
                            if (window.__internal.buffer) |_| {
                                if (window.vsync != window.platform.prev_vsync_val) {
                                    window.platform.prev_vsync_val = window.vsync;
                                    const proc = struct {
                                        pub extern fn wglGetProcAddress(c.LPCSTR) callconv(.winapi) ?*anyopaque;
                                    }.wglGetProcAddress("wglSwapIntervalEXT");
                                    if (proc != null) {
                                        const Fn = *const fn (c_int) callconv(.winapi) c_int;
                                        const wglSwapIntervalEXT: Fn = @ptrCast(proc.?);
                                        _ = wglSwapIntervalEXT(if (window.vsync) 1 else 0); // actually set vsync
                                    } else if (builtin.mode == .Debug) {
                                        std.log.err("The system does not support VSync\n", .{});
                                    }
                                }
                            }
                            window.drawBufferWithOpenGl();
                            _ = c.SwapBuffers(window.platform.dev_ctx);
                            _ = c.ValidateRect(hwnd, null);
                        },
                        c.WM_ERASEBKGND => {
                            if (window_ptr) |window| {
                                // Fill entire window with background color to avoid artifacts when resizing
                                const brush = c.CreateSolidBrush(c.RGB(
                                    @as(c_uint, @intFromFloat(window.bg_color[0] * 255)),
                                    @as(c_uint, @intFromFloat(window.bg_color[1] * 255)),
                                    @as(c_uint, @intFromFloat(window.bg_color[2] * 255)),
                                ));
                                defer _ = c.DeleteObject(brush);
                                var rect: c.RECT = undefined;
                                _ = c.GetClientRect(hwnd, &rect);
                                _ = struct {
                                    pub extern fn FillRect(
                                        hDC: *anyopaque,
                                        lprc: [*c]const c.RECT,
                                        hbr: c.HBRUSH,
                                    ) callconv(.winapi) c_int;
                                }.FillRect(@ptrFromInt(wp), &rect, brush);
                                return 1;
                            }
                        },
                        c.WM_LBUTTONDOWN, c.WM_LBUTTONUP => {
                            if (window_ptr) |w| w.key_pressed[Keys.mouse_left] = (msg == c.WM_LBUTTONDOWN);
                            return 0;
                        },
                        c.WM_RBUTTONDOWN, c.WM_RBUTTONUP => {
                            if (window_ptr) |w| w.key_pressed[Keys.mouse_right] = (msg == c.WM_RBUTTONDOWN);
                            return 0;
                        },
                        c.WM_MBUTTONDOWN, c.WM_MBUTTONUP => {
                            if (window_ptr) |w| w.key_pressed[Keys.mouse_middle] = (msg == c.WM_MBUTTONDOWN);
                            return 0;
                        },
                        c.WM_MOUSEMOVE => {
                            if (window_ptr) |window| {
                                const x_coord: i16 = @intCast(lp & 0xFFFF);
                                const y_coord: i16 = @intCast((lp >> 16) & 0xFFFF);
                                window.mouse_x = @floatFromInt(x_coord);
                                window.mouse_y = @floatFromInt(y_coord);
                            }
                            return 0;
                        },
                        c.WM_KEYUP, c.WM_KEYDOWN, c.WM_SYSKEYUP, c.WM_SYSKEYDOWN => {
                            if (window_ptr) |window| {
                                const is_pressed = ((lp >> 31) & 1) == 0;
                                const scancode = ((lp >> 16) & 0xFF) | (((lp >> 24) & 1) << 8);
                                const idx = Keys.mapPlatformKeycode(@intCast(scancode));
                                if (idx < window.key_pressed.len) {
                                    window.key_pressed[idx] = is_pressed;
                                }
                            }
                        },
                        c.WM_CLOSE => _ = c.DestroyWindow(hwnd),
                        c.WM_DESTROY => {
                            if (window_ptr) |window| {
                                if (window.platform.gl_ctx) |gl_ctx| {
                                    _ = c.wglMakeCurrent(null, null);
                                    _ = c.wglDeleteContext(gl_ctx);
                                }
                                if (window.platform.dev_ctx) |dev_ctx| {
                                    _ = c.ReleaseDC(@ptrCast(window.handle), dev_ctx);
                                }
                            }
                            c.PostQuitMessage(0);
                        },
                        else => return c.DefWindowProcW(hwnd, msg, wp, lp),
                    }
                    return 0;
                }
            }.func;
            wc.hInstance = h_inst;
            wc.lpszClassName = window_class_name.ptr;

            if (c.RegisterClassExW(&wc) == 0) return error.unableToRegisterWindowClass;
            _ = try std.fmt.bufPrintZ(&self.platform.title, "{s}", .{title});
            _ = try std.unicode.utf8ToUtf16Le(&self.platform.title_utf16, &self.platform.title);
            const hwnd = c.CreateWindowExW( // zig fmt: off
                c.WS_EX_CLIENTEDGE, window_class_name.ptr, &self.platform.title_utf16,
                if (params.resizeable)
                    c.WS_OVERLAPPEDWINDOW
                else
                    (c.WS_OVERLAPPED | c.WS_MINIMIZEBOX | c.WS_SYSMENU),
                c.CW_USEDEFAULT, c.CW_USEDEFAULT,
                @intCast(desired_width), @intCast(desired_height),
                null, null, h_inst, null,
            );
            // zig fmt: on
            if (hwnd == null) return window_create_err;
            const dev_ctx = c.GetDC(hwnd);
            if (dev_ctx == null) return window_create_err;
            self.platform.dev_ctx = dev_ctx;

            var pf_desc: c.PIXELFORMATDESCRIPTOR = std.mem.zeroes(c.PIXELFORMATDESCRIPTOR);
            pf_desc.nSize = @sizeOf(c.PIXELFORMATDESCRIPTOR);
            pf_desc.nVersion = 1;
            pf_desc.dwFlags = c.PFD_DRAW_TO_WINDOW | c.PFD_SUPPORT_OPENGL | c.PFD_DOUBLEBUFFER;
            pf_desc.iPixelType = c.PFD_TYPE_RGBA;
            pf_desc.cColorBits = 32;
            pf_desc.cDepthBits = 24;
            pf_desc.cStencilBits = 8;
            pf_desc.iLayerType = c.PFD_MAIN_PLANE;
            const pixel_format = c.ChoosePixelFormat(dev_ctx, &pf_desc);
            if (pixel_format == 0) return window_create_err;
            if (c.SetPixelFormat(dev_ctx, pixel_format, &pf_desc) == 0) return window_create_err;
            const gl_ctx = c.wglCreateContext(dev_ctx) orelse return window_create_err;
            self.platform.gl_ctx = gl_ctx;
            if (c.wglMakeCurrent(dev_ctx, gl_ctx) == 0) return window_create_err;

            c.glGenTextures(1, &self.platform.texture_id);
            c.glBindTexture(c.GL_TEXTURE_2D, self.platform.texture_id);
            c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_WRAP_S, 0x812F); // GL_CLAMP_TO_EDGE
            c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_WRAP_T, 0x812F); // GL_CLAMP_TO_EDGE

            _ = c.SetWindowLongPtrW(hwnd, c.GWLP_USERDATA, @intCast(@intFromPtr(self)));
            _ = c.ShowWindow(hwnd, c.SW_NORMAL);
            if (c.UpdateWindow(hwnd) == 0) return window_create_err;

            if (builtin.os.isAtLeast(.windows, .win10) orelse false) {
                var os_ver: c.OSVERSIONINFOEXW = .{ .dwOSVersionInfoSize = @sizeOf(c.OSVERSIONINFOEXW) };
                _ = struct {
                    pub extern fn RtlGetVersion(ver_info: *c.OSVERSIONINFOEXW) callconv(.winapi) c_long;
                }.RtlGetVersion(&os_ver);
                if (os_ver.dwMajorVersion >= 10 and os_ver.dwBuildNumber >= 17763) {
                    var composition_enabled: c.BOOL = 0;
                    if (c.DwmIsCompositionEnabled(&composition_enabled) == c.S_OK and composition_enabled == 1) {
                        const dark_mode: c.BOOL = 1; // Support "dark mode" on modern Windows
                        const s = @sizeOf(@TypeOf(dark_mode));
                        _ = c.DwmSetWindowAttribute(@ptrCast(@alignCast(hwnd)), 20, @ptrCast(&dark_mode), s);
                    }
                }
            }
            var dpi: ?c_uint = null;
            if (c.GetModuleHandleA("user32.dll")) |user32| {
                if (c.GetProcAddress(user32, "GetDpiForWindow")) |proc| {
                    const getDpiForWindow = @as(*const fn (c.HWND) callconv(.C) c_uint, @ptrCast(proc));
                    dpi = getDpiForWindow(hwnd);
                    if (dpi == 0) dpi = 96;
                } else {
                    const legacy_dpi = c.GetDeviceCaps(dev_ctx, c.LOGPIXELSX);
                    if (legacy_dpi > 0) dpi = @as(c_uint, @intCast(legacy_dpi));
                }
            }
            self.scaling_factor = @as(f64, @floatFromInt(dpi orelse 96)) / 96.0;
            self.handle = @ptrCast(hwnd);
            return self;
        },
        .linux => {
            const display = c.XOpenDisplay(null) orelse return window_create_err;
            errdefer _ = c.XCloseDisplay(display);
            self.platform.display = display;
            const screen = c.DefaultScreen(display);
            var glx_attribs = [_]c_int{
                c.GLX_RGBA,       c.GLX_DOUBLEBUFFER,
                c.GLX_RED_SIZE,   8,
                c.GLX_GREEN_SIZE, 8,
                c.GLX_BLUE_SIZE,  8,
                c.None,
            };
            const vi = c.glXChooseVisual(display, screen, &glx_attribs) orelse return window_create_err;
            defer _ = c.XFree(vi);
            const colormap = c.XCreateColormap(display, c.RootWindow(display, screen), vi.*.visual, c.AllocNone);
            defer _ = c.XFreeColormap(display, colormap);
            var swa: c.XSetWindowAttributes = .{
                .colormap = colormap,
                .event_mask = c.ExposureMask | c.StructureNotifyMask | c.KeyPressMask |
                    c.KeyReleaseMask | c.ButtonPressMask | c.ButtonReleaseMask | c.PointerMotionMask,
            };
            const window = c.XCreateWindow( // zig fmt: off
                display, c.RootWindow(display, screen),
                0, 0,
                @intCast(desired_width), @intCast(desired_height),
                0, vi.*.depth, c.InputOutput, vi.*.visual, c.CWColormap | c.CWEventMask, &swa,
            );
            // zig fmt: on
            errdefer _ = c.XDestroyWindow(display, window);
            const gl_context = c.glXCreateContext(display, vi, null, c.GL_TRUE) orelse return window_create_err;
            self.handle = @ptrFromInt(window);
            self.platform.gl_ctx = gl_context;
            _ = c.glXMakeCurrent(display, window, self.platform.gl_ctx);

            const hints = c.XAllocSizeHints() orelse return window_create_err;
            defer _ = c.XFree(hints);
            hints.*.flags = c.PMinSize | c.PMaxSize;
            hints.*.min_width = if (!params.resizeable) @intCast(desired_width) else 128;
            hints.*.max_width = if (!params.resizeable) @intCast(desired_width) else 1024 * 1024;
            hints.*.min_height = if (!params.resizeable) @intCast(desired_height) else 128;
            hints.*.max_height = if (!params.resizeable) @intCast(desired_height) else 1024 * 1024;
            c.XSetWMNormalHints(display, window, hints);

            const extensions_str = c.glXQueryExtensionsString(display, screen) orelse unreachable;
            if (std.mem.indexOf(u8, std.mem.span(extensions_str), "GLX_EXT_swap_control") != null) {
                const proc = struct {
                    pub extern fn glXGetProcAddressARB(procName: [*c]const u8) callconv(.C) ?*anyopaque;
                }.glXGetProcAddressARB("glXSwapIntervalEXT".ptr);
                if (proc != null) {
                    self.platform.glXSwapIntervalEXT = @ptrCast(proc);
                    self.platform.glXSwapIntervalEXT.?(display, window, if (self.vsync) 1 else 0);
                    self.platform.prev_vsync_val = self.vsync;
                } else std.log.err("The system does not support VSync toggle\n", .{});
            }
            c.glEnable(c.GL_TEXTURE_2D);
            c.glGenTextures(1, &self.platform.texture_id);
            c.glBindTexture(c.GL_TEXTURE_2D, self.platform.texture_id);
            c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_WRAP_S, 0x812F); // GL_CLAMP_TO_EDGE
            c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_WRAP_T, 0x812F); // GL_CLAMP_TO_EDGE
            _ = c.XStoreName(display, window, title.ptr);
            _ = c.XMapWindow(display, window);
            _ = c.XSync(display, @intCast(window));
            var wm_delete_window_atom = c.XInternAtom(display, "WM_DELETE_WINDOW", c.False);
            _ = c.XSetWMProtocols(display, window, &wm_delete_window_atom, 1);
            return self;
        },
        .macos => {
            _ = objc.msg(objc.cls("NSApplication"), objc.id, "sharedApplication", .{});
            objc.msg(objc.NSApp, void, "setActivationPolicy:", .{@as(objc.NSInteger, 0)});
            const flags = @as(objc.NSUInteger, 7) | (if (params.resizeable) @as(objc.NSUInteger, 1 << 3) else 0);
            const window_handle = objc.alloc(
                objc.cls("NSWindow"),
                "initWithContentRect:styleMask:backing:defer:",
                .{
                    objc.CGRectMake(0, 0, @floatFromInt(desired_width), @floatFromInt(desired_height)),
                    flags,
                    @as(objc.NSUInteger, 2),
                    objc.NO,
                },
            );
            self.handle = @ptrCast(window_handle);
            self.scaling_factor = objc.msg(window_handle, objc.CGFloat, "backingScaleFactor", .{});

            const custom_delegate = objc.allocateClassPair("NSObject", "CustomWinDelegate");
            _ = objc.addMethod(
                custom_delegate,
                "windowShouldClose:",
                @ptrCast(&(struct {
                    pub fn func(obj: objc.id, s: objc.SEL, w: objc.id) callconv(.c) objc.BOOL {
                        _ = s;
                        _ = w;
                        const window = objc.getAssociatedObject(*PBWindow, obj, "__state__");
                        if (window.platform.display_link) |dl| {
                            _ = objc.CVDisplayLinkStop(dl);
                            objc.CVDisplayLinkRelease(dl);
                            window.platform.display_link = null;
                        }
                        window.platform.close_requested = true;
                        return objc.YES;
                    }
                }.func)),
                "c@:@",
            );
            _ = objc.addMethod(
                custom_delegate,
                "windowWillResize:toSize:",
                @ptrCast(&(struct {
                    pub fn func(
                        obj: objc.id,
                        sel: objc.SEL,
                        ns_window: objc.id,
                        new_size: objc.CGSize,
                    ) callconv(.c) objc.CGSize {
                        _ = sel;
                        const window = objc.getAssociatedObject(*PBWindow, obj, "__state__");
                        window.scaling_factor = objc.msg(ns_window, objc.CGFloat, "backingScaleFactor", .{});
                        window.width = new_size.width;
                        window.height = new_size.height;
                        return new_size;
                    }
                }.func)),
                "{NSSize=ff}@:{NSSize=ff}",
            );
            objc.registerClassPair(custom_delegate);
            const delegate_inst = objc.alloc(custom_delegate, "init", .{});
            objc.msg(window_handle, void, "setDelegate:", .{delegate_inst});
            objc.setAssociatedObject(delegate_inst, "__state__", @ptrCast(self));

            const custom_view = objc.allocateClassPair("NSView", "CustomView");
            _ = objc.addMethod(
                custom_view,
                "drawRect:",
                @ptrCast(&(struct {
                    pub fn func(obj: objc.id, sel: objc.SEL, rect: objc.CGRect) callconv(.c) void {
                        _ = sel;
                        _ = rect;
                        const window = objc.getAssociatedObject(*PBWindow, obj, "__state__");
                        if (window.__internal.buffer) |buf| {
                            const context = objc.msg(
                                objc.msg(objc.cls("NSGraphicsContext"), objc.id, "currentContext", .{}),
                                objc.CGContextRef,
                                "graphicsPort",
                                .{},
                            );

                            const interp_quality: i32 = switch (window.interp) {
                                .nearest => 1, // kCGInterpolationNone
                                .bilinear => 3, // kCGInterpolationHigh
                            };
                            objc.CGContextSetInterpolationQuality(context, interp_quality);
                            const space = objc.CGColorSpaceCreateDeviceRGB();
                            const provider = objc.CGDataProviderCreateWithData(null, buf.ptr, buf.len, null);

                            const img = objc.CGImageCreate(
                                window.__internal.buf_width,
                                window.__internal.buf_height,
                                8,
                                32,
                                window.__internal.buf_width * 4,
                                space,
                                4 | 8192, // kCGImageAlphaNoneSkipFirst | kCGBitmapByteOrder32Little
                                provider,
                                null,
                                false,
                                0, // kCGRenderingIntentDefault
                            );
                            objc.CGColorSpaceRelease(space);
                            objc.CGDataProviderRelease(provider);

                            const ns_window = objc.msg(obj, objc.id, "window", .{});
                            const window_rect = objc.msg(ns_window, objc.CGRect, "frame", .{});
                            const c_rect = objc.msg(ns_window, objc.CGRect, "contentRectForFrameRect:", .{window_rect});
                            var view_rect = objc.CGRectMake(0, 0, c_rect.size.width, c_rect.size.height);
                            const r, const g, const b = window.bg_color;
                            objc.CGContextSetRGBFillColor(context, r, g, b, 1.0);
                            objc.CGContextFillRect(context, view_rect); // fill the background with color

                            const buf_wf: f64 = @floatFromInt(window.__internal.buf_width);
                            const buf_hf: f64 = @floatFromInt(window.__internal.buf_height);
                            const f: f64 = buf_wf * window.scaling_factor / 3.2;
                            // fix occasional jittering by limiting float precision
                            view_rect.size.width = buf_wf * (@round(c_rect.size.width / buf_wf * f) / f);
                            view_rect.size.height = buf_hf * (@round(c_rect.size.height / buf_hf * f) / f);

                            if (window.scaling == .keep_aspect) {
                                const view_ratio = view_rect.size.width / view_rect.size.height;
                                if (view_ratio > window.__internal.buf_aspect) {
                                    const width = view_rect.size.height * window.__internal.buf_aspect;
                                    const x = (view_rect.size.width - width) * 0.5;
                                    view_rect = objc.CGRectMake(x, 0, width, view_rect.size.height);
                                } else {
                                    const height = view_rect.size.width / window.__internal.buf_aspect;
                                    const y = (view_rect.size.height - height) * 0.5;
                                    view_rect = objc.CGRectMake(0, y, view_rect.size.width, height);
                                }
                            }
                            objc.CGContextDrawImage(context, view_rect, img);
                            objc.CGImageRelease(img);
                        }
                    }
                }.func)),
                "i@:@@",
            );
            objc.registerClassPair(custom_view);
            const custom_view_inst = objc.alloc(custom_view, "init", .{});
            objc.msg(window_handle, void, "setContentView:", .{custom_view_inst});
            objc.setAssociatedObject(custom_view_inst, "__state__", @ptrCast(self));

            self.updateTitle(title);
            objc.msg(window_handle, void, "makeKeyAndOrderFront:", .{@as(objc.id, null)});
            objc.msg(window_handle, void, "center", .{});
            objc.msg(objc.NSApp, void, "activateIgnoringOtherApps:", .{objc.YES});

            _ = objc.CVDisplayLinkCreateWithActiveCGDisplays(&self.platform.display_link);
            _ = objc.CVDisplayLinkSetOutputCallback(self.platform.display_link, struct {
                const opq = *anyopaque;
                fn func(p1: opq, p2: opq, p3: opq, p4: *u64, p5: *u64, user_data: ?opq) callconv(.c) i32 {
                    // zig fmt: off
                    _ = p1; _ = p2; _ = p3; _ = p4; _ = p5;
                    // zig fmt: on
                    const window: *PBWindow = @ptrCast(@alignCast(user_data.?));

                    var t_io = std.Io.Threaded.init_single_threaded;
                    const io = t_io.ioBasic();
                    window.platform.vsync_mutex.lockUncancelable(io);
                    defer window.platform.vsync_mutex.unlock(io);
                    window.platform.frame_ready = true; // Signal the main loop that it can proceed.
                    window.platform.vsync_cond.signal(io);
                    return 0;
                }
            }.func, @ptrCast(self));
            _ = objc.CVDisplayLinkStart(self.platform.display_link);

            return self;
        },
        else => @compileError(ERROR_STR_UNIMPLEMENTED),
    }
}

/// Destroys the window and frees the memory
pub fn deinit(self: *PBWindow) void {
    switch (os_tag) {
        .macos => {
            if (self.platform.display_link) |dl| {
                _ = objc.CVDisplayLinkStop(dl);
                objc.CVDisplayLinkRelease(dl);
            }
            objc.msg(@ptrCast(@alignCast(self.handle)), void, "close", .{});
        },
        .windows => {
            if (self.platform.gl_ctx) |gl_ctx| {
                _ = c.wglMakeCurrent(null, null);
                _ = c.wglDeleteContext(gl_ctx);
            }
        },
        .linux => {
            if (self.platform.gl_ctx) |glc| {
                _ = c.glXMakeCurrent(self.platform.display, c.None, null);
                c.glXDestroyContext(self.platform.display, glc);
            }
            _ = c.XDestroyWindow(self.platform.display, @intFromPtr(self.handle));
            _ = c.XCloseDisplay(self.platform.display);
        },
        else => @compileError(ERROR_STR_UNIMPLEMENTED),
    }
    var a = self.allocator;
    a.destroy(self);
    self.* = undefined;
}

/// Processes events and updates the window state. Should be called in a loop.
pub fn update(self: *PBWindow) bool {
    switch (os_tag) {
        .windows => {
            var msg: c.MSG = undefined;
            while (c.PeekMessageW(&msg, null, 0, 0, c.PM_REMOVE) != 0) {
                if (msg.message == c.WM_QUIT) return false;
                _ = c.TranslateMessage(&msg);
                _ = c.DispatchMessageW(&msg);
            }
            _ = c.RedrawWindow(@ptrCast(self.handle), null, null, c.RDW_INTERNALPAINT);
            return true;
        },
        .linux => {
            var event: c.XEvent = undefined;
            while (c.XPending(self.platform.display) != 0) {
                _ = c.XNextEvent(self.platform.display, &event);
                switch (event.type) {
                    c.ButtonPress, c.ButtonRelease => {
                        const is_pressed = event.type == c.ButtonPress;
                        const button_event = @as(*const c.XButtonEvent, @ptrCast(&event));
                        switch (button_event.button) {
                            c.Button1 => self.key_pressed[Keys.mouse_left] = is_pressed,
                            c.Button2 => self.key_pressed[Keys.mouse_middle] = is_pressed,
                            c.Button3 => self.key_pressed[Keys.mouse_right] = is_pressed,
                            else => {},
                        }
                    },
                    c.KeyPress, c.KeyRelease => {
                        const is_pressed = event.type == c.KeyPress;
                        const key_code = event.xkey.keycode;
                        var keysym = c.XkbKeycodeToKeysym(self.platform.display, @intCast(key_code), 0, 0);
                        if (keysym >= c.XK_a and keysym <= c.XK_z) keysym = keysym - (c.XK_a - c.XK_A);
                        const idx = Keys.mapPlatformKeycode(@intCast(keysym));
                        if (idx < self.key_pressed.len) self.key_pressed[idx] = is_pressed;
                    },
                    c.MotionNotify => {
                        const motion_event = @as(*const c.XMotionEvent, @ptrCast(&event));
                        self.mouse_x = @floatFromInt(motion_event.x);
                        self.mouse_y = @floatFromInt(motion_event.y);
                    },
                    c.ConfigureNotify => {
                        const cevent = @as(*const c.XConfigureEvent, @ptrCast(&event));
                        self.width = @floatFromInt(cevent.width);
                        self.height = @floatFromInt(cevent.height);
                    },
                    c.ClientMessage => {
                        const atom = c.XInternAtom(self.platform.display, "WM_DELETE_WINDOW", c.False);
                        if (event.xclient.data.l[0] == @as(c_long, @intCast(atom))) {
                            return false; // break main loop
                        }
                    },
                    else => {},
                }
            }
            if (self.vsync != self.platform.prev_vsync_val and self.platform.glXSwapIntervalEXT != null) {
                const dpy = self.platform.display;
                self.platform.glXSwapIntervalEXT.?(dpy, @intFromPtr(self.handle), if (self.vsync) 1 else 0);
                self.platform.prev_vsync_val = self.vsync;
            }
            if (self.vsync and self.__internal.buffer != null) self.drawBufferWithOpenGl();
            c.glXSwapBuffers(self.platform.display, @intFromPtr(self.handle));
            return true;
        },
        .macos => {
            if (self.platform.close_requested) return false;
            if (self.vsync) {
                var t_io = std.Io.Threaded.init_single_threaded;
                const io = t_io.ioBasic();
                self.platform.vsync_mutex.lockUncancelable(io);
                while (!self.platform.frame_ready) {
                    self.platform.vsync_cond.waitUncancelable(io, &self.platform.vsync_mutex);
                }
                self.platform.frame_ready = false;
                self.platform.vsync_mutex.unlock(io);
            }
            const window_handle: objc.id = @ptrCast(@alignCast(self.handle));
            const pollEvent = struct {
                pub fn func(flags: anytype) objc.id { // zig fmt: off
                    return objc.msg(objc.NSApp, objc.id, "nextEventMatchingMask:untilDate:inMode:dequeue:", .{
                        @as(usize, std.math.maxInt(usize)), @as(objc.id, null), flags, objc.YES,
                    });
                    // zig fmt: on
                }
            }.func;
            eventPollLoop: while (true) {
                const e = pollEvent(objc.NSDefaultRunLoopMode) orelse pollEvent(objc.NSEventTrackingRunLoopMode);
                const event = e orelse break :eventPollLoop;
                const event_type = objc.msg(event, objc.NSUInteger, "type", .{});
                switch (event_type) {
                    1, 2 => self.key_pressed[Keys.mouse_left] = event_type == 1,
                    3, 4 => self.key_pressed[Keys.mouse_right] = event_type == 3,
                    25, 26 => { // NSEventTypeOtherMouseDown, NSEventTypeOtherMouseUp
                        const button_number = objc.msg(event, objc.NSInteger, "buttonNumber", .{});
                        if (button_number == 2) { // 2 -> middle mouse button
                            self.key_pressed[Keys.mouse_middle] = event_type == 25;
                        }
                    },
                    5, 6 => { // NSEventTypeMouseMoved
                        const pos = objc.msg(event, objc.CGPoint, "locationInWindow", .{});
                        self.mouse_x = @floatCast(pos.x);
                        self.mouse_y = @floatCast(self.height - pos.y);
                    },
                    10, 11, 12 => { // NSEventTypeKeyDown, NSEventTypeKeyUp
                        const key_code = objc.msg(event, objc.NSUInteger, "keyCode", .{});
                        const modifier_flags = objc.msg(event, objc.NSUInteger, "modifierFlags", .{});
                        if (event_type == 10 and (modifier_flags & (1 << 20)) != 0 and key_code == 12) { // Cmd+Q
                            objc.msg(window_handle, void, "performClose:", .{@as(objc.id, null)});
                            continue;
                        }
                        const idx = Keys.mapPlatformKeycode(@intCast(key_code));
                        if (key_code < 128) {
                            var is_pressed = event_type == 10;
                            if (event_type == 12) {
                                is_pressed = !self.key_pressed[idx];
                                if (idx == Keys.super) {
                                    // We handle command key differrently,
                                    // because there's two of them with the same keycode
                                    const MOD_SUPER = @as(objc.NSUInteger, 1 << 20);
                                    is_pressed = (modifier_flags & MOD_SUPER) != 0;
                                }
                            }
                            self.key_pressed[idx] = is_pressed;
                            continue;
                        }
                    },
                    else => {},
                }
                objc.msg(objc.NSApp, void, "sendEvent:", .{event});
            }
            objc.msg(objc.msg(window_handle, objc.id, "contentView", .{}), void, "setNeedsDisplay:", .{objc.YES});
            return true;
        },
        else => @compileError(ERROR_STR_UNIMPLEMENTED),
    }
}

pub fn updateTitle(self: *PBWindow, new_title: [:0]const u8) void {
    switch (os_tag) {
        .windows => {
            var platform = &self.platform;
            const title_trunc = new_title[0..(@min(new_title.len, platform.title.len - 1))];
            if (!std.mem.eql(u8, title_trunc, platform.title[0..title_trunc.len])) {
                @memcpy(platform.title[0..title_trunc.len], title_trunc);
                platform.title[title_trunc.len] = 0;
                _ = std.unicode.utf8ToUtf16Le(&platform.title_utf16, &platform.title) catch unreachable;
                const hwnd: c.HWND = @ptrCast(self.handle);
                _ = c.SetWindowTextW(hwnd, &platform.title_utf16);
            }
        },
        .linux => {
            const now = std.time.milliTimestamp();
            // throttle updates to avoid XServer ddosing when `updateTitle` is called in a loop
            if (now - self.platform.last_title_update > @divFloor(1000, 30)) {
                const d = self.platform.display;
                const win: c.Window = @intFromPtr(self.handle);
                _ = c.XStoreName(d, win, new_title.ptr);
                const utf8_prop = c.XInternAtom(d, "_NET_WM_NAME", c.False);
                const utf8_str_prop = c.XInternAtom(d, "UTF8_STRING", c.False);
                if (c.XSupportsLocale() != 0 and utf8_prop != 0 and utf8_str_prop != 0) {
                    const str_ptr: [*c]const u8 = @ptrCast(new_title.ptr);
                    const len: c_int = @intCast(new_title.len);
                    _ = c.XChangeProperty(d, win, utf8_prop, utf8_str_prop, 8, c.PropModeReplace, str_ptr, len);
                }
                _ = c.XFlush(d);
                self.platform.last_title_update = now;
            }
        },
        .macos => {
            const window_handle: objc.id = @ptrCast(@alignCast(self.handle));
            const title_str = objc.msg(objc.cls("NSString"), objc.id, "stringWithUTF8String:", .{new_title.ptr});
            objc.msg(window_handle, void, "setTitle:", .{title_str});
        },
        else => @compileError(ERROR_STR_UNIMPLEMENTED),
    }
}

/// Updates the currently shown pixel buffer. Pixel buffer should be in a RGBA8 format.
///
/// Caller is responsible for managing the memory for the pixel buffer,
/// as PBWindow does neither allocate nor create a copy of the buffer by itself.
pub fn setPixelBuffer(self: *PBWindow, buf: []const u8, buf_w: usize, buf_h: usize) void {
    self.__internal.buffer = buf;
    self.__internal.buf_height = buf_h;
    self.__internal.buf_width = buf_w;
    self.__internal.buf_aspect = @as(f64, @floatFromInt(buf_w)) / @as(f64, @floatFromInt(buf_h));
    switch (os_tag) {
        .windows, .linux => {},
        .macos => {
            const handle: objc.id = @ptrCast(@alignCast(self.handle));
            objc.msg(handle, void, "setResizeIncrements:", .{objc.CGSizeMake(1, 1)});
            if (self.lock_aspect) {
                const aspect = objc.CGSizeMake(@floatFromInt(buf_w), @floatFromInt(buf_h));
                objc.msg(handle, void, "setContentAspectRatio:", .{aspect});
            }
        },
        else => @compileError(ERROR_STR_UNIMPLEMENTED),
    }
}

fn drawBufferWithOpenGl(window: *PBWindow) void {
    c.glBindTexture(c.GL_TEXTURE_2D, window.platform.texture_id);
    const filter = if (window.interp == .bilinear) c.GL_LINEAR else c.GL_NEAREST;
    c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MIN_FILTER, filter);
    c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MAG_FILTER, filter);
    c.glTexImage2D(
        c.GL_TEXTURE_2D,
        0,
        c.GL_RGBA,
        @intCast(window.__internal.buf_width),
        @intCast(window.__internal.buf_height),
        0,
        c.GL_BGRA_EXT,
        c.GL_UNSIGNED_BYTE,
        @ptrCast(window.__internal.buffer.?.ptr),
    );

    const rect = [4]f32{ 0, 0, @floatCast(window.width), @floatCast(window.height) };
    var x1, var y1, var x2, var y2 = rect;
    if (window.scaling == .keep_aspect) {
        const view_ratio = window.width / window.height;
        if (view_ratio > window.__internal.buf_aspect) {
            const w: f32 = @floatCast(window.height * window.__internal.buf_aspect);
            x1 = @floatCast((window.width - w) * 0.5);
            x2 = x1 + w;
        } else {
            const h: f32 = @floatCast(window.width / window.__internal.buf_aspect);
            y1 = @floatCast((window.height - h) * 0.5);
            y2 = y1 + h;
        }
    }
    const vertices: [16]f32 = .{
        x1, y1, 0, 0, // x, y, u, v
        x1, y2, 0, 1,
        x2, y2, 1, 1,
        x2, y1, 1, 0,
    };

    const r, const g, const b = window.bg_color;
    c.glViewport(0, 0, @intFromFloat(window.width), @intFromFloat(window.height));
    c.glMatrixMode(c.GL_PROJECTION);
    c.glLoadIdentity();
    c.glOrtho(0, window.width, window.height, 0, -1, 1);
    c.glClearColor(@floatCast(r), @floatCast(g), @floatCast(b), 1.0);
    c.glClear(c.GL_COLOR_BUFFER_BIT);
    c.glEnable(c.GL_TEXTURE_2D);
    c.glEnableClientState(c.GL_VERTEX_ARRAY);
    c.glEnableClientState(c.GL_TEXTURE_COORD_ARRAY);
    c.glVertexPointer(2, c.GL_FLOAT, 4 * @sizeOf(f32), @ptrCast(&vertices));
    c.glTexCoordPointer(2, c.GL_FLOAT, 4 * @sizeOf(f32), @ptrCast(vertices[2..].ptr));
    c.glDrawArrays(c.GL_QUADS, 0, 4);
    c.glDisable(c.GL_TEXTURE_2D);
}
