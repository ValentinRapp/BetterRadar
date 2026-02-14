pub const SHIP_RADIUS: f32 = 0.9;
pub const SHIP_RADIUS_SQ: f32 = SHIP_RADIUS * SHIP_RADIUS;
pub const COLLISION_DIST: f32 = SHIP_RADIUS * 2.0;
pub const COLLISION_DIST_SQ: f32 = COLLISION_DIST * COLLISION_DIST;

/// Pure data — no methods for hot paths.
/// Scalar f32 fields give optimal SoA layout via MultiArrayList:
/// each field becomes its own contiguous array, perfect for SIMD.
pub const Ship = struct {
    pos_x: f32,
    pos_y: f32,
    dest_x: f32,
    dest_y: f32,
    vec_x: f32,
    vec_y: f32,
    delay: f32,

    pub fn init(dep_x: f32, dep_y: f32, dst_x: f32, dst_y: f32, speed: f32, delay_val: f32) Ship {
        const dx = dst_x - dep_x;
        const dy = dst_y - dep_y;
        const length = @sqrt(dx * dx + dy * dy);
        return .{
            .pos_x = dep_x,
            .pos_y = dep_y,
            .dest_x = dst_x,
            .dest_y = dst_y,
            .vec_x = dx / length * speed,
            .vec_y = dy / length * speed,
            .delay = delay_val,
        };
    }
};
