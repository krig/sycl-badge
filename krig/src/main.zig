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
const ziggy2 = defColor(0x231f20);
const ziggy8 = defColor(0xeaebec);
const light = defColor(0x555555);
const dark = defColor(0x222222);

const shipTop = defColor(0xF7A41D);
// const shipBottom = defColor(0xf58f0a);
const shipBottom = defColor(0xc37b07);

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

const Star = struct {
    x: f32,
    y: f32,
    speed: f32,
    color: cart.DisplayColor,
};

var rand_seed: u16 = 5381;
fn rand_float() f32 {
    rand_seed = std.math.rotl(u16, rand_seed, 5) +% rand_seed;
    return @as(f32, @floatFromInt(rand_seed)) / @as(f32, std.math.maxInt(u16)); 
}

const NumStars = 32;
var starfield: [NumStars]Star = undefined;

const Player = struct {
    x: f32,
    y: f32,
    speed: f32,
    health: u8,
    cooldown: u8,
};
var player: Player = undefined;
const MaxHealth: u8 = 5;

const BulletType = enum {
    dot,
    cross,
    ball,
};

const Bullet = struct {
    x: f32,
    y: f32,
    dx: f32,
    dy: f32,
    typ: BulletType,
    live: bool,
};
const MaxBullets = 64;
var bullets: [MaxBullets]Bullet = undefined;

export fn start() void {
    for (&starfield) |*star| {
        const speed = rand_float();
        star.* = .{
            .x = rand_float() * cart.screen_width,
            .y = rand_float() * cart.screen_height,
            .speed = speed,
            .color = rgb565(blend(dark, light, speed)),
        };
    }
    for (&bullets) |*bullet| bullet.*.live = false;
    player = .{
        .x = 8.0,
        .y = cart.screen_height / 2,
        .speed = 0.0,
        .health = MaxHealth,
        .cooldown = 0,
    };
}

fn draw_stars() void {
    const shaky = (player.y / cart.screen_height) * -15.0;
    for (&starfield) |*star| {
        cart.hline(.{
            .x = @intFromFloat(star.*.x),
            .y = @intFromFloat(star.*.y + shaky * star.*.speed),
            .len = @intFromFloat(star.*.speed * 4.0 + 1.0),
            .color = star.*.color,
        });
        var x = star.*.x - star.*.speed * 2.0;
        if (x < 0.0) x = @floatFromInt(cart.screen_width);
        star.*.x = x;
    }
}

fn spawn_bullet(bullet: Bullet) void {
    for (&bullets) |*b| {
        if (b.live) continue;
        b.* = bullet;
        break;
    }
}

fn draw_bullets() void {
    // move all live bullets
    // if player is firing: spawn new bullet
    if (cart.controls.a) {
        if (player.cooldown > 0) {
            player.cooldown -= 1;
        } else {
            player.cooldown = 4;
            spawn_bullet(.{
                .x = player.x + 7.0 + (rand_float() - 0.5) * 3.0,
                .y = player.y + (rand_float() - 0.5),
                .dx = 3.0 + (rand_float() * 0.2),
                .dy = 0.5 * (rand_float() - 0.5),
                .typ = .dot,
                .live = true,
            });
        }
    }
    for (&bullets) |*bullet| {
        if (!bullet.live) continue;
        bullet.*.x += bullet.dx;
        bullet.*.y += bullet.dy;
        if (bullet.x > cart.screen_width) bullet.*.live = false;
        if (bullet.y > cart.screen_height) bullet.*.live = false;
        if (bullet.x < 0) bullet.*.live = false;
        if (bullet.y < 0) bullet.*.live = false;
        if (bullet.live) {
            if (bullet.typ == .dot) {
                cart.rect(.{
                    .x = @intFromFloat(bullet.x),
                    .y = @intFromFloat(bullet.y),
                    .width = 1,
                    .height = 1,
                    .fill_color = rgb565(white),
                });
            } else {
                cart.hline(.{
                    .x = @intFromFloat(bullet.x - 1),
                    .y = @intFromFloat(bullet.y),
                    .len = 3,
                    .color = rgb565(white),
                });
                cart.vline(.{
                    .x = @intFromFloat(bullet.x),
                    .y = @intFromFloat(bullet.y - 1),
                    .len = 3,
                    .color = rgb565(white),
                });
            }
        }
    }
}

fn draw_player() void {
    if (cart.controls.up) {
        player.speed = @max(-3.0, player.speed - 0.2);
    }
    if (cart.controls.down) {
        player.speed = @min(3.0, player.speed + 0.2);
    }
    if (!cart.controls.up and !cart.controls.down) {
        player.speed = player.speed * 0.66;
    }
    const speed = player.speed;
    player.y = player.y + player.speed;
    if (player.y < 8.0) {
        player.y = 8.0;
        player.speed = 0.0;
    }
    if (player.y > @as(f32, cart.screen_height) - 8.0) {
        player.y = @as(f32, cart.screen_height) - 8.0;
        player.speed = 0.0;
    }
    const xpos: i32 = @intFromFloat(player.x - @as(f32, @floatFromInt(player.cooldown)) * 0.5);
    if (speed < -0.1) {
        cart.hline(.{
            .x = xpos,
            .y = @intFromFloat(player.y),
            .len = 8.0,
            .color = rgb565(shipBottom),
        });
        cart.hline(.{
            .x = xpos,
            .y = @intFromFloat(player.y - 1),
            .len = 3,
            .color = rgb565(shipBottom),
        });
    } else if (speed > 0.1) {
        cart.hline(.{
            .x = xpos,
            .y = @intFromFloat(player.y),
            .len = 8.0,
            .color = rgb565(shipTop),
        });
        cart.hline(.{
            .x = xpos,
            .y = @intFromFloat(player.y + 1),
            .len = 3,
            .color = rgb565(shipTop),
        });
    } else {
        cart.hline(.{
            .x = xpos,
            .y = @intFromFloat(player.y),
            .len = 8.0,
            .color = rgb565(shipTop),
        });
    }

    // draw health with neopixels
    for (cart.neopixels, 0..) |*np, i| {
        if (player.health > i) {
            np.* = green;
        } else {
            np.* = red;
        }
    }
}

// Enemies spawn in waves
// Increase level = more enemies in wave, faster enemies
// X number of enemy types, harder enemies shoot back
// enemies move in sin waves

const EnemyType = enum {
    blobby,
    forky,
};

const Enemy = struct {
    typ: EnemyType,
    x: f32,
    y: f32,
    speed: f32,
    cooldown: u8,
    live: bool,
};

var level: u8 = 0;
var levelTime: u16 = 0;
const MaxEnemies = 8;
var enemies: [MaxEnemies]Enemy = undefined;

fn draw_enemies() void {
}

const bannerText = "krig @ sycl 2024";
const bannerWidth = cart.font_width * bannerText.len;
var bannerPos: f32 = cart.screen_width / 2;

fn draw_banner() void {
    cart.text(.{
        .str = bannerText,
        .x = @intFromFloat(bannerPos),
        .y = cart.screen_height - 12,
        .text_color = rgb565(ziggy4),
    });
    bannerPos -= 0.233;
    if (bannerPos < -@as(f32, @floatFromInt(bannerWidth)))
        bannerPos = cart.screen_width;
}

export fn update() void {
    set_background();
    draw_stars();
    draw_bullets();
    draw_enemies();
    draw_player();
    draw_banner();
}

fn set_background() void {
    @memset(cart.framebuffer, rgb565(black));
}
