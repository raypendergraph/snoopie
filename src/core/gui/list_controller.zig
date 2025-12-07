const std = @import("std");
const collections = @import("../collections.zig");
const ListView = @import("list_view.zig").ListView;

/// Generic MVC list controller
/// Owns both the model (SortedList) and view (ListView) and wires them together
///
/// Usage:
/// ```zig
/// const DeviceController = ListController(
///     models.Device,           // Model type
///     DeviceListItem,          // View item type
///     DeviceListItem.create,   // Factory function
/// );
///
/// var controller = try DeviceController.create(allocator, sortByLastSeen);
/// defer controller.destroy();
///
/// // Add items to model - view updates automatically
/// try controller.insert(device);
/// ```
pub fn ListController(
    comptime ModelType: type,
    comptime ViewItemType: type,
    comptime createItemFn: fn (allocator: std.mem.Allocator, model: *const ModelType) anyerror!*ViewItemType,
) type {
    return struct {
        const Self = @This();
        const SortedListType = collections.SortedList(ModelType);
        const ListViewType = ListView(ViewItemType);

        allocator: std.mem.Allocator,
        model: SortedListType,
        view: *ListViewType,

        /// Map from model items to view items for efficient lookup
        item_map: std.AutoHashMap(*const ModelType, *ViewItemType),

        pub fn create(
            allocator: std.mem.Allocator,
            sort_fn: *const fn (context: void, a: ModelType, b: ModelType) bool,
        ) !*Self {
            const self = try allocator.create(Self);
            errdefer allocator.destroy(self);

            // Create model
            self.model = SortedListType.init(allocator, sort_fn);
            errdefer self.model.deinit();

            // Create view
            self.view = try ListViewType.create(allocator);
            errdefer self.view.destroy();

            self.allocator = allocator;
            self.item_map = std.AutoHashMap(*const ModelType, *ViewItemType).init(allocator);
            errdefer self.item_map.deinit();

            try self.model.addObserver(onModelChanged, self);

            return self;
        }

        pub fn destroy(self: *Self) void {
            self.model.removeObserver(onModelChanged);
            self.item_map.deinit();
            self.model.deinit();
            self.view.destroy();
            self.allocator.destroy(self);
        }

        /// Get the GTK widget for embedding in UI
        pub fn getWidget(self: *Self) *anyopaque {
            return self.view.getWidget();
        }

        /// Insert item into model (view updates automatically)
        pub fn insert(self: *Self, item: ModelType) !void {
            _ = try self.model.insert(item);
        }

        /// Remove item at index from model (view updates automatically)
        pub fn remove(self: *Self, index: usize) void {
            _ = self.model.remove(index);
        }

        /// Update item at index (view updates automatically)
        pub fn update(self: *Self, index: usize, item: ModelType) !void {
            try self.model.update(index, item);
        }

        /// Clear all items
        pub fn clear(self: *Self) void {
            self.model.clear();
            self.item_map.clearRetainingCapacity();
        }

        /// Get count of items
        pub fn count(self: *const Self) usize {
            return self.model.count();
        }

        /// Observer callback - called when model changes
        fn onModelChanged(change: SortedListType.Change, context: ?*anyopaque) void {
            const self: *Self = @ptrCast(@alignCast(context.?));

            switch (change.change_type) {
                .inserted => {
                    const model_item = change.item.?;
                    const view_item = createItemFn(self.allocator, model_item) catch {
                        std.debug.print("Failed to create view item\n", .{});
                        return;
                    };

                    self.view.insertItem(change.index, view_item) catch {
                        view_item.destroy(self.allocator);
                        return;
                    };

                    self.item_map.put(model_item, view_item) catch {};
                },

                .removed => {
                    const model_item = change.item.?;
                    if (self.item_map.fetchRemove(model_item)) |kv| {
                        const view_item = kv.value;
                        self.view.removeItem(view_item);
                    }
                },

                .updated => {
                    const model_item = change.item.?;
                    if (self.item_map.get(model_item)) |view_item| {
                        view_item.update(model_item);
                    }
                },

                .reordered => {
                    // Full rebuild
                    self.view.clear();
                    self.item_map.clearRetainingCapacity();

                    for (self.model.slice()) |*model_item| {
                        const view_item = createItemFn(self.allocator, model_item) catch continue;
                        self.view.appendItem(view_item) catch {
                            view_item.destroy(self.allocator);
                            continue;
                        };
                        self.item_map.put(model_item, view_item) catch {};
                    }
                },
            }
        }

        /// Set CSS class on the view
        pub fn setCssClass(self: *Self, class_name: [*:0]const u8) void {
            self.view.setCssClass(class_name);
        }
    };
}
