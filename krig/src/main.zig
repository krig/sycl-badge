const std = @import("std");
const fmt = std.fmt;
const cart = @import("cart-api");

const GameScaler: f32 = 1.0;

const black = defColor(0x000000);
const white = defColor(0xffffff);
const zig = defColor(0xF7A41D);
const red = defColor(0xF82828);
const green = defColor(0x00FF00);
const dark_red = defColor(0x010000);
const dark_green = defColor(0x000100);
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

var rand: std.rand.DefaultPrng = undefined;
fn rand_float() f32 {
    const byte_count = 2;
    const UInt = @Type(std.builtin.Type{
        .Int = .{
            .signedness = .unsigned,
            .bits = byte_count * 8,
        },
    });
    var buf: [byte_count]u8 = undefined;
    rand.fill(&buf);
    const r = std.mem.readInt(UInt, &buf, .big);
    return @as(f32, @floatFromInt(r)) / (@as(f32, 1.0) + @as(f32, std.math.maxInt(UInt)));
}

const NumStars = 12;
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
const MaxBullets = 8;
var bullets: [MaxBullets]Bullet = undefined;

export fn start() void {
    rand = std.rand.DefaultPrng.init(5831);
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

fn tick_stars() void {
    for (&starfield) |*star| {
        var x = star.*.x - star.*.speed * 2.0;
        if (x < 0.0) x = @floatFromInt(cart.screen_width);
        star.*.x = x;
    }
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
    }
}

fn noisy(freq: f32, len: f32, vol: u8, channel: u8) void {
    cart.tone(.{
        .frequency = @intFromFloat(freq + 0.5),
        .duration = @intFromFloat(@max(len - 0.04, 0.0) * 60),
        .volume = vol,
        .flags = .{
            .channel = @enumFromInt(channel),
        },
    });
}

fn spawn_bullet(bullet: Bullet) void {
    for (&bullets) |*b| {
        if (b.live) continue;
        b.* = bullet;
        noisy(880.0, 0.1, 100, 0);
        break;
    }
}

fn tick_bullets() void {
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
    }
}

