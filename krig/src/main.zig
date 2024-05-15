const std = @import("std");
const fmt = std.fmt;
const cart = @import("cart-api");


const black = defColor(0x000000);
const white = defColor(0xffffff);
const zig = defColor(0xF7A41D);
const red = defColor(0xF82828);
const green = defColor(0x00FF00);
const dark_red = defColor(0x7f0000);
const dark_green = defColor(0x007f00);
const blue = defColor(0x0000FF);
const ziggy1 = defColor(0xf98a31);
const ziggy3 = defColor(0xe56c2c);
const ziggy4 = defColor(0xf15a29);
const ziggy5 = defColor(0xc54827);
const ziggy6 = defColor(0xfbb040);
const ziggy7 = defColor(0xf09d2e);
const ziggy2 = defColor(0x231f20);
const ziggy8 = defColor(0xeaebec);
const light = defColor(0x777777);
const dark = defColor(0x222222);
const purp = defColor(0x820eef);

const shipTop = defColor(0xF7A41D);
// const shipBottom = defColor(0xf58f0a);
const shipBottom = defColor(0x934b17);
const flash = defColor(0x98ff98);

inline fn defColor(rgb: u24) cart.NeopixelColor {
    return .{
        .r = @intCast((rgb >> 16) & 0xff),
        .g = @intCast((rgb >> 8) & 0xff),
        .b = @intCast(rgb & 0xff),
    };
}

inline fn blend(from: cart.NeopixelColor, to: cart.NeopixelColor, f: f32) cart.NeopixelColor {
    const clamped = @min(1.0, @max(0.0, f));
    return .{
        .r = @intFromFloat((from.r * (1.0 - clamped)) + (to.r * clamped)),
        .g = @intFromFloat((from.g * (1.0 - clamped)) + (to.g * clamped)),
        .b = @intFromFloat((from.b * (1.0 - clamped)) + (to.b * clamped)),
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

const NumStars = 18;
var starfield: [NumStars]Star = undefined;

const Player = struct {
    x: f32,
    y: f32,
    speed: f32,
    health: u8,
    cooldown: u8,
    score: u8,
};
var player: Player = undefined;
const MaxHealth: u8 = 5;
const PlayerWidth = 8;

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
const MaxBullets = 16;
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
        .score = 0,
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
                    .width = 2,
                    .height = 2,
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
        cart.rect(.{
            .x = xpos,
            .y = @intFromFloat(player.y),
            .width = 8,
            .height = 2,
            .fill_color = rgb565(shipBottom),
        });
        cart.hline(.{
            .x = xpos,
            .y = @intFromFloat(player.y - 1),
            .len = 3,
            .color = rgb565(shipBottom),
        });
        cart.hline(.{
            .x = xpos,
            .y = @intFromFloat(player.y - 2),
            .len = 1,
            .color = rgb565(shipBottom),
        });
    } else if (speed > 0.1) {
        cart.rect(.{
            .x = xpos,
            .y = @intFromFloat(player.y),
            .width = 8,
            .height = 2,
            .fill_color = rgb565(shipTop),
        });
        cart.hline(.{
            .x = xpos,
            .y = @intFromFloat(player.y + 2),
            .len = 3,
            .color = rgb565(shipTop),
        });
        cart.hline(.{
            .x = xpos,
            .y = @intFromFloat(player.y + 3),
            .len = 1,
            .color = rgb565(shipTop),
        });
    } else {
        cart.hline(.{
            .x = xpos,
            .y = @intFromFloat(player.y),
            .len = 8.0,
            .color = rgb565(shipTop),
        });
        cart.hline(.{
            .x = xpos,
            .y = @intFromFloat(player.y + 1),
            .len = 8.0,
            .color = rgb565(shipBottom),
        });
    }

    const r = rand_float();
    if (r > 0.2) {
        cart.hline(.{
            .x = xpos - @as(i32, @intFromFloat(r * 6.0)),
            .y = @intFromFloat(player.y + r + 0.2),
            .len = @intFromFloat(r * 5.0),
            .color = rgb565(flash),
        });
    }

    // draw health with neopixels
    for (cart.neopixels, 0..) |*np, i| {
        if (player.health > i) {
            np.* = black;
        } else {
            np.* = dark_red;
        }
    }
}

// Enemies spawn in waves
// Increase level = more enemies in wave, faster enemies
// X number of enemy types, harder enemies shoot back
// enemies move in sin waves

const EnemyType = enum {
    sinwavey,
    angular,
};

const EnemyState = enum {
    dead,
    live,
    dying,
};

const Enemy = struct {
    typ: EnemyType,
    state: EnemyState,
    x: f32,
    y: f32,
    speed: f32,
    health: u8,
    cooldown: u8,
};

var level: u32 = 0;
var levelTime: u32 = 0;
var shouldSpawn: u8 = 0;
const EnemyWidth: f32 = 8;
const MaxEnemies = 8;
var enemies: [MaxEnemies]Enemy = undefined;

fn reset_game() void {
    level = 0;
    levelTime = 0;
    shouldSpawn = 0;
    for (&enemies) |*slot| slot.*.state = .dead;
    for (&bullets) |*slot| slot.*.live = false;
    player.health = MaxHealth;
    player.cooldown = 0;
    player.score = 0;
}

