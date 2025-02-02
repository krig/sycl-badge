pub fn init() void {
    @setCold(true);
    Port.BUTTON_SELECT.set_dir(.in);
    Port.BUTTON_START.set_dir(.in);
    Port.BUTTON_A.set_dir(.in);
    Port.BUTTON_B.set_dir(.in);
    Port.BUTTON_UP.set_dir(.in);
    Port.BUTTON_DOWN.set_dir(.in);
    Port.BUTTON_PRESS.set_dir(.in);
    Port.BUTTON_RIGHT.set_dir(.in);
    Port.BUTTON_LEFT.set_dir(.in);

    @memset(@as(*[0x19A0]u8, @ptrFromInt(0x20000000)), 0);

    // fill .bss with zeroes
    {
        const bss_start: [*]u8 = @ptrCast(&libcart.cart_bss_start);
        const bss_end: [*]u8 = @ptrCast(&libcart.cart_bss_end);
        const bss_len = @intFromPtr(bss_end) - @intFromPtr(bss_start);

        @memset(bss_start[0..bss_len], 0);
    }

    // load .data from flash
    {
        const data_start: [*]u8 = @ptrCast(&libcart.cart_data_start);
        const data_end: [*]u8 = @ptrCast(&libcart.cart_data_end);
        const data_len = @intFromPtr(data_end) - @intFromPtr(data_start);
        const data_src: [*]const u8 = @ptrCast(&libcart.cart_data_load_start);

        @memcpy(data_start[0..data_len], data_src[0..data_len]);
    }
}

pub fn start() void {
    call(&libcart.start);
}

pub fn tick() void {
    if (!timer.check_frame_ready()) return;

    {
        GAMEPAD1.* = ((@as(u8, 1) & @intFromEnum(Port.BUTTON_SELECT.read())) << 0 |
            (@as(u8, 1) & @intFromEnum(Port.BUTTON_START.read())) << 1 |
            (@as(u8, 1) & @intFromEnum(Port.BUTTON_A.read())) << 2 |
            (@as(u8, 1) & @intFromEnum(Port.BUTTON_B.read())) << 3 |
            (@as(u8, 1) & @intFromEnum(Port.BUTTON_UP.read())) << 4 |
            (@as(u8, 1) & @intFromEnum(Port.BUTTON_DOWN.read())) << 5 |
            (@as(u8, 1) & @intFromEnum(Port.BUTTON_RIGHT.read())) << 6 |
            (@as(u8, 1) & @intFromEnum(Port.BUTTON_LEFT.read())) << 7
        // TODO: pressed
        );
    }
    if (SYSTEM_FLAGS.* & SYSTEM_PRESERVE_FRAMEBUFFER == 0) @memset(FRAMEBUFFER, 0b00_00_00_00);
    call(&libcart.update);
    var x: u8 = 0;
    var y: u8 = 0;
    for (FRAMEBUFFER[0 .. lcd.width * lcd.height * 2 / 8]) |byte| {
        inline for (.{ 0, 2, 4, 6 }) |shift| {
            const palette_index: u2 = @truncate(byte >> shift);
            const color: u24 = @truncate(PALETTE[palette_index]);
            lcd.fb.bpp24[x][y] = @bitCast(color);
            x += 1;
        }
        if (x == lcd.width) {
            x = 0;
            y += 1;
        }
    }
    std.debug.assert(y == lcd.height);
}

pub fn blit(sprite: [*]const User(u8), x: i32, y: i32, rest: *const extern struct { width: User(u32), height: User(u32), flags: User(u32) }) callconv(.C) void {
    const width = rest.width.load();
    const height = rest.height.load();
    const flags = rest.flags.load();

    switch (flags) {
        BLIT_1BPP => for (0..height) |sprite_y| {
            for (0..width) |sprite_x| {
                const sprite_index = sprite_x + width * sprite_y;
                const draw_color_index: u1 = @truncate(sprite[sprite_index >> 3].load() >>
                    (7 - @as(u3, @truncate(sprite_index))));
                clip_draw(
                    x +| @min(sprite_x, std.math.maxInt(i32)),
                    y +| @min(sprite_y, std.math.maxInt(i32)),
                    draw_color_index,
                );
            }
        },
        BLIT_2BPP => for (0..height) |sprite_y| {
            for (0..width) |sprite_x| {
                const sprite_index = sprite_x + width * sprite_y;
                const draw_color_index: u2 = @truncate(sprite[sprite_index >> 2].load() >>
                    (6 - (@as(u3, @as(u2, @truncate(sprite_index))) << 1)));
                clip_draw(
                    x +| @min(sprite_x, std.math.maxInt(i32)),
                    y +| @min(sprite_y, std.math.maxInt(i32)),
                    draw_color_index,
                );
            }
        },
        else => {},
    }
}

pub fn oval(x: i32, y: i32, width: u32, height: u32) callconv(.C) void {
    if (width == 0 or height == 0 or x >= SCREEN_SIZE or y >= SCREEN_SIZE) return;
    const end_x = x +| @min(width, std.math.maxInt(i32));
    const end_y = y +| @min(height, std.math.maxInt(i32));
    if (end_x < 0 or end_y < 0) return;

    const draw_colors = DRAW_COLORS.*;
    const fill_draw_color: u4 = @truncate(draw_colors >> 0);
    const stroke_draw_color: u4 = @truncate(draw_colors >> 4);
    if (fill_draw_color == 0 and stroke_draw_color == 0) return;
    const fill_palette_index: ?u2 = if (fill_draw_color == 0) null else @truncate(fill_draw_color - 1);
    const stroke_palette_index: ?u2 = if (stroke_draw_color == 0) fill_palette_index else @truncate(stroke_draw_color - 1);

    switch (std.math.order(width, height)) {
        .lt => rect(x, y, width, height),
        .eq => {
            const size: u31 = @intCast(width >> 1);
            const mid_x = x +| size;
            const mid_y = y +| size;

            var cur_x: u31 = 0;
            var cur_y: u31 = size;
            var err: i32 = size >> 1;
            while (cur_x <= cur_y) {
                hline(mid_x -| cur_y, mid_y -| cur_x, cur_y << 1);
                hline(mid_x -| cur_y, mid_y +| cur_x, cur_y << 1);
                if (stroke_palette_index) |palette_index| {
                    clip_draw_palette(mid_x -| cur_x, mid_y -| cur_y, palette_index);
                    clip_draw_palette(mid_x +| cur_x, mid_y -| cur_y, palette_index);
                    clip_draw_palette(mid_x -| cur_y, mid_y -| cur_x, palette_index);
                    clip_draw_palette(mid_x +| cur_y, mid_y -| cur_x, palette_index);
                    clip_draw_palette(mid_x -| cur_y, mid_y +| cur_x, palette_index);
                    clip_draw_palette(mid_x +| cur_y, mid_y +| cur_x, palette_index);
                    clip_draw_palette(mid_x -| cur_x, mid_y +| cur_y, palette_index);
                    clip_draw_palette(mid_x +| cur_x, mid_y +| cur_y, palette_index);
                }
                cur_x += 1;
                err += cur_x;
                const temp = err - cur_y;
                if (temp >= 0) {
                    err = temp;
                    cur_y -= 1;

                    if (cur_x <= cur_y) {
                        hline(mid_x -| cur_x, mid_y -| cur_y, cur_x << 1);
                        hline(mid_x -| cur_x, mid_y +| cur_y, cur_x << 1);
                    }
                }
            }
        },
        .gt => rect(x, y, width, height),
    }
}

