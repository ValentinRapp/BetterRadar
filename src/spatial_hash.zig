const std = @import("std");

pub const SpatialHash = struct {
    cell_size: f32,
    inv_cell_size: f32,
    allocator: std.mem.Allocator,
    cells: std.AutoHashMap(CellKey, std.ArrayListUnmanaged(u32)),

    pub const CellKey = struct {
        x: i32,
        y: i32,
    };

    pub fn init(allocator: std.mem.Allocator, cell_size: f32) SpatialHash {
        std.debug.assert(cell_size > 0);
        return .{
            .cell_size = cell_size,
            .inv_cell_size = 1.0 / cell_size,
            .allocator = allocator,
            .cells = std.AutoHashMap(CellKey, std.ArrayListUnmanaged(u32)).init(allocator),
        };
    }

    pub fn deinit(self: *SpatialHash) void {
        var it = self.cells.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.deinit(self.allocator);
        }
        self.cells.deinit();
    }

    /// Reset all cells for a new frame. Retains allocated memory so no
    /// reallocation happens between frames once the table is warmed up.
    pub fn clear(self: *SpatialHash) void {
        var it = self.cells.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.clearRetainingCapacity();
        }
    }

    /// Convert world coordinates to cell coordinates.
    /// Uses @floor so negative positions map correctly (e.g. -0.5 → cell -1).
    pub fn cellCoord(self: *const SpatialHash, x: f32, y: f32) CellKey {
        return .{
            .x = @intFromFloat(@floor(x * self.inv_cell_size)),
            .y = @intFromFloat(@floor(y * self.inv_cell_size)),
        };
    }

    /// Insert an element by its index at the given world position.
    pub fn insert(self: *SpatialHash, index: u32, x: f32, y: f32) !void {
        const key = self.cellCoord(x, y);
        const gop = try self.cells.getOrPut(key);
        if (!gop.found_existing) {
            gop.value_ptr.* = .{};
        }
        try gop.value_ptr.append(self.allocator, index);
    }

    /// Return the indices stored in a given cell, or null if the cell
    /// is empty / doesn't exist.
    pub fn getCell(self: *const SpatialHash, key: CellKey) ?[]const u32 {
        if (self.cells.get(key)) |list| {
            if (list.items.len > 0) return list.items;
        }
        return null;
    }

    /// Iterator that yields every non-empty slice of indices in the 3×3
    /// neighbourhood of a cell (the cell itself + its 8 neighbours).
    pub const NeighborIterator = struct {
        hash: *const SpatialHash,
        center_x: i32,
        center_y: i32,
        dx: i32 = -1,
        dy: i32 = -1,

        pub fn next(self: *NeighborIterator) ?[]const u32 {
            while (self.dx <= 1) {
                while (self.dy <= 1) {
                    const key = CellKey{
                        .x = self.center_x + self.dx,
                        .y = self.center_y + self.dy,
                    };
                    self.dy += 1;
                    if (self.hash.getCell(key)) |items| {
                        return items;
                    }
                }
                self.dx += 1;
                self.dy = -1;
            }
            return null;
        }
    };

    /// Return an iterator over the 3×3 neighbourhood of the cell containing (x, y).
    pub fn neighbors(self: *const SpatialHash, x: f32, y: f32) NeighborIterator {
        const key = self.cellCoord(x, y);
        return .{
            .hash = self,
            .center_x = key.x,
            .center_y = key.y,
        };
    }
};
