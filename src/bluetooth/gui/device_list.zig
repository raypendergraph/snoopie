const std = @import("std");
const Device = @import("../models/device.zig").Device;
const DeviceRegistry = @import("../models/device_registry.zig").DeviceRegistry;
const primitives = @import("../primitives.zig");
const DeviceListItem = @import("device_list_item.zig").DeviceListItem;

const c = @cImport({
    @cDefine("GLIB_DISABLE_DEPRECATION_WARNINGS", "1");
    @cInclude("gtk/gtk.h");
});

/// Device list widget - displays all discovered Bluetooth devices
pub const DeviceList = struct {
    allocator: std.mem.Allocator,
    scroll_window: *c.GtkScrolledWindow,
    list_box: *c.GtkListBox,
    items: std.AutoHashMap(primitives.Address, *DeviceListItem),

    /// Hash function for Address (required for HashMap)
    const AddressContext = struct {
        pub fn hash(_: @This(), addr: primitives.Address) u64 {
            var hasher = std.hash.Wyhash.init(0);
            hasher.update(&addr.bytes);
            return hasher.final();
        }

        pub fn eql(_: @This(), a: primitives.Address, b: primitives.Address) bool {
            return a.eql(b);
        }
    };

    pub fn create(allocator: std.mem.Allocator) !*DeviceList {
        const self = try allocator.create(DeviceList);
        errdefer allocator.destroy(self);

        // Create scrolled window
        const scroll_window = c.gtk_scrolled_window_new();
        c.gtk_scrolled_window_set_policy(
            @ptrCast(scroll_window),
            c.GTK_POLICY_NEVER,
            c.GTK_POLICY_AUTOMATIC,
        );
        c.gtk_widget_set_vexpand(scroll_window, 1);

        // Create list box
        const list_box = c.gtk_list_box_new();
        c.gtk_list_box_set_selection_mode(@ptrCast(list_box), c.GTK_SELECTION_SINGLE);
        c.gtk_widget_add_css_class(list_box, "device-list");

        // Add list box to scrolled window
        c.gtk_scrolled_window_set_child(@ptrCast(scroll_window), list_box);

        self.* = DeviceList{
            .allocator = allocator,
            .scroll_window = @ptrCast(scroll_window),
            .list_box = @ptrCast(list_box),
            .items = std.AutoHashMap(primitives.Address, *DeviceListItem).init(allocator),
        };

        return self;
    }

    pub fn destroy(self: *DeviceList) void {
        // Destroy all items
        var it = self.items.valueIterator();
        while (it.next()) |item| {
            item.*.destroy(self.allocator);
        }
        self.items.deinit();
        self.allocator.destroy(self);
    }

    /// Get the GTK widget (the scrolled window)
    pub fn getWidget(self: *DeviceList) *c.GtkWidget {
        return @ptrCast(@alignCast(self.scroll_window));
    }

    /// Update the list with devices from the registry
    pub fn updateFromRegistry(self: *DeviceList, registry: *DeviceRegistry) !void {
        // Get all devices sorted by last seen
        const devices = try registry.getDevicesSortedByLastSeen(self.allocator);
        defer self.allocator.free(devices);

        // Track which devices we've seen in this update
        var seen_addresses = std.AutoHashMap(primitives.Address, void).init(self.allocator);
        defer seen_addresses.deinit();

        for (devices) |device| {
            try seen_addresses.put(device.address, {});

            if (self.items.get(device.address)) |item| {
                // Update existing item
                item.update(&device);
            } else {
                // Create new item
                const item = try DeviceListItem.create(self.allocator, &device);
                try self.items.put(device.address, item);
                c.gtk_list_box_append(self.list_box, item.getWidget());
            }
        }

        // Remove items for devices that no longer exist
        // (In practice, devices rarely disappear, but this keeps the list clean)
        var items_to_remove = std.ArrayList(primitives.Address).init(self.allocator);
        defer items_to_remove.deinit();

        var it = self.items.keyIterator();
        while (it.next()) |addr| {
            if (!seen_addresses.contains(addr.*)) {
                try items_to_remove.append(addr.*);
            }
        }

        for (items_to_remove.items) |addr| {
            if (self.items.fetchRemove(addr)) |kv| {
                const item = kv.value;
                c.gtk_list_box_remove(self.list_box, item.getWidget());
                item.destroy(self.allocator);
            }
        }
    }

    /// Add or update a single device
    pub fn updateDevice(self: *DeviceList, device: *const Device) !void {
        if (self.items.get(device.address)) |item| {
            // Update existing item
            item.update(device);
        } else {
            // Create new item
            const item = try DeviceListItem.create(self.allocator, device);
            try self.items.put(device.address, item);

            // Prepend new devices to top of list (most recent first)
            c.gtk_list_box_prepend(self.list_box, @ptrCast(item.getWidget()));
        }
    }

    /// Remove a device from the list
    pub fn removeDevice(self: *DeviceList, address: primitives.Address) void {
        if (self.items.fetchRemove(address)) |kv| {
            const item = kv.value;
            c.gtk_list_box_remove(self.list_box, @ptrCast(item.getWidget()));
            item.destroy(self.allocator);
        }
    }

    /// Clear all devices from the list
    pub fn clear(self: *DeviceList) void {
        var it = self.items.valueIterator();
        while (it.next()) |item| {
            c.gtk_list_box_remove(self.list_box, item.*.getWidget());
            item.*.destroy(self.allocator);
        }
        self.items.clearRetainingCapacity();
    }

    /// Get count of devices in the list
    pub fn getDeviceCount(self: *const DeviceList) usize {
        return self.items.count();
    }
};
