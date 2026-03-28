const std = @import("std");
const rl = @import("raylib");
const ship_mod = @import("ship.zig");
const uniform_grid_mod = @import("uniform_grid.zig");

const Ship = ship_mod.Ship;
const ShipList = std.MultiArrayList(Ship);

// SIMD helpers

const VEC_LEN = 8; // 8 × f32 = 256-bit (AVX) or 2 × 128-bit NEON ops
const Vec = @Vector(VEC_LEN, f32);

/// SIMD batch: pos += vec × dt
fn simdMovePositions(px: []f32, py: []f32, vx: []const f32, vy: []const f32, dt: f32) void {
    const dt_v: Vec = @splat(dt);
    var i: usize = 0;
    while (i + VEC_LEN <= px.len) : (i += VEC_LEN) {
        const p: Vec = px[i..][0..VEC_LEN].*;
        const v: Vec = vx[i..][0..VEC_LEN].*;
        px[i..][0..VEC_LEN].* = p + v * dt_v;

        const q: Vec = py[i..][0..VEC_LEN].*;
        const w: Vec = vy[i..][0..VEC_LEN].*;
        py[i..][0..VEC_LEN].* = q + w * dt_v;
    }
    while (i < px.len) : (i += 1) {
        px[i] += vx[i] * dt;
        py[i] += vy[i] * dt;
    }
}

/// SIMD batch: delay -= dt
fn simdDecrementDelays(delays: []f32, dt: f32) void {
    const dt_v: Vec = @splat(dt);
    var i: usize = 0;
    while (i + VEC_LEN <= delays.len) : (i += VEC_LEN) {
        const d: Vec = delays[i..][0..VEC_LEN].*;
        delays[i..][0..VEC_LEN].* = d - dt_v;
    }
    while (i < delays.len) : (i += 1) {
        delays[i] -= dt;
    }
}

