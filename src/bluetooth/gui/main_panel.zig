const std = @import("std");
const c = @import("root").c;
const core = @import("core");
const DeviceList = @import("device_list.zig").DeviceList;
const loadComponentCss = core.gui.gtk.loadComponentCss;

fn loadStyles() void {
    const ui_css = @embedFile("main_panel.css");
    loadComponentCss(ui_css);
}

var styles_once = std.once(loadStyles);

/// Main Bluetooth panel - contains all Bluetooth UI components
pub const MainPanel = struct {
    widget: *c.GtkBox,
    device_list: *DeviceList,
    allocator: std.mem.Allocator,

    pub fn create(allocator: std.mem.Allocator) !*MainPanel {
        const self = try allocator.create(MainPanel);
        const ui_xml = @embedFile("main_panel.ui");
        errdefer allocator.destroy(self);

        styles_once.call();

        const builder = c.gtk_builder_new_from_string(ui_xml.ptr, ui_xml.len);
        if (builder == null) {
            return error.UILoadFailed;
        }
        defer c.g_object_unref(builder);

        // Get references to widgets that were created by the builder
        const widget = c.gtk_builder_get_object(builder, "root_box");

        if (widget == null) {
            std.debug.print("Failed to get widget objects from UI file\n", .{});
            return error.UIObjectsNotFound;
        }

        // Keep a reference to the root widget so it doesn't get destroyed
        // when builder is unreffed
        _ = c.g_object_ref(widget);

        // Create device list
        const device_list = try DeviceList.create(allocator);
        c.gtk_widget_set_vexpand(@ptrCast(device_list.getWidget()), 1);
        c.gtk_box_append(@ptrCast(widget), @ptrCast(device_list.getWidget()));

        self.* = MainPanel{
            .widget = @ptrCast(widget),
            .device_list = device_list,
            .allocator = allocator,
        };

        return self;
    }

    pub fn deinit(self: *MainPanel) void {
        self.device_list.destroy();
        c.g_object_unref(self.widget);
        self.allocator.destroy(self);
    }

    pub fn getWidget(self: *MainPanel) *c.GtkWidget {
        return @ptrCast(self.widget);
    }

    pub fn getDeviceList(self: *MainPanel) *DeviceList {
        return self.device_list;
    }
};
