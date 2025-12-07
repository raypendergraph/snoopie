const std = @import("std");

pub fn AsyncQueue(comptime T: type) type {
    return struct {
        const Self = @This();

        items: []T,
        head: usize,
        tail: usize,
        count: usize,
        capacity: usize,
        mutex: std.Thread.Mutex = .{},
        not_empty: std.Thread.Condition = .{},
        not_full: std.Thread.Condition = .{},
        allocator: std.mem.Allocator,

        pub fn init(allocator: std.mem.Allocator, capacity: usize) !Self {
            const items = try allocator.alloc(T, capacity);
            return Self{
                .items = items,
                .head = 0,
                .tail = 0,
                .count = 0,
                .capacity = capacity,
                .allocator = allocator,
            };
        }

        pub fn deinit(self: *Self) void {
            self.allocator.free(self.items);
        }

        pub fn push(self: *Self, item: T) !void {
            self.mutex.lock();
            defer self.mutex.unlock();

            while (self.count >= self.capacity) {
                self.not_full.wait(&self.mutex);
            }

            self.items[self.tail] = item;
            self.tail = (self.tail + 1) % self.capacity;
            self.count += 1;
            self.not_empty.signal();
        }

        pub fn pop(self: *Self) T {
            self.mutex.lock();
            defer self.mutex.unlock();

            while (self.count == 0) {
                self.not_empty.wait(&self.mutex);
            }

            const item = self.items[self.head];
            self.head = (self.head + 1) % self.capacity;
            self.count -= 1;
            self.not_full.signal();
            return item;
        }

        pub fn tryPop(self: *Self) ?T {
            self.mutex.lock();
            defer self.mutex.unlock();

            if (self.count == 0) {
                return null;
            }

            const item = self.items[self.head];
            self.head = (self.head + 1) % self.capacity;
            self.count -= 1;
            self.not_full.signal();
            return item;
        }
    };
}
