const std = @import("std");
const Device = @import("../models/device.zig").Device;
const primitives = @import("../primitives.zig");
const DeviceListItem = @import("device_list_item.zig").DeviceListItem;
const core = @import("core");
const loadComponentCss = core.gui.gtk.loadComponentCss;

const c = @cImport({
    @cDefine("GLIB_DISABLE_DEPRECATION_WARNINGS", "1");
    @cInclude("gtk/gtk.h");
});

fn loadStyles() void {
    const ui_css = @embedFile("device_list.css");
    loadComponentCss(ui_css);
}

var styles_once = std.once(loadStyles);

/// Device list widget - displays all discovered Bluetooth devices
pub const DeviceList = struct {
    allocator: std.mem.Allocator,
    scroll_window: *c.GtkScrolledWindow,
    list_box: *c.GtkListBox,
    placeholder: *c.GtkWidget,
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

        styles_once.call();

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

        // Create placeholder for empty list
        const placeholder = c.gtk_label_new("No devices discovered yet.\nClick 'Start Scan' to begin.");
        c.gtk_widget_add_css_class(placeholder, "device-list-empty");
        c.gtk_label_set_justify(@ptrCast(placeholder), c.GTK_JUSTIFY_CENTER);
        c.gtk_list_box_set_placeholder(@ptrCast(list_box), placeholder);

        // Add list box to scrolled window
        c.gtk_scrolled_window_set_child(@ptrCast(scroll_window), list_box);

        self.* = DeviceList{
            .allocator = allocator,
            .scroll_window = @ptrCast(scroll_window),
            .list_box = @ptrCast(list_box),
            .placeholder = placeholder,
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

    /// Add or update a single device
    pub fn updateDevice(self: *DeviceList, device: *const Device) !void {
        const addr = device.data.address;

        if (self.items.get(addr)) |item| {
            // Update existing item
            item.update(device);
        } else {
            // Create new item
            const item = try DeviceListItem.create(self.allocator, device);
            try self.items.put(addr, item);

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
