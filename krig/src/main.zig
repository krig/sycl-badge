const std = @import("std");
const fmt = std.fmt;
const cart = @import("cart-api");

export fn start() void {}

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

inline fn rgb565(clr: cart.NeopixelColor) cart.DisplayColor {
    return .{
        .r = @intCast(clr.r / 8),
        .g = @intCast(clr.g / 4),
        .b = @intCast(clr.b / 8),
    };
}

var ticks: u8 = 0;

export fn update() void {
    set_background();

    cart.rect(.{
        .x = @intCast(cart.screen_width / 2 - 50),
        .y = @intCast(cart.screen_height / 2 - 25),
        .width = 100,
        .height = 50,
        .stroke_color = rgb565(ziggy8),
        .fill_color = rgb565(zig),
    });

    const slowTick: u8 = @intCast(ticks / 4);

    var buf: [32]u8 = undefined;
    _ = fmt.bufPrint(&buf, "{d}\n", .{slowTick}) catch "err";

    cart.text(.{
        .str = &buf,
        .x = 4,
        .y = 4,
        .text_color = rgb565(white),
    });

    cart.red_led.* = !cart.red_led.*;

    ticks +%= 1;
}

fn set_background() void {
    const ratio = (4095 - @as(f32, @floatFromInt(cart.light_level.*))) / 4095 * 0.2;

    @memset(cart.framebuffer, cart.DisplayColor{
        .r = @intFromFloat(ratio * 31),
        .g = @intFromFloat(ratio * 63),
        .b = @intFromFloat(ratio * 31),
    });
}
