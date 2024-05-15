const std = @import("std");
const fmt = std.fmt;
const cart = @import("cart-api");


const black = defColor(0x000000);
const white = defColor(0xffffff);
const zig = defColor(0xF7A41D);
const red = defColor(0xFF0000);
const green = defColor(0x00FF00);
const blue = defColor(0x0000FF);
const ziggy1 = defColor(0xf98a31);
const ziggy3 = defColor(0xe56c2c);
const ziggy4 = defColor(0xf15a29);
const ziggy5 = defColor(0xc54827);
const ziggy6 = defColor(0xfbb040);
const ziggy7 = defColor(0xf09d2e);
const ziggy8 = defColor(0xeaebec);
const ziggy2 = defColor(0x231f20);
const ziggy9 = defColor(0x212121);


inline fn defColor(rgb: u24) cart.NeopixelColor {
    return .{
        .r = @intCast((rgb >> 16) & 0xff),
        .g = @intCast((rgb >> 8) & 0xff),
        .b = @intCast(rgb & 0xff),
    };
}

inline fn blend(from: cart.NeopixelColor, to: cart.NeopixelColor, f: f32) cart.NeopixelColor {
    return .{
        .r = @intFromFloat((from.r * (1.0 - f)) + (to.r * f)),
        .g = @intFromFloat((from.g * (1.0 - f)) + (to.g * f)),
        .b = @intFromFloat((from.b * (1.0 - f)) + (to.b * f)),
    };
}

inline fn rgb565(clr: cart.NeopixelColor) cart.DisplayColor {
    return .{
        .r = @intCast(clr.r / 8),
        .g = @intCast(clr.g / 4),
        .b = @intCast(clr.b / 8),
    };
}

const numLines = 8;
var lines: [numLines]f32 = undefined;
var lineColor: [numLines]cart.NeopixelColor = undefined;

export fn start() void {
    for (lines, 0..) |_, i| {
        const v = @as(f32, @floatFromInt(i)) / numLines;
        lines[i] = v;
        lineColor[i] = blend(black, zig, 0.2 + v*0.8);
    }
}

export fn update() void {
    set_background();

    const half_h: u8 = @intCast(cart.screen_height / 2);

    const speed: f32 = 0.008;
    for (lines, 0..) |life, i| {
        var newlife = life + speed;
        if (newlife >= 1.0) newlife = 0.0;
        const iclr: u8 = @intFromFloat(newlife * numLines);
        const ipos: u32 = @intFromFloat((newlife*newlife) * half_h);
        const drawpos: u8 = @intCast(ipos % @as(u32, half_h));
        cart.line(.{
            .x1 = 0,
            .y1 = @intCast(half_h + drawpos),
            .x2 = cart.screen_width - 1,
            .y2 = @intCast(half_h + drawpos),
            .color = rgb565(lineColor[iclr]),
        });
        lines[i] = newlife;
    }

    cart.red_led.* = !cart.red_led.*;
}

fn set_background() void {
    const ratio = (4095 - @as(f32, @floatFromInt(cart.light_level.*))) / 4095 * 0.2;

    @memset(cart.framebuffer, cart.DisplayColor{
        .r = @intFromFloat(ratio * 31),
        .g = @intFromFloat(ratio * 63),
        .b = @intFromFloat(ratio * 31),
    });
}
