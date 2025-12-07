const std = @import("std");

/// A sorted list that maintains order and provides change notifications
pub fn SortedList(comptime T: type) type {
    return struct {
        const Self = @This();

        /// Change event types
        pub const ChangeType = enum {
            inserted,
            removed,
            updated,
            reordered,
        };

        /// Change notification
        pub const Change = struct {
            change_type: ChangeType,
            index: usize,
            item: ?*const T = null,
        };

        /// Observer callback function type
        pub const Observer = *const fn (change: Change, context: ?*anyopaque) void;

        /// Observer registration
        const ObserverEntry = struct {
            callback: Observer,
            context: ?*anyopaque,
        };

        allocator: std.mem.Allocator,
        items: std.ArrayList(T),
        sort_fn: *const fn (context: void, a: T, b: T) bool,
        observers: std.ArrayList(ObserverEntry),

        pub fn init(
            allocator: std.mem.Allocator,
            sort_fn: *const fn (context: void, a: T, b: T) bool,
        ) Self {
            return .{
                .allocator = allocator,
                .items = std.ArrayList(T).init(allocator),
                .sort_fn = sort_fn,
                .observers = std.ArrayList(ObserverEntry).init(allocator),
            };
        }

        pub fn deinit(self: *Self) void {
            self.items.deinit();
            self.observers.deinit();
        }

        /// Add an observer for change notifications
        pub fn addObserver(self: *Self, callback: Observer, context: ?*anyopaque) !void {
            try self.observers.append(.{
                .callback = callback,
                .context = context,
            });
        }

        /// Remove an observer
        pub fn removeObserver(self: *Self, callback: Observer) void {
            for (self.observers.items, 0..) |entry, i| {
                if (entry.callback == callback) {
                    _ = self.observers.orderedRemove(i);
                    return;
                }
            }
        }

        /// Notify all observers of a change
        fn notifyObservers(self: *Self, change: Change) void {
            for (self.observers.items) |entry| {
                entry.callback(change, entry.context);
            }
        }

        /// Insert an item in sorted order
        pub fn insert(self: *Self, item: T) !usize {
            const idx = self.findInsertIndex(item);
            try self.items.insert(idx, item);

            self.notifyObservers(.{
                .change_type = .inserted,
                .index = idx,
                .item = &self.items.items[idx],
            });

            return idx;
        }

        /// Remove item at index
        pub fn remove(self: *Self, index: usize) T {
            const item = self.items.orderedRemove(index);

            self.notifyObservers(.{
                .change_type = .removed,
                .index = index,
                .item = &item,
            });

            return item;
        }

        /// Update item at index (re-sorts if necessary)
        pub fn update(self: *Self, index: usize, item: T) !void {
            // Remove old item
            _ = self.items.orderedRemove(index);

            // Insert updated item in sorted position
            const new_idx = self.findInsertIndex(item);
            try self.items.insert(new_idx, item);

            if (new_idx == index) {
                // Position unchanged, just updated
                self.notifyObservers(.{
                    .change_type = .updated,
                    .index = index,
                    .item = &self.items.items[index],
                });
            } else {
                // Position changed, treat as remove + insert
                self.notifyObservers(.{
                    .change_type = .removed,
                    .index = index,
                });
                self.notifyObservers(.{
                    .change_type = .inserted,
                    .index = new_idx,
                    .item = &self.items.items[new_idx],
                });
            }
        }

        /// Change the sort function and re-sort the entire list
        pub fn setSortFunction(
            self: *Self,
            sort_fn: *const fn (context: void, a: T, b: T) bool,
        ) void {
            self.sort_fn = sort_fn;
            std.mem.sort(T, self.items.items, {}, sort_fn);

            self.notifyObservers(.{
                .change_type = .reordered,
                .index = 0,
            });
        }

        /// Get item at index
        pub fn get(self: *const Self, index: usize) T {
            return self.items.items[index];
        }

        /// Get pointer to item at index
        pub fn getPtr(self: *Self, index: usize) *T {
            return &self.items.items[index];
        }

        /// Get count of items
        pub fn count(self: *const Self) usize {
            return self.items.items.len;
        }

        /// Clear all items
        pub fn clear(self: *Self) void {
            const old_count = self.items.items.len;
            self.items.clearRetainingCapacity();

            // Notify observers that all items were removed
            var i: usize = old_count;
            while (i > 0) {
                i -= 1;
                self.notifyObservers(.{
                    .change_type = .removed,
                    .index = i,
                });
            }
        }

        /// Find the insertion index for an item using binary search
        fn findInsertIndex(self: *const Self, item: T) usize {
            return std.sort.lowerBound(
                T,
                item,
                self.items.items,
                {},
                self.sort_fn,
            );
        }

        /// Get slice of all items (read-only)
        pub fn slice(self: *const Self) []const T {
            return self.items.items;
        }
    };
}