pub fn main() !void {
    // var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    // defer _ = gpa.deinit();
    // const allocator = gpa.allocator();
    const allocator = std.heap.c_allocator;

    var prng: std.Random.DefaultPrng = .init(blk: {
        var seed: u64 = undefined;
        try std.posix.getrandom(std.mem.asBytes(&seed));
        break :blk seed;
    });
    const rand = prng.random();

    const screenWidth = 1280;
    const screenHeight = 720;

    rl.initWindow(screenWidth, screenHeight, "betterradar");
    defer rl.closeWindow();

    // rl.setTargetFPS(60);

    const N = 10_000_000;

    var initial_ships: ShipList = .{};
    var ships: ShipList = .{};
    try initial_ships.ensureTotalCapacity(allocator, N);
    try ships.ensureTotalCapacity(allocator, N);
    defer ships.deinit(allocator);
    defer initial_ships.deinit(allocator);

    // Scratch buffer for marking collided ships (reused every frame)
    const destroyed = try allocator.alloc(bool, N);
    defer allocator.free(destroyed);

    var uniform_grid = try uniform_grid_mod.UniformGrid.init(
        allocator,
        ship_mod.COLLISION_DIST,
        -ship_mod.COLLISION_DIST,
        -ship_mod.COLLISION_DIST,
        @as(f32, @floatFromInt(screenWidth)) + ship_mod.COLLISION_DIST,
        @as(f32, @floatFromInt(screenHeight)) + ship_mod.COLLISION_DIST,
        N,
    );
    defer uniform_grid.deinit();

    for (0..N) |_| {
        const dep_x: f32 = @floatFromInt(rand.intRangeAtMost(u32, 0, screenWidth));
        const dep_y: f32 = @floatFromInt(rand.intRangeAtMost(u32, 0, screenHeight));
        const dst_x: f32 = @floatFromInt(rand.intRangeAtMost(u32, 0, screenWidth));
        const dst_y: f32 = @floatFromInt(rand.intRangeAtMost(u32, 0, screenHeight));
        const speed: f32 = @floatFromInt(rand.intRangeAtMost(u32, 50, 200));
        const delay = rand.float(f32) * 30.0;
        try initial_ships.append(allocator, Ship.init(dep_x, dep_y, dst_x, dst_y, speed, delay));
    }

    var lastFrame = rl.getTime();
    var currentFrame: f64 = undefined;
    var deltaTime: f64 = undefined;
    var largestDeltaTime: f64 = 0.0;

    var started = false;

    while (!rl.windowShouldClose()) {
        currentFrame = rl.getTime();
        deltaTime = currentFrame - lastFrame;
        lastFrame = currentFrame;

        if (deltaTime > largestDeltaTime) {
            largestDeltaTime = deltaTime;
        }

        rl.beginDrawing();
        defer rl.endDrawing();

        const dt: f32 = @floatCast(deltaTime);

        // Decrement waiting-ship delays (SIMD)
        simdDecrementDelays(initial_ships.items(.delay), dt);

        // Transfer ready ships to active list
        {
            var i: usize = initial_ships.len;
            while (i > 0) {
                i -= 1;
                if (initial_ships.items(.delay)[i] <= 0) {
                    started = true;
                    try ships.append(allocator, initial_ships.get(i));
                    initial_ships.swapRemove(i);
                }
            }
        }

        // Move all active ships (SIMD)
        simdMovePositions(
            ships.items(.pos_x),
            ships.items(.pos_y),
            ships.items(.vec_x),
            ships.items(.vec_y),
            dt,
        );

        // Remove arrived ships (dot product: detects overshoot reliably)
        // If (dest - pos) · vec <= 0, the ship has reached or overshot its destination.
        {
            const px = ships.items(.pos_x);
            const py = ships.items(.pos_y);
            const dx = ships.items(.dest_x);
            const dy = ships.items(.dest_y);
            const vx = ships.items(.vec_x);
            const vy = ships.items(.vec_y);
            var i: usize = ships.len;
            while (i > 0) {
                i -= 1;
                const to_dest_x = dx[i] - px[i];
                const to_dest_y = dy[i] - py[i];
                if (to_dest_x * vx[i] + to_dest_y * vy[i] <= 0) {
                    ships.swapRemove(i);
                }
            }
        }

        // Build uniform grid (all ships active -> branchless)
        uniform_grid.clear();
        {
            const px = ships.items(.pos_x);
            const py = ships.items(.pos_y);
            for (px, py, 0..) |x, y, i| {
                uniform_grid.insert(i, x, y);
            }
        }

        // Collision detection (distance ** 2 + scratch buffer)
        {
            @memset(destroyed[0..ships.len], false);
            const px = ships.items(.pos_x);
            const py = ships.items(.pos_y);

            for (px, py, 0..) |x, y, i| {
                if (destroyed[i]) continue;

                // Tower
                const sz_dx = x - 300.0;
                const sz_dy = y - 300.0;
                if (sz_dx * sz_dx + sz_dy * sz_dy < 40_000.0) continue;

                var iter = uniform_grid.neighbors(x, y);
                check: while (iter.next()) |j| {
                    if (j <= i) continue;
                    if (destroyed[j]) continue;
                    const cdx = x - px[j];
                    const cdy = y - py[j];
                    if (cdx * cdx + cdy * cdy < ship_mod.COLLISION_DIST_SQ) {
                        destroyed[i] = true;
                        destroyed[j] = true;
                        break :check; // ship i dead, skip remaining neighbors
                    }
                }
            }
        }

        // Remove collided ships
        {
            var i: usize = ships.len;
            while (i > 0) {
                i -= 1;
                if (destroyed[i]) {
                    ships.swapRemove(i);
                }
            }
        }

        rl.clearBackground(.ray_white);
        {
            const px = ships.items(.pos_x);
            const py = ships.items(.pos_y);
            for (px, py) |x, y| {
                rl.drawRectangleRec(.{
                    .x = x - ship_mod.SHIP_RADIUS,
                    .y = y - ship_mod.SHIP_RADIUS,
                    .width = ship_mod.COLLISION_DIST,
                    .height = ship_mod.COLLISION_DIST,
                }, .red);
            }
        }

        rl.drawFPS(0, 0);
        rl.drawText(rl.textFormat("nb ships: %d", .{ships.len}), 0, 20, 20, .black);

        if (started and ships.len == 0 and initial_ships.len == 0) {
            std.debug.print("All ships destroyed! Largest delta time: {d}ms, which is {d} FPS\n", .{ largestDeltaTime * 1000.0, 1.0 / largestDeltaTime });
            return;
        }
    }
}