pub fn rect(x: i32, y: i32, width: u32, height: u32) callconv(.C) void {
    if (width == 0 or height == 0 or x >= SCREEN_SIZE or y >= SCREEN_SIZE) return;
    const end_x = x +| @min(width, std.math.maxInt(i32));
    const end_y = y +| @min(height, std.math.maxInt(i32));
    if (end_x < 0 or end_y < 0) return;

    const draw_colors = DRAW_COLORS.*;
    const fill_draw_color: u4 = @truncate(draw_colors >> 0);
    const stroke_draw_color: u4 = @truncate(draw_colors >> 4);
    if (fill_draw_color == 0 and stroke_draw_color == 0) return;
    const fill_palette_index: ?u2 = if (fill_draw_color == 0) null else @truncate(fill_draw_color - 1);
    const stroke_palette_index: ?u2 = if (stroke_draw_color == 0) fill_palette_index else @truncate(stroke_draw_color - 1);

    if (stroke_palette_index) |palette_index| {
        if (y >= 0 and y < SCREEN_SIZE) {
            for (@max(x, 0)..@intCast(@min(end_x, SCREEN_SIZE))) |cur_x| {
                draw_palette(@intCast(cur_x), @intCast(y), palette_index);
            }
        }
    }
    if (height > 2) {
        for (@max(y + 1, 0)..@intCast(@min(end_y - 1, SCREEN_SIZE))) |cur_y| {
            if (stroke_palette_index) |palette_index| {
                if (x >= 0 and x < SCREEN_SIZE) {
                    draw_palette(@intCast(x), @intCast(cur_y), palette_index);
                }
            }
            if (fill_palette_index) |palette_index| {
                if (width > 2) {
                    for (@max(x + 1, 0)..@intCast(@min(end_x - 1, SCREEN_SIZE))) |cur_x| {
                        draw_palette(@intCast(cur_x), @intCast(cur_y), palette_index);
                    }
                }
            }
            if (stroke_palette_index) |palette_index| {
                if (width > 1 and end_x - 1 >= 0 and end_x - 1 < SCREEN_SIZE) {
                    draw_palette(@intCast(end_x - 1), @intCast(cur_y), palette_index);
                }
            }
        }
    }
    if (stroke_palette_index) |palette_index| {
        if (height > 1 and end_y - 1 >= 0 and end_y - 1 < SCREEN_SIZE) {
            for (@max(x, 0)..@intCast(@min(end_x, SCREEN_SIZE))) |cur_x| {
                draw_palette(@intCast(cur_x), @intCast(end_y - 1), palette_index);
            }
        }
    }
}

pub fn text(str: [*]const User(u8), len: usize, x: i32, y: i32) callconv(.C) void {
    var cur_x = x;
    var cur_y = y;
    for (str[0..len]) |*byte| switch (byte.load()) {
        else => cur_x +|= 8,
        '\n' => {
            cur_x = x;
            cur_y +|= 8;
        },
        ' '...0xFF => |char| {
            const glyph = &font[char - ' '];
            blit_unsafe(glyph, cur_x, cur_y, 8, 8, BLIT_1BPP);
            cur_x +|= 8;
        },
    };
}

pub fn vline(x: i32, y: i32, len: u32) callconv(.C) void {
    if (len == 0 or x < 0 or x >= SCREEN_SIZE or y >= SCREEN_SIZE) return;
    const end_y = y +| @min(len, std.math.maxInt(i32));
    if (end_y < 0) return;

    const draw_color: u4 = @truncate(DRAW_COLORS.* >> 0);
    if (draw_color == 0) return;
    const palette_index: u2 = @truncate(draw_color - 1);

    for (@max(y, 0)..@intCast(@min(end_y, SCREEN_SIZE))) |cur_y| {
        draw_palette(@intCast(x), @intCast(cur_y), palette_index);
    }
}

pub fn hline(x: i32, y: i32, len: u32) callconv(.C) void {
    if (len == 0 or y < 0 or y >= SCREEN_SIZE or x >= SCREEN_SIZE) return;
    const end_x = x +| @min(len, std.math.maxInt(i32));
    if (end_x < 0) return;

    const draw_color: u4 = @truncate(DRAW_COLORS.* >> 0);
    if (draw_color == 0) return;
    const palette_index: u2 = @truncate(draw_color - 1);

    for (@max(x, 0)..@intCast(@min(end_x, SCREEN_SIZE))) |cur_x| {
        draw_palette(@intCast(cur_x), @intCast(y), palette_index);
    }
}

pub fn tone(frequency: u32, duration: u32, volume: u32, flags: u32) callconv(.C) void {
    const start_frequency: u16 = @truncate(frequency >> 0);
    const end_frequency = switch (@as(u16, @truncate(frequency >> 16))) {
        0 => start_frequency,
        else => |end_frequency| end_frequency,
    };
    const sustain_time: u8 = @truncate(duration >> 0);
    const release_time: u8 = @truncate(duration >> 8);
    const decay_time: u8 = @truncate(duration >> 16);
    const attack_time: u8 = @truncate(duration >> 24);
    const total_time = @as(u10, attack_time) + decay_time + sustain_time + release_time;
    const sustain_volume: u8 = @truncate(volume >> 0);
    const peak_volume = switch (@as(u8, @truncate(volume >> 8))) {
        0 => 100,
        else => |attack_volume| attack_volume,
    };
    const channel: enum { pulse1, pulse2, triangle, noise } = @enumFromInt(@as(u2, @truncate(flags >> 0)));

    var state: audio.Channel = .{
        .duty = 0,
        .phase = 0,
        .phase_step = 0,
        .phase_step_step = 0,

        .duration = 0,
        .attack_duration = 0,
        .decay_duration = 0,
        .sustain_duration = 0,
        .release_duration = 0,

        .volume = 0,
        .volume_step = 0,
        .peak_volume = 0,
        .sustain_volume = 0,
        .attack_volume_step = 0,
        .decay_volume_step = 0,
        .release_volume_step = 0,
    };

    const start_phase_step = @mulWithOverflow((1 << 32) / 44100, @as(u31, start_frequency));
    const end_phase_step = @mulWithOverflow((1 << 32) / 44100, @as(u31, end_frequency));
    if (start_phase_step[1] != 0 or end_phase_step[1] != 0) return;
    state.phase_step = start_phase_step[0];
    state.phase_step_step = @divTrunc(@as(i32, end_phase_step[0]) - start_phase_step[0], @as(u20, total_time) * @divExact(44100, 60));

    state.attack_duration = @as(u18, attack_time) * @divExact(44100, 60);
    state.decay_duration = @as(u18, decay_time) * @divExact(44100, 60);
    state.sustain_duration = @as(u18, sustain_time) * @divExact(44100, 60);
    state.release_duration = @as(u18, release_time) * @divExact(44100, 60);

    state.peak_volume = @as(u29, peak_volume) << 21;
    state.sustain_volume = @as(u29, sustain_volume) << 21;
    if (state.attack_duration > 0) {
        state.attack_volume_step = @divTrunc(@as(i32, state.peak_volume) - 0, state.attack_duration);
    }
    if (state.decay_duration > 0) {
        state.decay_volume_step = @divTrunc(@as(i32, state.sustain_volume) - state.peak_volume, state.decay_duration);
    }
    if (state.release_duration > 0) {
        state.release_volume_step = @divTrunc(@as(i32, 0) - state.sustain_volume, state.release_duration);
    }

    switch (channel) {
        .pulse1, .pulse2 => {
            const mode: enum { @"1/8", @"1/4", @"1/2", @"3/4" } = @enumFromInt(@as(u2, @truncate(flags >> 2)));
            state.duty = switch (mode) {
                .@"1/8" => (1 << 32) / 8,
                .@"1/4" => (1 << 32) / 4,
                .@"1/2" => (1 << 32) / 2,
                .@"3/4" => (3 << 32) / 4,
            };
        },
        .triangle => {
            state.duty = (1 << 32) / 2;
        },
        .noise => {
            state.duty = (1 << 32) / 2;
        },
    }

    audio.set_channel(@intFromEnum(channel), state);
}

