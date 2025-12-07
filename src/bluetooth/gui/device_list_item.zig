const std = @import("std");
const Device = @import("../models/device.zig").Device;
const primitives = @import("../primitives.zig");
const core = @import("../../core.zig");
const loadComponentCss = core.gui.gtk.loadComponentCss;

const c = @cImport({
    @cDefine("GLIB_DISABLE_DEPRECATION_WARNINGS", "1");
    @cInclude("gtk/gtk.h");
});

fn loadStyles() void {
    const ui_css = @embedFile("device_list_item.css");
    loadComponentCss(ui_css);
}

var styles_once = std.once(loadStyles);

/// Device list item widget - using GtkBuilder (XML-based)
/// The XML file creates and parents all widgets, we just get references
pub const DeviceListItem = struct {
    widget: *c.GtkBox,
    device_address: primitives.Address,

    // Child widgets (already created by builder)
    name_label: *c.GtkLabel,
    address_label: *c.GtkLabel,
    rssi_label: *c.GtkLabel,
    status_label: *c.GtkLabel,

    pub fn create(allocator: std.mem.Allocator, device: *const Device) !*DeviceListItem {
        const self = try allocator.create(DeviceListItem);
        const ui_xml = @embedFile("device_list_item.ui");
        errdefer allocator.destroy(self);

        styles_once.call();

        const builder = c.gtk_builder_new_from_string(ui_xml.ptr, ui_xml.len);
        if (builder == null) {
            return error.UILoadFailed;
        }
        defer c.g_object_unref(builder);

        // Get references to widgets that were created by the builder
        // No creation, no parenting - just get the objects
        const widget = c.gtk_builder_get_object(builder, "root_box");
        const name_label = c.gtk_builder_get_object(builder, "name_label");
        const address_label = c.gtk_builder_get_object(builder, "address_label");
        const rssi_label = c.gtk_builder_get_object(builder, "rssi_label");
        const status_label = c.gtk_builder_get_object(builder, "status_label");

        if (widget == null or name_label == null or address_label == null or
            rssi_label == null or status_label == null)
        {
            std.debug.print("Failed to get widget objects from UI file\n", .{});
            return error.UIObjectsNotFound;
        }

        // Keep a reference to the root widget so it doesn't get destroyed
        // when builder is unreffed
        _ = c.g_object_ref(widget);

        self.* = DeviceListItem{
            .widget = @ptrCast(widget),
            .device_address = device.address,
            .name_label = @ptrCast(name_label),
            .address_label = @ptrCast(address_label),
            .rssi_label = @ptrCast(rssi_label),
            .status_label = @ptrCast(status_label),
        };

        // Populate with initial device data
        self.update(device);

        return self;
    }

    pub fn destroy(self: *DeviceListItem, allocator: std.mem.Allocator) void {
        c.g_object_unref(self.widget);
        allocator.destroy(self);
    }

    /// Update the widget with new device data
    /// This is the ONLY place we manipulate the widgets
    pub fn update(self: *DeviceListItem, device: *const Device) void {
        // Update name
        const name = device.name orelse "Unknown Device";
        var name_buf: [256]u8 = undefined;
        const name_str = std.fmt.bufPrintZ(&name_buf, "{s}", .{name}) catch return;
        c.gtk_label_set_text(self.name_label, name_str.ptr);

        // Update address
        var addr_buf: [18]u8 = undefined;
        const addr_str = std.fmt.bufPrintZ(&addr_buf, "{any}", .{device.address}) catch "??:??:??:??:??:??";
        c.gtk_label_set_text(self.address_label, addr_str.ptr);

        // Update RSSI
        var rssi_buf: [32]u8 = undefined;
        const rssi_str = if (device.getCurrentRssi()) |rssi|
            std.fmt.bufPrintZ(&rssi_buf, "{} dBm", .{rssi}) catch "? dBm"
        else
            "? dBm";
        c.gtk_label_set_text(self.rssi_label, rssi_str.ptr);

        // Update connection status
        const status_text = if (device.isConnected()) "Connected" else "";
        c.gtk_label_set_text(self.status_label, status_text);

        // Update CSS class for connected state
        if (device.isConnected()) {
            c.gtk_widget_add_css_class(@ptrCast(@alignCast(self.status_label)), "connected");
        } else {
            c.gtk_widget_remove_css_class(@ptrCast(@alignCast(self.status_label)), "connected");
        }
    }

    pub fn getWidget(self: *DeviceListItem) *c.GtkWidget {
        return @ptrCast(self.widget);
    }
};
