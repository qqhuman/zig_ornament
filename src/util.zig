pub const std = @import("std");

const geometry = @import("geometry/geometry.zig");
const materials = @import("materials/materials.zig");

pub const Resolution = struct {
    width: u32,
    height: u32,
};

pub const Range = struct {
    const Self = @This();
    start: usize,
    end: usize,

    pub inline fn count(self: *const Self) usize {
        return self.end - self.start;
    }
};

pub fn ArrayList(comptime T: type) type {
    return struct {
        const Self = @This();
        dirty: bool = true,
        array_list: std.ArrayList(T),

        pub fn init(allocator: std.mem.Allocator) Self {
            return .{ .array_list = std.ArrayList(T).init(allocator) };
        }

        pub fn deinit(self: *Self) void {
            self.array_list.deinit();
        }

        pub fn len(self: *const Self) usize {
            return self.array_list.items.len;
        }

        pub inline fn get(self: *Self, i: usize) T {
            return self.array_list.items[i];
        }

        pub inline fn get_mut(self: *Self, i: usize) *T {
            self.dirty = true;
            return &self.array_list.items[i];
        }

        pub inline fn set(self: *Self, i: usize, item: T) void {
            self.array_list.items[i] = item;
            self.dirty = true;
        }

        pub fn get_slice_mut(self: *Self, start: usize, end: usize) []T {
            var slice = self.array_list.items[start..end];
            self.dirty = true;
            return slice;
        }

        pub fn get_slice_mut_from(self: *Self, start: usize) []T {
            var slice = self.array_list.items[start..];
            self.dirty = true;
            return slice;
        }

        pub fn get_slice(self: *const Self, start: usize, end: usize) []const T {
            return self.array_list.items[start..end];
        }

        pub fn get_slice_from(self: *const Self, start: usize) []const T {
            return self.array_list.items[start..];
        }

        pub fn ensureUnusedCapacity(self: *Self, additional_count: usize) !void {
            return self.array_list.ensureUnusedCapacity(additional_count);
        }

        pub fn ensureTotalCapacity(self: *Self, new_capacity: usize) !void {
            return self.array_list.ensureTotalCapacity(new_capacity);
        }

        pub fn append(self: *Self, item: T) !void {
            try self.array_list.append(item);
            self.dirty = true;
        }

        pub fn addManyAsSlice(self: *Self, n: usize) ![]T {
            var slice = try self.array_list.addManyAsSlice(n);
            self.dirty = true;
            return slice;
        }

        pub fn appendSlice(self: *Self, items: []const T) !void {
            try self.array_list.appendSlice(items);
            self.dirty = true;
        }

        pub fn appendNTimes(self: *Self, value: T, n: usize) !void {
            try self.array_list.appendNTimes(value, n);
            self.dirty = true;
        }

        pub fn shrinkRetainingCapacity(self: *Self, new_len: usize) void {
            self.array_list.shrinkRetainingCapacity(new_len);
            self.dirty = true;
        }

        pub fn clearRetainingCapacity(self: *Self) void {
            self.array_list.clearRetainingCapacity();
            self.dirty = true;
        }

        pub fn orderedRemove(self: *Self, i: usize) void {
            self.array_list.orderedRemove(i);
            self.dirty = true;
        }
    };
}