pub fn trace(str: [*]const User(u8), len: usize) callconv(.C) void {
    std.log.scoped(.trace).info("{}", .{fmt_user_string(str[0..len])});
}

fn call(func: *const fn () callconv(.C) void) void {
    const process_stack = utils.HSRAM.ADDR[utils.HSRAM.SIZE - @divExact(
        utils.HSRAM.SIZE,
        3 * 2,
    ) ..][0..@divExact(utils.HSRAM.SIZE, 3 * 4)];
    const frame = comptime std.mem.bytesAsSlice(u32, process_stack[process_stack.len - 0x20 ..]);
    @memset(frame[0..5], 0);
    frame[5] = @intFromPtr(&__return_thunk__);
    frame[6] = @intFromPtr(func);
    frame[7] = 1 << 24;
    asm volatile (
        \\ msr psp, %[process_stack]
        \\ svc #12
        :
        : [process_stack] "r" (frame.ptr),
        : "memory"
    );
}

fn blit_unsafe(sprite: [*]const u8, x: i32, y: i32, width: u32, height: u32, flags: u32) void {
    switch (flags) {
        BLIT_1BPP => for (0..height) |sprite_y| {
            for (0..width) |sprite_x| {
                const sprite_index = sprite_x + width * sprite_y;
                const draw_color_index: u1 = @truncate(sprite[sprite_index >> 3] >>
                    (7 - @as(u3, @truncate(sprite_index))));
                clip_draw(
                    x +| @min(sprite_x, std.math.maxInt(i32)),
                    y +| @min(sprite_y, std.math.maxInt(i32)),
                    draw_color_index,
                );
            }
        },
        BLIT_2BPP => for (0..height) |sprite_y| {
            for (0..width) |sprite_x| {
                const sprite_index = sprite_x + width * sprite_y;
                const draw_color_index: u2 = @truncate(sprite[sprite_index >> 2] >>
                    (6 - (@as(u3, @as(u2, @truncate(sprite_index))) << 1)));
                clip_draw(
                    x +| @min(sprite_x, std.math.maxInt(i32)),
                    y +| @min(sprite_y, std.math.maxInt(i32)),
                    draw_color_index,
                );
            }
        },
        else => {},
    }
}

inline fn clip_draw(x: i32, y: i32, draw_color_index: u2) void {
    if (x < 0 or x >= SCREEN_SIZE or y < 0 or y >= SCREEN_SIZE) return;
    draw(@intCast(x), @intCast(y), draw_color_index);
}

inline fn clip_draw_palette(x: i32, y: i32, palette_index: u2) void {
    if (x < 0 or x >= SCREEN_SIZE or y < 0 or y >= SCREEN_SIZE) return;
    draw_palette(@intCast(x), @intCast(y), palette_index);
}

inline fn draw(x: u8, y: u8, draw_color_index: u2) void {
    const draw_color: u4 = @truncate(DRAW_COLORS.* >> (@as(u4, draw_color_index) << 2));
    if (draw_color == 0) return;
    const palette_index: u2 = @truncate(draw_color - 1);
    draw_palette(x, y, palette_index);
}

inline fn draw_palette(x: u8, y: u8, palette_index: u2) void {
    std.debug.assert(x < SCREEN_SIZE and y < SCREEN_SIZE);
    const buffer_index = x + SCREEN_SIZE * y;
    const shift = @as(u3, @as(u2, @truncate(buffer_index))) << 1;
    const byte = &FRAMEBUFFER[buffer_index >> 2];
    byte.* = (byte.* & ~(@as(u8, 0b11) << shift)) | @as(u8, palette_index) << shift;
}

fn format_user_string(bytes: []const User(u8), comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) @TypeOf(writer).Error!void {
    for (bytes) |*byte| try writer.writeByte(byte.load());
}
inline fn fmt_user_string(bytes: []const User(u8)) std.fmt.Formatter(format_user_string) {
    return .{ .data = bytes };
}

fn User(comptime T: type) type {
    return extern struct {
        const Self = @This();
        const suffix = switch (@sizeOf(T)) {
            1 => "b",
            2 => "h",
            4 => "",
            else => @compileError("loadUser doesn't support " ++ @typeName(T)),
        };

        unsafe: T,

        pub inline fn load(user: *const Self) T {
            return asm ("ldr" ++ suffix ++ "t %[value], [%[pointer]]"
                : [value] "=r" (-> T),
                : [pointer] "r" (&user.unsafe),
            );
        }

        pub inline fn store(user: *Self, value: T) void {
            asm volatile ("str" ++ suffix ++ "t %[value], [%pointer]]"
                :
                : [value] "r" (value),
                  [pointer] "r" (&user.unsafe),
            );
        }
    };
}

const libcart = struct {
    extern var cart_data_start: u8;
    extern var cart_data_end: u8;
    extern var cart_bss_start: u8;
    extern var cart_bss_end: u8;
    extern const cart_data_load_start: u8;

    extern fn start() void;
    extern fn update() void;
};

export fn __return_thunk__() noreturn {
    asm volatile (" svc #12");
    unreachable;
}

pub const SCREEN_SIZE: u32 = 160;

const PALETTE: *[4]u32 = @ptrFromInt(0x20000004);
const DRAW_COLORS: *u16 = @ptrFromInt(0x20000014);
const GAMEPAD1: *u8 = @ptrFromInt(0x20000016);
const GAMEPAD2: *u8 = @ptrFromInt(0x20000017);
const GAMEPAD3: *u8 = @ptrFromInt(0x20000018);
const GAMEPAD4: *u8 = @ptrFromInt(0x20000019);
const MOUSE_X: *i16 = @ptrFromInt(0x2000001a);
const MOUSE_Y: *i16 = @ptrFromInt(0x2000001c);
const MOUSE_BUTTONS: *u8 = @ptrFromInt(0x2000001e);
const SYSTEM_FLAGS: *u8 = @ptrFromInt(0x2000001f);
const NETPLAY: *u8 = @ptrFromInt(0x20000020);
const FRAMEBUFFER: *[6400]u8 = @ptrFromInt(0x200000A0);

const BUTTON_1: u8 = 1;
const BUTTON_2: u8 = 2;
const BUTTON_LEFT: u8 = 16;
const BUTTON_RIGHT: u8 = 32;
const BUTTON_UP: u8 = 64;
const BUTTON_DOWN: u8 = 128;

const MOUSE_LEFT: u8 = 1;
const MOUSE_RIGHT: u8 = 2;
const MOUSE_MIDDLE: u8 = 4;

const SYSTEM_PRESERVE_FRAMEBUFFER: u8 = 1;
const SYSTEM_HIDE_GAMEPAD_OVERLAY: u8 = 2;

pub const BLIT_2BPP: u32 = 1;
pub const BLIT_1BPP: u32 = 0;
pub const BLIT_FLIP_X: u32 = 2;
pub const BLIT_FLIP_Y: u32 = 4;
pub const BLIT_ROTATE: u32 = 8;

