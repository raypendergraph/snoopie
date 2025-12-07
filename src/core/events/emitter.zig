const std = @import("std");

/// Generic event emitter that manages observers and emits events of type T
pub fn Emitter(comptime T: type) type {
    return struct {
        const Self = @This();

        pub const Observer = struct {
            context: *anyopaque,
            callback: *const fn (ctx: *anyopaque, event: T) void,

            pub fn notify(self: Observer, event: T) void {
                self.callback(self.context, event);
            }
        };

        allocator: std.mem.Allocator,
        observers: std.ArrayList(Observer),

        pub fn init(allocator: std.mem.Allocator) Self {
            return Self{
                .allocator = allocator,
                .observers = std.ArrayList(Observer){},
            };
        }

        pub fn deinit(self: *Self) void {
            self.observers.deinit(self.allocator);
        }

        /// Add an observer
        pub fn addObserver(
            self: *Self,
            context: anytype,
            comptime callback: fn (ctx: @TypeOf(context), event: T) void,
        ) !void {
            const observer = Observer{
                .context = context,
                .callback = struct {
                    fn wrapper(ctx: *anyopaque, event: T) void {
                        const typed_ctx: @TypeOf(context) = @ptrCast(@alignCast(ctx));
                        callback(typed_ctx, event);
                    }
                }.wrapper,
            };
            try self.observers.append(self.allocator, observer);
        }

        /// Remove an observer by context pointer
        pub fn removeObserver(self: *Self, context: *const anyopaque) void {
            var i: usize = 0;
            while (i < self.observers.items.len) {
                if (self.observers.items[i].context == context) {
                    _ = self.observers.orderedRemove(i);
                } else {
                    i += 1;
                }
            }
        }

        /// Emit an event to all observers
        pub fn emit(self: *Self, event: T) void {
            for (self.observers.items) |observer| {
                observer.notify(event);
            }
        }

        /// Get the number of observers
        pub fn observerCount(self: *const Self) usize {
            return self.observers.items.len;
        }
    };
}
