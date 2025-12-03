const std = @import("std");

pub fn AsyncQueue(comptime T: type) type {
    return struct {
        const Self = @This();

        buffer: std.RingBuffer,
        mutex: std.Thread.Mutex = .{},
        not_empty: std.Thread.Condition = .{},
        not_full: std.Thread.Condition = .{},
        allocator: std.mem.Allocator,

        pub fn init(allocator: std.mem.Allocator, capacity: usize) !Self {
            const buf = try std.RingBuffer.init(allocator, capacity * @sizeOf(T));
            return Self{
                .buffer = buf,
                .allocator = allocator,
            };
        }

        pub fn deinit(self: *Self) void {
            self.buffer.deinit(self.allocator);
        }

        pub fn push(self: *Self, item: T) void {
            self.mutex.lock();
            defer self.mutex.unlock();

            while (self.buffer.isFull()) {
                self.not_full.wait(&self.mutex);
            }

            const bytes = std.mem.asBytes(&item);
            self.buffer.write(bytes);
            self.not_empty.signal();
        }

        pub fn pop(self: *Self) T {
            self.mutex.lock();
            defer self.mutex.unlock();

            while (self.buffer.isEmpty()) {
                self.not_empty.wait(&self.mutex);
            }

            var item: T = undefined;
            const bytes = std.mem.asBytes(&item);
            _ = self.buffer.read(bytes);
            self.not_full.signal();
            return item;
        }

        pub fn tryPop(self: *Self) ?T {
            self.mutex.lock();
            defer self.mutex.unlock();

            if (self.buffer.isEmpty()) {
                return null;
            }

            var item: T = undefined;
            const bytes = std.mem.asBytes(&item);
            _ = self.buffer.read(bytes);
            self.not_full.signal();
            return item;
        }
    };
}