fn draw_bullets() void {
    for (&bullets) |*bullet| {
        if (!bullet.live) continue;
        if (bullet.typ == .dot) {
            cart.rect(.{
                .x = @intFromFloat(bullet.x),
                .y = @intFromFloat(bullet.y),
                .width = 2,
                .height = 2,
                .stroke_color = rgb565(white),
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

fn tick_player() void {
    if (cart.controls.up) {
        player.speed = @max(-3.0, player.speed - 0.2);
    }
    if (cart.controls.down) {
        player.speed = @min(3.0, player.speed + 0.2);
    }
    if (!cart.controls.up and !cart.controls.down) {
        player.speed = player.speed * 0.66;
    }
    player.y = player.y + player.speed;
    if (player.y < 8.0) {
        player.y = 8.0;
        player.speed = 0.0;
    }
    if (player.y > @as(f32, cart.screen_height) - 8.0) {
        player.y = @as(f32, cart.screen_height) - 8.0;
        player.speed = 0.0;
    }
}

fn draw_player() void {
    const speed = player.speed;
    const xpos: i32 = @intFromFloat(player.x - @as(f32, @floatFromInt(player.cooldown)) * 0.5);
    if (speed < -0.1) {
        cart.rect(.{
            .x = xpos,
            .y = @intFromFloat(player.y),
            .width = 8,
            .height = 2,
            .stroke_color = rgb565(shipBottom),
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
            .stroke_color = rgb565(shipTop),
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
            np.* = dark_green;
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
    levelTime +%= 1;
    if (levelTime > 100 and level_cleared()) {
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
                            noisy(440.0, 0.2, 100, 3);
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
                        noisy(220.0, 0.2, 80, 1);
                    } else {
                        noisy(440.0, 0.2, 100, 3);
                    }
                }
            }
            // remove enemy when exiting the screen
            if (enemy.x < -4.0) {
                enemy.*.state = .dead;
                // TODO: swap last enemy with this one
            }
        }
    }
}

fn draw_enemies() void {
    for (&enemies) |*enemy| {
        if (enemy.state == .dead) continue;
        if (enemy.state == .dying) {
            const hw: f32 = @as(f32, @floatFromInt(enemy.cooldown * 2)) * 0.5;
            cart.oval(.{
                .x = @intFromFloat(enemy.x - hw),
                .y = @intFromFloat(enemy.y - hw),
                .width = enemy.cooldown * 2,
                .height = enemy.cooldown * 2,
                .stroke_color = rgb565(red),
                .fill_color = rgb565(white),
            });
        }
        if (enemy.state == .live) {
            cart.rect(.{
                .x = @intFromFloat(enemy.x - EnemyWidth/2),
                .y = @intFromFloat(enemy.y + EnemyWidth/2),
                .width = EnemyWidth + 1,
                .height = 2,
                .fill_color = rgb565(ziggy6),
            });
            cart.rect(.{
                .x = @intFromFloat(enemy.x - EnemyWidth/2),
                .y = @intFromFloat(enemy.y - EnemyWidth/2),
                .width = EnemyWidth + 1,
                .height = 2,
                .fill_color = rgb565(ziggy6),
            });
            cart.oval(.{
                .x = @intFromFloat(enemy.x - 3),
                .y = @intFromFloat(enemy.y - 3),
                .width = 7,
                .height = 8,
                .fill_color = rgb565(ziggy6),
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

const GameState = enum {
    intro,
    game,
    game_over,
};
var gameState: GameState = .intro;

const introText = &[_][]const u8{
    "KRISTOFFER",
    "GRONLUND",
    "",
    "@krig",
    "",
    "PRESS START",
};
const spacing = (cart.font_height * 4 / 3);
var shakex: [introText.len]i32 = .{0} ** introText.len;
var shakey: [introText.len]i32 = .{0} ** introText.len;

fn draw_intro_text() void {
    const y_start = (cart.screen_height - (cart.font_height + spacing * (introText.len - 1))) / 2;
    if (rand_float() < 0.1) {
        for (shakex, 0..) |_, i| {
            shakex[i] = @intFromFloat(rand_float() * 8.0);
            shakey[i] = @intFromFloat(rand_float() * 4.0);
        }
    }
    for (introText, 0..) |line, i| {
        const flicker = rand_float() < 0.2;
        if (!flicker) {
            cart.text(.{
                .str = line,
                .x = @as(i32, @intCast((cart.screen_width - cart.font_width * line.len) / 2)) + shakex[i],
                .y = @as(i32, @intCast(y_start + spacing * i)) + shakey[i],
                .text_color = rgb565(zig),
            });
        }
    }
}

var stateTick: u16 = 0;

export fn update() void {
    if (stateTick > 1000) stateTick = 100;
    stateTick +%= 1;
    if (gameState == .intro) {
        set_background();
        tick_stars();
        tick_stars();
        draw_stars();
        draw_intro_text();
        if (stateTick > 50 and cart.controls.start) {
            gameState = .game;
            stateTick = 0;
        }
        for (cart.neopixels) |*np| {
            if (rand_float() > 0.8) {
                np.* = black;
            } else if (rand_float() > 0.98) {
                np.* = blend(black, zig, 0.05);
            } else if (rand_float() > 0.8) {
                np.* = blend(black, dark_red, 0.05);
            }
        }
    } else if (gameState == .game_over) {
        set_background();
        tick_stars();
        tick_stars();
        draw_stars();
        const gameOver = "GAME OVER";
        if (rand_float() < 0.8) {
            cart.text(.{
                .str = gameOver,
                .x = (cart.screen_width - gameOver.len * cart.font_width)/2,
                .y = (cart.screen_height - cart.font_height)/2,
                .text_color = rgb565(red),
            });
        }
        if (stateTick > 50 and cart.controls.start) {
            reset_game();
            gameState = .intro;
            stateTick = 0;
        }
        for (cart.neopixels) |*np| {
            if (rand_float() > 0.8) {
                np.* = black;
            } else if (rand_float() > 0.8) {
                np.* = dark_red;
            }
        }
    } else {
        if (stateTick > 50 and cart.controls.select) {
            reset_game();
            gameState = .intro;
            stateTick = 0;
        }
        tick_game();
        if (player.health == 0) {
            gameState = .game_over;
            stateTick = 0;
            return;
        }
        tick_game();
        if (player.health == 0) {
            gameState = .game_over;
            stateTick = 0;
            return;
        }
        draw_game();
    }
}

fn tick_game() void {
    tick_stars();
    tick_bullets();
    tick_enemies();
    tick_player();
}

fn draw_game() void {
    set_background();
    draw_stars();
    draw_enemies();
    draw_player();
    draw_bullets();
    draw_level();
    draw_banner();
}

fn set_background() void {
    @memset(cart.framebuffer, rgb565(black));
}
