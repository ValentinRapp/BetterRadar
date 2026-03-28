const std = @import("std");

pub const UniformGrid = struct {
    cell_size: f32,
    inv_cell_size: f32,
    min_x: f32,
    min_y: f32,
    grid_w: usize,
    grid_h: usize,
    allocator: std.mem.Allocator,
    cell_heads: []u32,
    next_indices: []u32,

    const INVALID_INDEX = std.math.maxInt(u32);

    pub fn init(
        allocator: std.mem.Allocator,
        cell_size: f32,
        min_x: f32,
        min_y: f32,
        max_x: f32,
        max_y: f32,
        max_items: usize,
    ) !UniformGrid {
        std.debug.assert(cell_size > 0);
        std.debug.assert(max_x > min_x);
        std.debug.assert(max_y > min_y);

        const inv_cell_size = 1.0 / cell_size;
        const grid_w: usize = @intFromFloat(@ceil((max_x - min_x) * inv_cell_size));
        const grid_h: usize = @intFromFloat(@ceil((max_y - min_y) * inv_cell_size));
        std.debug.assert(grid_w > 0);
        std.debug.assert(grid_h > 0);

        const cell_count = grid_w * grid_h;
        const cell_heads = try allocator.alloc(u32, cell_count);
        errdefer allocator.free(cell_heads);
        const next_indices = try allocator.alloc(u32, max_items);
        @memset(cell_heads, INVALID_INDEX);

        return .{
            .cell_size = cell_size,
            .inv_cell_size = inv_cell_size,
            .min_x = min_x,
            .min_y = min_y,
            .grid_w = grid_w,
            .grid_h = grid_h,
            .allocator = allocator,
            .cell_heads = cell_heads,
            .next_indices = next_indices,
        };
    }

    pub fn deinit(self: *UniformGrid) void {
        self.allocator.free(self.next_indices);
        self.allocator.free(self.cell_heads);
    }

    /// Reset all cells for a new frame.
    pub fn clear(self: *UniformGrid) void {
        @memset(self.cell_heads, INVALID_INDEX);
    }

    fn clampCell(v: isize, max: usize) usize {
        if (v <= 0) return 0;
        const uv: usize = @intCast(v);
        if (uv >= max) return max - 1;
        return uv;
    }

    /// Convert world coordinates to clamped grid cell coordinates.
    fn cellCoord(self: *const UniformGrid, x: f32, y: f32) struct { x: usize, y: usize } {
        const cx: isize = @intFromFloat(@floor((x - self.min_x) * self.inv_cell_size));
        const cy: isize = @intFromFloat(@floor((y - self.min_y) * self.inv_cell_size));
        return .{
            .x = clampCell(cx, self.grid_w),
            .y = clampCell(cy, self.grid_h),
        };
    }

    fn cellIndex(self: *const UniformGrid, cx: usize, cy: usize) usize {
        return cy * self.grid_w + cx;
    }

    /// Insert an element by its index at the given world position.
    pub fn insert(self: *UniformGrid, index: usize, x: f32, y: f32) void {
        std.debug.assert(index < self.next_indices.len);
        const key = self.cellCoord(x, y);
        const ci = self.cellIndex(key.x, key.y);
        const idx_u32: u32 = @intCast(index);
        self.next_indices[index] = self.cell_heads[ci];
        self.cell_heads[ci] = idx_u32;
    }

    /// Iterator over all ship indices in the 3x3 neighborhood around a ship.
    pub const NeighborIterator = struct {
        grid: *const UniformGrid,
        min_x: usize,
        max_x: usize,
        min_y: usize,
        max_y: usize,
        cur_x: usize,
        cur_y: usize,
        current: u32 = INVALID_INDEX,

        pub fn next(self: *NeighborIterator) ?usize {
            while (true) {
                if (self.current != INVALID_INDEX) {
                    const out = self.current;
                    self.current = self.grid.next_indices[@intCast(out)];
                    return @intCast(out);
                }

                while (self.cur_x < self.max_x) {
                    while (self.cur_y < self.max_y) {
                        const ci = self.grid.cellIndex(self.cur_x, self.cur_y);
                        self.cur_y += 1;
                        const head = self.grid.cell_heads[ci];
                        if (head != INVALID_INDEX) {
                            self.current = head;
                            break;
                        }
                    }
                    if (self.current != INVALID_INDEX) break;
                    self.cur_x += 1;
                    self.cur_y = self.min_y;
                }

                if (self.current == INVALID_INDEX) {
                    return null;
                }
            }
        }
    };

    /// Return an iterator over the 3x3 neighbourhood of the cell containing (x, y).
    pub fn neighbors(self: *const UniformGrid, x: f32, y: f32) NeighborIterator {
        const key = self.cellCoord(x, y);
        const min_x = if (key.x > 0) key.x - 1 else 0;
        const min_y = if (key.y > 0) key.y - 1 else 0;
        const max_x = @min(key.x + 2, self.grid_w);
        const max_y = @min(key.y + 2, self.grid_h);
        return .{
            .grid = self,
            .min_x = min_x,
            .max_x = max_x,
            .min_y = min_y,
            .max_y = max_y,
            .cur_x = min_x,
            .cur_y = min_y,
        };
    }
};