fn spawn_enemy(enemy: Enemy) void {
    for (&enemies) |*slot| {
        if (slot.state == .dead) {
            slot.* = enemy;
            break;
        }
    }
}

fn level_cleared() bool {
    for (enemies) |enemy| {
        if (enemy.state != .dead) {
            return false;
        }
    }
    return true;
}

fn tick_enemies() void {
    levelTime += 1;
    if (levelTime > 1200 and level_cleared()) {
        levelTime = 0;
        level += 1;
        shouldSpawn = @min(level, MaxEnemies);
    }

    // spawn enemies
    if ((levelTime > 0 and (levelTime % 50) == 0) and (shouldSpawn > 0)) {
        spawn_enemy(.{
            .typ = .sinwavey,
            .state = .live,
            .x = cart.screen_width,
            .y = (0.2 + rand_float()*0.8) * cart.screen_height,
            .speed = 0.8,
            .health = 1,
            .cooldown = 0,
        });
        shouldSpawn -= 1;
    }

    for (&enemies) |*enemy| {
        if (enemy.state == .dead) {
        }
        else if (enemy.state == .dying) { 
            enemy.cooldown += 1;
            if (enemy.cooldown > 16) {
                enemy.state = .dead;
            }
        } else {
            const hw: f32 = EnemyWidth * 0.5;
            const hh: f32 = EnemyWidth * 0.5;

            // move enemy
            enemy.x = enemy.x - enemy.speed;
            enemy.y = enemy.y + std.math.sin(@as(f32, @floatFromInt(levelTime % 100)) * 0.01) * 0.1;
            // collide with bullets
            for (&bullets) |*bullet| {
                if (bullet.live) {
                    if (bullet.x < enemy.x + hw and bullet.x > enemy.x - hw) {
                        if (bullet.y < enemy.y + hh and bullet.y > enemy.y - hh) {
                            bullet.*.live = false;
                            enemy.*.state = .dying;
                            enemy.cooldown = 1;
                            player.score += 1;
                            continue;
                        }
                    }
                }
            }
            // collide with player
            if (enemy.x - hw < player.x + PlayerWidth and enemy.x + hw > player.x) {
                if (enemy.y - hh < player.y + 1 and enemy.y + hh > player.y - 1) {
                    enemy.*.state = .dying;
                    enemy.cooldown = 1;
                    if (player.health > 0) {
                        player.health -= 1;
                        player.score = 0;
                    }
                }
            }
            // remove enemy when exiting the screen
            if (enemy.x < -5.0) {
                enemy.*.state = .dead;
            }
        }
    }
}

fn draw_enemies() void {
    for (enemies) |enemy| {
        if (enemy.state == .dead) continue;
        if (enemy.state == .dying) {
            const hw: f32 = @as(f32, @floatFromInt(enemy.cooldown)) * 0.5;
            cart.oval(.{
                .x = @intFromFloat(enemy.x - hw),
                .y = @intFromFloat(enemy.y - hw),
                .width = enemy.cooldown,
                .height = enemy.cooldown,
                .fill_color = rgb565(white),
            });
        }
        if (enemy.state == .live) {
            cart.rect(.{
                .x = @intFromFloat(enemy.x - EnemyWidth/2),
                .y = @intFromFloat(enemy.y - EnemyWidth/2),
                .width = EnemyWidth,
                .height = EnemyWidth,
                .fill_color = rgb565(blue),
                .stroke_color = null,
            });
        }
    }
}

fn draw_level() void {
    if (player.score > 0) {
        var text: [32]u8 = undefined;
        const txt = std.fmt.bufPrintZ(&text, "{}", .{player.score}) catch "-";
        cart.text(.{
            .str = txt,
            .x = @intCast((cart.screen_width - cart.font_width*txt.len)/2),
            .y = 4,
            .text_color = rgb565(white),
        });
    }

    if (level > 0 and levelTime < 100 and rand_float() < 0.5) {
        const txt = "NEW WAVE";
        cart.text(.{
            .str = txt,
            .x = @intCast((cart.screen_width - cart.font_width*txt.len)/2),
            .y = @intCast((cart.screen_height - cart.font_height)/2),
            .text_color = rgb565(red),
        });
    }
}

const bannerText = "krig @ sycl 2024";
const bannerWidth = cart.font_width * bannerText.len;
var bannerPos: f32 = cart.screen_width / 2;

fn draw_banner() void {
    cart.text(.{
        .str = bannerText,
        .x = @intFromFloat(bannerPos),
        .y = cart.screen_height - 12,
        .text_color = rgb565(purp),
    });
    bannerPos -= 0.233;
    if (bannerPos < -@as(f32, @floatFromInt(bannerWidth)))
        bannerPos = cart.screen_width;
}

export fn update() void {
    set_background();
    if (player.health == 0) {
        reset_game();
    }
    draw_stars();
    tick_enemies();
    draw_enemies();
    draw_player();
    draw_bullets();
    draw_level();
    draw_banner();
}

fn set_background() void {
    if (level == 0 and levelTime % 8 == 0 and levelTime < 40) {
        @memset(cart.framebuffer, rgb565(white));
    } else {
        @memset(cart.framebuffer, rgb565(black));
    }
}