const font: [0x100 - ' '][8]u8 = .{ .{
    0b11111111,
    0b11111111,
    0b11111111,
    0b11111111,
    0b11111111,
    0b11111111,
    0b11111111,
    0b11111111,
}, .{
    0b11000111,
    0b11000111,
    0b11000111,
    0b11001111,
    0b11001111,
    0b11111111,
    0b11001111,
    0b11111111,
}, .{
    0b10010011,
    0b10010011,
    0b10010011,
    0b11111111,
    0b11111111,
    0b11111111,
    0b11111111,
    0b11111111,
}, .{
    0b10010011,
    0b00000001,
    0b10010011,
    0b10010011,
    0b10010011,
    0b00000001,
    0b10010011,
    0b11111111,
}, .{
    0b11101111,
    0b10000011,
    0b00101111,
    0b10000011,
    0b11101001,
    0b00000011,
    0b11101111,
    0b11111111,
}, .{
    0b10011101,
    0b01011011,
    0b00110111,
    0b11101111,
    0b11011001,
    0b10110101,
    0b01110011,
    0b11111111,
}, .{
    0b10001111,
    0b00100111,
    0b00100111,
    0b10001111,
    0b00100101,
    0b00110011,
    0b10000001,
    0b11111111,
}, .{
    0b11001111,
    0b11001111,
    0b11001111,
    0b11111111,
    0b11111111,
    0b11111111,
    0b11111111,
    0b11111111,
}, .{
    0b11110011,
    0b11100111,
    0b11001111,
    0b11001111,
    0b11001111,
    0b11100111,
    0b11110011,
    0b11111111,
}, .{
    0b10011111,
    0b11001111,
    0b11100111,
    0b11100111,
    0b11100111,
    0b11001111,
    0b10011111,
    0b11111111,
}, .{
    0b11111111,
    0b10010011,
    0b11000111,
    0b00000001,
    0b11000111,
    0b10010011,
    0b11111111,
    0b11111111,
}, .{
    0b11111111,
    0b11100111,
    0b11100111,
    0b10000001,
    0b11100111,
    0b11100111,
    0b11111111,
    0b11111111,
}, .{
    0b11111111,
    0b11111111,
    0b11111111,
    0b11111111,
    0b11111111,
    0b11001111,
    0b11001111,
    0b10011111,
}, .{
    0b11111111,
    0b11111111,
    0b11111111,
    0b10000001,
    0b11111111,
    0b11111111,
    0b11111111,
    0b11111111,
}, .{
    0b11111111,
    0b11111111,
    0b11111111,
    0b11111111,
    0b11111111,
    0b11001111,
    0b11001111,
    0b11111111,
}, .{
    0b11111101,
    0b11111011,
    0b11110111,
    0b11101111,
    0b11011111,
    0b10111111,
    0b01111111,
    0b11111111,
}, .{
    0b11000111,
    0b10110011,
    0b00111001,
    0b00111001,
    0b00111001,
    0b10011011,
    0b11000111,
    0b11111111,
}, .{
    0b11100111,
    0b11000111,
    0b11100111,
    0b11100111,
    0b11100111,
    0b11100111,
    0b10000001,
    0b11111111,
}, .{
    0b10000011,
    0b00111001,
    0b11110001,
    0b11000011,
    0b10000111,
    0b00011111,
    0b00000001,
    0b11111111,
}, .{
    0b10000001,
    0b11110011,
    0b11100111,
    0b11000011,
    0b11111001,
    0b00111001,
    0b10000011,
    0b11111111,
}, .{
    0b11100011,
    0b11000011,
    0b10010011,
    0b00110011,
    0b00000001,
    0b11110011,
    0b11110011,
    0b11111111,
}, .{
    0b00000011,
    0b00111111,
    0b00000011,
    0b11111001,
    0b11111001,
    0b00111001,
    0b10000011,
    0b11111111,
}, .{
    0b11000011,
    0b10011111,
    0b00111111,
    0b00000011,
    0b00111001,
    0b00111001,
    0b10000011,
    0b11111111,
}, .{
    0b00000001,
    0b00111001,
    0b11110011,
    0b11100111,
    0b11001111,
    0b11001111,
    0b11001111,
    0b11111111,
}, .{
    0b10000111,
    0b00111011,
    0b00011011,
    0b10000111,
    0b01100001,
    0b01111001,
    0b10000011,
    0b11111111,
}, .{
    0b10000011,
    0b00111001,
    0b00111001,
    0b10000001,
    0b11111001,
    0b11110011,
    0b10000111,
    0b11111111,
}, .{
    0b11111111,
    0b11001111,
    0b11001111,
    0b11111111,
    0b11001111,
    0b11001111,
    0b11111111,
    0b11111111,
}, .{
    0b11111111,
    0b11001111,
    0b11001111,
    0b11111111,
    0b11001111,
    0b11001111,
    0b10011111,
    0b11111111,
}, .{
    0b11110011,
    0b11100111,
    0b11001111,
    0b10011111,
    0b11001111,
    0b11100111,
    0b11110011,
    0b11111111,
}, .{
    0b11111111,
    0b11111111,
    0b00000001,
    0b11111111,
    0b00000001,
    0b11111111,
    0b11111111,
    0b11111111,
}, .{
    0b10011111,
    0b11001111,
    0b11100111,
    0b11110011,
    0b11100111,
    0b11001111,
    0b10011111,
    0b11111111,
}, .{
    0b10000011,
    0b00000001,
    0b00111001,
    0b11110011,
    0b11000111,
    0b11111111,
    0b11000111,
    0b11111111,
}, .{
    0b10000011,
    0b01111101,
    0b01000101,
    0b01010101,
    0b01000001,
    0b01111111,
    0b10000011,
    0b11111111,
}, .{
    0b11000111,
    0b10010011,
    0b00111001,
    0b00111001,
    0b00000001,
    0b00111001,
    0b00111001,
    0b11111111,
}, .{
    0b00000011,
    0b00111001,
    0b00111001,
    0b00000011,
    0b00111001,
    0b00111001,
    0b00000011,
    0b11111111,
}, .{
    0b11000011,
    0b10011001,
    0b00111111,
    0b00111111,
    0b00111111,
    0b10011001,
    0b11000011,
    0b11111111,
}, .{
    0b00000111,
    0b00110011,
    0b00111001,
    0b00111001,
    0b00111001,
    0b00110011,
    0b00000111,
    0b11111111,
}, .{
    0b00000001,
    0b00111111,
    0b00111111,
    0b00000011,
    0b00111111,
    0b00111111,
    0b00000001,
    0b11111111,
}, .{
    0b00000001,
    0b00111111,
    0b00111111,
    0b00000011,
    0b00111111,
    0b00111111,
    0b00111111,
    0b11111111,
}, .{
    0b11000001,
    0b10011111,
    0b00111111,
    0b00110001,
    0b00111001,
    0b10011001,
    0b11000001,
    0b11111111,
}, .{
    0b00111001,
    0b00111001,
    0b00111001,
    0b00000001,
    0b00111001,
    0b00111001,
    0b00111001,
    0b11111111,
}, .{
    0b10000001,
    0b11100111,
    0b11100111,
    0b11100111,
    0b11100111,
    0b11100111,
    0b10000001,
    0b11111111,
}, .{
    0b11111001,
    0b11111001,
    0b11111001,
    0b11111001,
    0b11111001,
    0b00111001,
    0b10000011,
    0b11111111,
}, .{
    0b00111001,
    0b00110011,
    0b00100111,
    0b00001111,
    0b00000111,
    0b00100011,
    0b00110001,
    0b11111111,
}, .{
    0b10011111,
    0b10011111,
    0b10011111,
    0b10011111,
    0b10011111,
    0b10011111,
    0b10000001,
    0b11111111,
}, .{
    0b00111001,
    0b00010001,
    0b00000001,
    0b00000001,
    0b00101001,
    0b00111001,
    0b00111001,
    0b11111111,
}, .{
    0b00111001,
    0b00011001,
    0b00001001,
    0b00000001,
    0b00100001,
    0b00110001,
    0b00111001,
    0b11111111,
}, .{
    0b10000011,
    0b00111001,
    0b00111001,
    0b00111001,
    0b00111001,
    0b00111001,
    0b10000011,
    0b11111111,
}, .{
    0b00000011,
    0b00111001,
    0b00111001,
    0b00111001,
    0b00000011,
    0b00111111,
    0b00111111,
    0b11111111,
}, .{
    0b10000011,
    0b00111001,
    0b00111001,
    0b00111001,
    0b00100001,
    0b00110011,
    0b10000101,
    0b11111111,
}, .{
    0b00000011,
    0b00111001,
    0b00111001,
    0b00110001,
    0b00000111,
    0b00100011,
    0b00110001,
    0b11111111,
}, .{
    0b10000111,
    0b00110011,
    0b00111111,
    0b10000011,
    0b11111001,
    0b00111001,
    0b10000011,
    0b11111111,
}, .{
    0b10000001,
    0b11100111,
    0b11100111,
    0b11100111,
    0b11100111,
    0b11100111,
    0b11100111,
    0b11111111,
}, .{
    0b00111001,
    0b00111001,
    0b00111001,
    0b00111001,
    0b00111001,
    0b00111001,
    0b10000011,
    0b11111111,
}, .{
    0b00111001,
    0b00111001,
    0b00111001,
    0b00010001,
    0b10000011,
    0b11000111,
    0b11101111,
    0b11111111,
}, .{
    0b00111001,
    0b00111001,
    0b00101001,
    0b00000001,
    0b00000001,
    0b00010001,
    0b00111001,
    0b11111111,
}, .{
    0b00111001,
    0b00010001,
    0b10000011,
    0b11000111,
    0b10000011,
    0b00010001,
    0b00111001,
    0b11111111,
}, .{
    0b10011001,
    0b10011001,
    0b10011001,
    0b11000011,
    0b11100111,
    0b11100111,
    0b11100111,
    0b11111111,
}, .{
    0b00000001,
    0b11110001,
    0b11100011,
    0b11000111,
    0b10001111,
    0b00011111,
    0b00000001,
    0b11111111,
}, .{
    0b11000011,
    0b11001111,
    0b11001111,
    0b11001111,
    0b11001111,
    0b11001111,
    0b11000011,
    0b11111111,
}, .{
    0b01111111,
    0b10111111,
    0b11011111,
    0b11101111,
    0b11110111,
    0b11111011,
    0b11111101,
    0b11111111,
}, .{
    0b10000111,
    0b11100111,
    0b11100111,
    0b11100111,
    0b11100111,
    0b11100111,
    0b10000111,
    0b11111111,
}, .{
    0b11000111,
    0b10010011,
    0b11111111,
    0b11111111,
    0b11111111,
    0b11111111,
    0b11111111,
    0b11111111,
}, .{
    0b11111111,
    0b11111111,
    0b11111111,
    0b11111111,
    0b11111111,
    0b11111111,
    0b11111111,
    0b00000001,
}, .{
    0b11101111,
    0b11110111,
    0b11111111,
    0b11111111,
    0b11111111,
    0b11111111,
    0b11111111,
    0b11111111,
}, .{
    0b11111111,
    0b11111111,
    0b10000011,
    0b11111001,
    0b10000001,
    0b00111001,
    0b10000001,
    0b11111111,
}, .{
    0b00111111,
    0b00111111,
    0b00000011,
    0b00111001,
    0b00111001,
    0b00111001,
    0b10000011,
    0b11111111,
}, .{
    0b11111111,
    0b11111111,
    0b10000001,
    0b00111111,
    0b00111111,
    0b00111111,
    0b10000001,
    0b11111111,
}, .{
    0b11111001,
    0b11111001,
    0b10000001,
    0b00111001,
    0b00111001,
    0b00111001,
    0b10000001,
    0b11111111,
}, .{
    0b11111111,
    0b11111111,
    0b10000011,
    0b00111001,
    0b00000001,
    0b00111111,
    0b10000011,
    0b11111111,
}, .{
    0b11110001,
    0b11100111,
    0b10000001,
    0b11100111,
    0b11100111,
    0b11100111,
    0b11100111,
    0b11111111,
}, .{
    0b11111111,
    0b11111111,
    0b10000001,
    0b00111001,
    0b00111001,
    0b10000001,
    0b11111001,
    0b10000011,
}, .{
    0b00111111,
    0b00111111,
    0b00000011,
    0b00111001,
    0b00111001,
    0b00111001,
    0b00111001,
    0b11111111,
}, .{
    0b11100111,
    0b11111111,
    0b11000111,
    0b11100111,
    0b11100111,
    0b11100111,
    0b10000001,
    0b11111111,
}, .{
    0b11110011,
    0b11111111,
    0b11100011,
    0b11110011,
    0b11110011,
    0b11110011,
    0b11110011,
    0b10000111,
}, .{
    0b00111111,
    0b00111111,
    0b00110001,
    0b00000011,
    0b00000111,
    0b00100011,
    0b00110001,
    0b11111111,
}, .{
    0b11000111,
    0b11100111,
    0b11100111,
    0b11100111,
    0b11100111,
    0b11100111,
    0b10000001,
    0b11111111,
}, .{
    0b11111111,
    0b11111111,
    0b00000011,
    0b01001001,
    0b01001001,
    0b01001001,
    0b01001001,
    0b11111111,
}, .{
    0b11111111,
    0b11111111,
    0b00000011,
    0b00111001,
    0b00111001,
    0b00111001,
    0b00111001,
    0b11111111,
}, .{
    0b11111111,
    0b11111111,
    0b10000011,
    0b00111001,
    0b00111001,
    0b00111001,
    0b10000011,
    0b11111111,
}, .{
    0b11111111,
    0b11111111,
    0b00000011,
    0b00111001,
    0b00111001,
    0b00000011,
    0b00111111,
    0b00111111,
}, .{
    0b11111111,
    0b11111111,
    0b10000001,
    0b00111001,
    0b00111001,
    0b10000001,
    0b11111001,
    0b11111001,
}, .{
    0b11111111,
    0b11111111,
    0b10010001,
    0b10001111,
    0b10011111,
    0b10011111,
    0b10011111,
    0b11111111,
}, .{
    0b11111111,
    0b11111111,
    0b10000011,
    0b00111111,
    0b10000011,
    0b11111001,
    0b00000011,
    0b11111111,
}, .{
    0b11100111,
    0b11100111,
    0b10000001,
    0b11100111,
    0b11100111,
    0b11100111,
    0b11100111,
    0b11111111,
}, .{
    0b11111111,
    0b11111111,
    0b00111001,
    0b00111001,
    0b00111001,
    0b00111001,
    0b10000001,
    0b11111111,
}, .{
    0b11111111,
    0b11111111,
    0b10011001,
    0b10011001,
    0b10011001,
    0b11000011,
    0b11100111,
    0b11111111,
}, .{
    0b11111111,
    0b11111111,
    0b01001001,
    0b01001001,
    0b01001001,
    0b01001001,
    0b10000001,
    0b11111111,
}, .{
    0b11111111,
    0b11111111,
    0b00111001,
    0b00000001,
    0b11000111,
    0b00000001,
    0b00111001,
    0b11111111,
}, .{
    0b11111111,
    0b11111111,
    0b00111001,
    0b00111001,
    0b00111001,
    0b10000001,
    0b11111001,
    0b10000011,
}, .{
    0b11111111,
    0b11111111,
    0b00000001,
    0b11100011,
    0b11000111,
    0b10001111,
    0b00000001,
    0b11111111,
}, .{
    0b11110011,
    0b11100111,
    0b11100111,
    0b11001111,
    0b11100111,
    0b11100111,
    0b11110011,
    0b11111111,
}, .{
    0b11100111,
    0b11100111,
    0b11100111,
    0b11100111,
    0b11100111,
    0b11100111,
    0b11100111,
    0b11111111,
}, .{
    0b10011111,
    0b11001111,
    0b11001111,
    0b11100111,
    0b11001111,
    0b11001111,
    0b10011111,
    0b11111111,
}, .{
    0b11111111,
    0b11111111,
    0b10001111,
    0b01000101,
    0b11100011,
    0b11111111,
    0b11111111,
    0b11111111,
}, .{
    0b11111111,
    0b11111111,
    0b11111111,
    0b11111111,
    0b11111111,
    0b10010011,
    0b10010011,
    0b11111111,
}, .{
    0b10000011,
    0b00010001,
    0b00101001,
    0b00111001,
    0b00101001,
    0b00101001,
    0b10000011,
    0b11111111,
}, .{
    0b10000011,
    0b00110001,
    0b00101001,
    0b00110001,
    0b00101001,
    0b00110001,
    0b10000011,
    0b11111111,
}, .{
    0b10000011,
    0b00010001,
    0b00010001,
    0b01111101,
    0b00010001,
    0b00010001,
    0b10000011,
    0b11111111,
}, .{
    0b10000011,
    0b00000001,
    0b00000001,
    0b01111101,
    0b00000001,
    0b00000001,
    0b10000011,
    0b11111111,
}, .{
    0b10000011,
    0b00010001,
    0b00100001,
    0b01111101,
    0b00100001,
    0b00010001,
    0b10000011,
    0b11111111,
}, .{
    0b10000011,
    0b00010001,
    0b00001001,
    0b01111101,
    0b00001001,
    0b00010001,
    0b10000011,
    0b11111111,
}, .{
    0b10000011,
    0b00010001,
    0b00111001,
    0b01010101,
    0b00010001,
    0b00010001,
    0b10000011,
    0b11111111,
}, .{
    0b10000011,
    0b00010001,
    0b00010001,
    0b01010101,
    0b00111001,
    0b00010001,
    0b10000011,
    0b11111111,
}, .{
    0b11111111,
    0b11111111,
    0b11111111,
    0b11111111,
    0b11111111,
    0b11111111,
    0b11111111,
    0b11111111,
}, .{
    0b11111111,
    0b11111111,
    0b11111111,
    0b11111111,
    0b11111111,
    0b11111111,
    0b11111111,
    0b11111111,
}, .{
    0b11111111,
    0b11111111,
    0b11111111,
    0b11111111,
    0b11111111,
    0b11111111,
    0b11111111,
    0b11111111,
}, .{
    0b11111111,
    0b11111111,
    0b11111111,
    0b11111111,
    0b11111111,
    0b11111111,
    0b11111111,
    0b11111111,
}, .{
    0b11111111,
    0b11111111,
    0b11111111,
    0b11111111,
    0b11111111,
    0b11111111,
    0b11111111,
    0b11111111,
}, .{
    0b11111111,
    0b11111111,
    0b11111111,
    0b11111111,
    0b11111111,
    0b11111111,
    0b11111111,
    0b11111111,
}, .{
    0b11111111,
    0b11111111,
    0b11111111,
    0b11111111,
    0b11111111,
    0b11111111,
    0b11111111,
    0b11111111,
}, .{
    0b11111111,
    0b11111111,
    0b11111111,
    0b11111111,
    0b11111111,
    0b11111111,
    0b11111111,
    0b11111111,
}, .{
    0b11111111,
    0b11111111,
    0b11111111,
    0b11111111,
    0b11111111,
    0b11111111,
    0b11111111,
    0b11111111,
}, .{
    0b11111111,
    0b11111111,
    0b11111111,
    0b11111111,
    0b11111111,
    0b11111111,
    0b11111111,
    0b11111111,
}, .{
    0b11111111,
    0b11111111,
    0b11111111,
    0b11111111,
    0b11111111,
    0b11111111,
    0b11111111,
    0b11111111,
}, .{
    0b11111111,
    0b11111111,
    0b11111111,
    0b11111111,
    0b11111111,
    0b11111111,
    0b11111111,
    0b11111111,
}, .{
    0b11111111,
    0b11111111,
    0b11111111,
    0b11111111,
    0b11111111,
    0b11111111,
    0b11111111,
    0b11111111,
}, .{
    0b11111111,
    0b11111111,
    0b11111111,
    0b11111111,
    0b11111111,
    0b11111111,
    0b11111111,
    0b11111111,
}, .{
    0b11111111,
    0b11111111,
    0b11111111,
    0b11111111,
    0b11111111,
    0b11111111,
    0b11111111,
    0b11111111,
}, .{
    0b11111111,
    0b11111111,
    0b11111111,
    0b11111111,
    0b11111111,
    0b11111111,
    0b11111111,
    0b11111111,
}, .{
    0b11111111,
    0b11111111,
    0b11111111,
    0b11111111,
    0b11111111,
    0b11111111,
    0b11111111,
    0b11111111,
}, .{
    0b11111111,
    0b11111111,
    0b11111111,
    0b11111111,
    0b11111111,
    0b11111111,
    0b11111111,
    0b11111111,
}, .{
    0b11111111,
    0b11111111,
    0b11111111,
    0b11111111,
    0b11111111,
    0b11111111,
    0b11111111,
    0b11111111,
}, .{
    0b11111111,
    0b11111111,
    0b11111111,
    0b11111111,
    0b11111111,
    0b11111111,
    0b11111111,
    0b11111111,
}, .{
    0b11111111,
    0b11111111,
    0b11111111,
    0b11111111,
    0b11111111,
    0b11111111,
    0b11111111,
    0b11111111,
}, .{
    0b11111111,
    0b11111111,
    0b11111111,
    0b11111111,
    0b11111111,
    0b11111111,
    0b11111111,
    0b11111111,
}, .{
    0b11111111,
    0b11111111,
    0b11111111,
    0b11111111,
    0b11111111,
    0b11111111,
    0b11111111,
    0b11111111,
}, .{
    0b11111111,
    0b11111111,
    0b11111111,
    0b11111111,
    0b11111111,
    0b11111111,
    0b11111111,
    0b11111111,
}, .{
    0b11111111,
    0b11111111,
    0b11111111,
    0b11111111,
    0b11111111,
    0b11111111,
    0b11111111,
    0b11111111,
}, .{
    0b11100111,
    0b11111111,
    0b11100111,
    0b11100111,
    0b11000111,
    0b11000111,
    0b11000111,
    0b11111111,
}, .{
    0b11101111,
    0b10000011,
    0b00101001,
    0b00101111,
    0b00101001,
    0b10000011,
    0b11101111,
    0b11111111,
}, .{
    0b11000011,
    0b10011001,
    0b10011111,
    0b00000011,
    0b10011111,
    0b10011111,
    0b00000001,
    0b11111111,
}, .{
    0b11111111,
    0b10100101,
    0b11011011,
    0b11011011,
    0b11011011,
    0b10100101,
    0b11111111,
    0b11111111,
}, .{
    0b10011001,
    0b10011001,
    0b11000011,
    0b10000001,
    0b11100111,
    0b10000001,
    0b11100111,
    0b11111111,
}, .{
    0b11100111,
    0b11100111,
    0b11100111,
    0b11111111,
    0b11100111,
    0b11100111,
    0b11100111,
    0b11111111,
}, .{
    0b11000011,
    0b10011001,
    0b10000111,
    0b11011011,
    0b11100001,
    0b10011001,
    0b11000011,
    0b11111111,
}, .{
    0b10010011,
    0b11111111,
    0b11111111,
    0b11111111,
    0b11111111,
    0b11111111,
    0b11111111,
    0b11111111,
}, .{
    0b11000011,
    0b10111101,
    0b01100110,
    0b01011110,
    0b01011110,
    0b01100110,
    0b10111101,
    0b11000011,
}, .{
    0b10000111,
    0b11000011,
    0b10010011,
    0b11000011,
    0b11111111,
    0b11111111,
    0b11111111,
    0b11111111,
}, .{
    0b11111111,
    0b11001001,
    0b10010011,
    0b00100111,
    0b10010011,
    0b11001001,
    0b11111111,
    0b11111111,
}, .{
    0b11111111,
    0b11111111,
    0b10000001,
    0b11111001,
    0b11111001,
    0b11111111,
    0b11111111,
    0b11111111,
}, .{
    0b11111111,
    0b11111111,
    0b11111111,
    0b11111111,
    0b11111111,
    0b11111111,
    0b11111111,
    0b11111111,
}, .{
    0b11000011,
    0b10111101,
    0b01000110,
    0b01011010,
    0b01000110,
    0b01011010,
    0b10111101,
    0b11000011,
}, .{
    0b10000011,
    0b11111111,
    0b11111111,
    0b11111111,
    0b11111111,
    0b11111111,
    0b11111111,
    0b11111111,
}, .{
    0b11101111,
    0b11010111,
    0b11101111,
    0b11111111,
    0b11111111,
    0b11111111,
    0b11111111,
    0b11111111,
}, .{
    0b11100111,
    0b11100111,
    0b10000001,
    0b11100111,
    0b11100111,
    0b11111111,
    0b10000001,
    0b11111111,
}, .{
    0b11000111,
    0b11110011,
    0b11100111,
    0b11000011,
    0b11111111,
    0b11111111,
    0b11111111,
    0b11111111,
}, .{
    0b11000011,
    0b11100111,
    0b11110011,
    0b11000111,
    0b11111111,
    0b11111111,
    0b11111111,
    0b11111111,
}, .{
    0b11110111,
    0b11101111,
    0b11111111,
    0b11111111,
    0b11111111,
    0b11111111,
    0b11111111,
    0b11111111,
}, .{
    0b11111111,
    0b11111111,
    0b00110011,
    0b00110011,
    0b00110011,
    0b00110011,
    0b00001001,
    0b00111111,
}, .{
    0b11000001,
    0b10010101,
    0b10110101,
    0b10010101,
    0b11000001,
    0b11110101,
    0b11110101,
    0b11111111,
}, .{
    0b11111111,
    0b11111111,
    0b11111111,
    0b11001111,
    0b11001111,
    0b11111111,
    0b11111111,
    0b11111111,
}, .{
    0b11111111,
    0b11111111,
    0b11111111,
    0b11111111,
    0b11111111,
    0b11111111,
    0b11110111,
    0b11001111,
}, .{
    0b11100111,
    0b11000111,
    0b11100111,
    0b11000011,
    0b11111111,
    0b11111111,
    0b11111111,
    0b11111111,
}, .{
    0b11000111,
    0b10010011,
    0b10010011,
    0b11000111,
    0b11111111,
    0b11111111,
    0b11111111,
    0b11111111,
}, .{
    0b11111111,
    0b00100111,
    0b10010011,
    0b11001001,
    0b10010011,
    0b00100111,
    0b11111111,
    0b11111111,
}, .{
    0b10111101,
    0b00111011,
    0b10110111,
    0b10101101,
    0b11011001,
    0b10110001,
    0b01111101,
    0b11111111,
}, .{
    0b10111101,
    0b00111011,
    0b10110111,
    0b10101001,
    0b11011101,
    0b10111011,
    0b01110001,
    0b11111111,
}, .{
    0b00011101,
    0b10111011,
    0b11010111,
    0b00101101,
    0b11011001,
    0b10110001,
    0b01111101,
    0b11111111,
}, .{
    0b11000111,
    0b11111111,
    0b11000111,
    0b10011111,
    0b00111001,
    0b00000001,
    0b10000011,
    0b11111111,
}, .{
    0b11011111,
    0b11101111,
    0b11000111,
    0b10010011,
    0b00111001,
    0b00000001,
    0b00111001,
    0b11111111,
}, .{
    0b11110111,
    0b11101111,
    0b11000111,
    0b10010011,
    0b00111001,
    0b00000001,
    0b00111001,
    0b11111111,
}, .{
    0b11000111,
    0b10010011,
    0b11000111,
    0b10010011,
    0b00111001,
    0b00000001,
    0b00111001,
    0b11111111,
}, .{
    0b11001011,
    0b10100111,
    0b11000111,
    0b10010011,
    0b00111001,
    0b00000001,
    0b00111001,
    0b11111111,
}, .{
    0b10010011,
    0b11111111,
    0b11000111,
    0b10010011,
    0b00111001,
    0b00000001,
    0b00111001,
    0b11111111,
}, .{
    0b11101111,
    0b11010111,
    0b11000111,
    0b10010011,
    0b00111001,
    0b00000001,
    0b00111001,
    0b11111111,
}, .{
    0b11000001,
    0b10000111,
    0b00100111,
    0b00100001,
    0b00000111,
    0b00100111,
    0b00100001,
    0b11111111,
}, .{
    0b11000011,
    0b10011001,
    0b00111111,
    0b00111111,
    0b10011001,
    0b11000011,
    0b11110111,
    0b11001111,
}, .{
    0b11011111,
    0b11101111,
    0b00000001,
    0b00111111,
    0b00000011,
    0b00111111,
    0b00000001,
    0b11111111,
}, .{
    0b11110111,
    0b11101111,
    0b00000001,
    0b00111111,
    0b00000011,
    0b00111111,
    0b00000001,
    0b11111111,
}, .{
    0b11000111,
    0b10010011,
    0b00000001,
    0b00111111,
    0b00000011,
    0b00111111,
    0b00000001,
    0b11111111,
}, .{
    0b10010011,
    0b11111111,
    0b00000001,
    0b00111111,
    0b00000011,
    0b00111111,
    0b00000001,
    0b11111111,
}, .{
    0b11101111,
    0b11110111,
    0b10000001,
    0b11100111,
    0b11100111,
    0b11100111,
    0b10000001,
    0b11111111,
}, .{
    0b11110111,
    0b11101111,
    0b10000001,
    0b11100111,
    0b11100111,
    0b11100111,
    0b10000001,
    0b11111111,
}, .{
    0b11100111,
    0b11000011,
    0b10000001,
    0b11100111,
    0b11100111,
    0b11100111,
    0b10000001,
    0b11111111,
}, .{
    0b10011001,
    0b11111111,
    0b10000001,
    0b11100111,
    0b11100111,
    0b11100111,
    0b10000001,
    0b11111111,
}, .{
    0b10000111,
    0b10010011,
    0b10011001,
    0b00001001,
    0b10011001,
    0b10010011,
    0b10000111,
    0b11111111,
}, .{
    0b11001011,
    0b10100111,
    0b00011001,
    0b00001001,
    0b00000001,
    0b00100001,
    0b00110001,
    0b11111111,
}, .{
    0b11011111,
    0b11101111,
    0b10000011,
    0b00111001,
    0b00111001,
    0b00111001,
    0b10000011,
    0b11111111,
}, .{
    0b11110111,
    0b11101111,
    0b10000011,
    0b00111001,
    0b00111001,
    0b00111001,
    0b10000011,
    0b11111111,
}, .{
    0b11000111,
    0b10010011,
    0b10000011,
    0b00111001,
    0b00111001,
    0b00111001,
    0b10000011,
    0b11111111,
}, .{
    0b11001011,
    0b10100111,
    0b10000011,
    0b00111001,
    0b00111001,
    0b00111001,
    0b10000011,
    0b11111111,
}, .{
    0b10010011,
    0b11111111,
    0b10000011,
    0b00111001,
    0b00111001,
    0b00111001,
    0b10000011,
    0b11111111,
}, .{
    0b11111111,
    0b10111011,
    0b11010111,
    0b11101111,
    0b11010111,
    0b10111011,
    0b11111111,
    0b11111111,
}, .{
    0b10000011,
    0b00111001,
    0b00110001,
    0b00101001,
    0b00011001,
    0b00111001,
    0b10000011,
    0b11111111,
}, .{
    0b11011111,
    0b11101111,
    0b00111001,
    0b00111001,
    0b00111001,
    0b00111001,
    0b10000011,
    0b11111111,
}, .{
    0b11110111,
    0b11101111,
    0b00111001,
    0b00111001,
    0b00111001,
    0b00111001,
    0b10000011,
    0b11111111,
}, .{
    0b11000111,
    0b10010011,
    0b11111111,
    0b00111001,
    0b00111001,
    0b00111001,
    0b10000011,
    0b11111111,
}, .{
    0b10010011,
    0b11111111,
    0b00111001,
    0b00111001,
    0b00111001,
    0b00111001,
    0b10000011,
    0b11111111,
}, .{
    0b11110111,
    0b11101111,
    0b10011001,
    0b10011001,
    0b11000011,
    0b11100111,
    0b11100111,
    0b11111111,
}, .{
    0b00111111,
    0b00000011,
    0b00111001,
    0b00111001,
    0b00111001,
    0b00000011,
    0b00111111,
    0b11111111,
}, .{
    0b11000011,
    0b10011001,
    0b10011001,
    0b10010011,
    0b10011001,
    0b10001001,
    0b10010011,
    0b11111111,
}, .{
    0b11011111,
    0b11101111,
    0b10000011,
    0b11111001,
    0b10000001,
    0b00111001,
    0b10000001,
    0b11111111,
}, .{
    0b11110111,
    0b11101111,
    0b10000011,
    0b11111001,
    0b10000001,
    0b00111001,
    0b10000001,
    0b11111111,
}, .{
    0b11000111,
    0b10010011,
    0b10000011,
    0b11111001,
    0b10000001,
    0b00111001,
    0b10000001,
    0b11111111,
}, .{
    0b11001011,
    0b10100111,
    0b10000011,
    0b11111001,
    0b10000001,
    0b00111001,
    0b10000001,
    0b11111111,
}, .{
    0b10010011,
    0b11111111,
    0b10000011,
    0b11111001,
    0b10000001,
    0b00111001,
    0b10000001,
    0b11111111,
}, .{
    0b11101111,
    0b11010111,
    0b10000011,
    0b11111001,
    0b10000001,
    0b00111001,
    0b10000001,
    0b11111111,
}, .{
    0b11111111,
    0b11111111,
    0b10000011,
    0b11101001,
    0b10000001,
    0b00101111,
    0b10000011,
    0b11111111,
}, .{
    0b11111111,
    0b11111111,
    0b10000001,
    0b00111111,
    0b00111111,
    0b10000001,
    0b11110111,
    0b11001111,
}, .{
    0b11011111,
    0b11101111,
    0b10000011,
    0b00111001,
    0b00000001,
    0b00111111,
    0b10000011,
    0b11111111,
}, .{
    0b11110111,
    0b11101111,
    0b10000011,
    0b00111001,
    0b00000001,
    0b00111111,
    0b10000011,
    0b11111111,
}, .{
    0b11000111,
    0b10010011,
    0b10000011,
    0b00111001,
    0b00000001,
    0b00111111,
    0b10000011,
    0b11111111,
}, .{
    0b10010011,
    0b11111111,
    0b10000011,
    0b00111001,
    0b00000001,
    0b00111111,
    0b10000011,
    0b11111111,
}, .{
    0b11011111,
    0b11101111,
    0b11111111,
    0b11000111,
    0b11100111,
    0b11100111,
    0b10000001,
    0b11111111,
}, .{
    0b11110111,
    0b11101111,
    0b11111111,
    0b11000111,
    0b11100111,
    0b11100111,
    0b10000001,
    0b11111111,
}, .{
    0b11000111,
    0b10010011,
    0b11111111,
    0b11000111,
    0b11100111,
    0b11100111,
    0b10000001,
    0b11111111,
}, .{
    0b10010011,
    0b11111111,
    0b11000111,
    0b11100111,
    0b11100111,
    0b11100111,
    0b10000001,
    0b11111111,
}, .{
    0b10011011,
    0b10000111,
    0b01100111,
    0b10000011,
    0b00111001,
    0b00111001,
    0b10000011,
    0b11111111,
}, .{
    0b11001011,
    0b10100111,
    0b00000011,
    0b00111001,
    0b00111001,
    0b00111001,
    0b00111001,
    0b11111111,
}, .{
    0b11011111,
    0b11101111,
    0b10000011,
    0b00111001,
    0b00111001,
    0b00111001,
    0b10000011,
    0b11111111,
}, .{
    0b11110111,
    0b11101111,
    0b10000011,
    0b00111001,
    0b00111001,
    0b00111001,
    0b10000011,
    0b11111111,
}, .{
    0b11000111,
    0b10010011,
    0b10000011,
    0b00111001,
    0b00111001,
    0b00111001,
    0b10000011,
    0b11111111,
}, .{
    0b11001011,
    0b10100111,
    0b10000011,
    0b00111001,
    0b00111001,
    0b00111001,
    0b10000011,
    0b11111111,
}, .{
    0b10010011,
    0b11111111,
    0b10000011,
    0b00111001,
    0b00111001,
    0b00111001,
    0b10000011,
    0b11111111,
}, .{
    0b11111111,
    0b11100111,
    0b11111111,
    0b10000001,
    0b11111111,
    0b11100111,
    0b11111111,
    0b11111111,
}, .{
    0b11111111,
    0b11111111,
    0b10000011,
    0b00110001,
    0b00101001,
    0b00011001,
    0b10000011,
    0b11111111,
}, .{
    0b11011111,
    0b11101111,
    0b00111001,
    0b00111001,
    0b00111001,
    0b00111001,
    0b10000001,
    0b11111111,
}, .{
    0b11110111,
    0b11101111,
    0b00111001,
    0b00111001,
    0b00111001,
    0b00111001,
    0b10000001,
    0b11111111,
}, .{
    0b11000111,
    0b10010011,
    0b11111111,
    0b00111001,
    0b00111001,
    0b00111001,
    0b10000001,
    0b11111111,
}, .{
    0b10010011,
    0b11111111,
    0b00111001,
    0b00111001,
    0b00111001,
    0b00111001,
    0b10000001,
    0b11111111,
}, .{
    0b11110111,
    0b11101111,
    0b00111001,
    0b00111001,
    0b00111001,
    0b10000001,
    0b11111001,
    0b10000011,
}, .{
    0b00111111,
    0b00111111,
    0b00000011,
    0b00111001,
    0b00111001,
    0b00000011,
    0b00111111,
    0b00111111,
}, .{
    0b10010011,
    0b11111111,
    0b00111001,
    0b00111001,
    0b00111001,
    0b10000001,
    0b11111001,
    0b10000011,
} };

const audio = @import("audio.zig");
const lcd = @import("lcd.zig");
const Port = @import("Port.zig");
const std = @import("std");
const timer = @import("timer.zig");
const utils = @import("utils.zig");
