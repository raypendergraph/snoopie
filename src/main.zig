const std = @import("std");
const bt = @import("bluetooth.zig");
const dbus_provider = @import("bluetooth/dbus_provider.zig");
const primitives = @import("bluetooth/primitives.zig");
const Device = @import("bluetooth/models/device.zig").Device;
const DeviceRegistry = @import("bluetooth/models/device_registry.zig").DeviceRegistry;
const gui = @import("bluetooth/gui.zig");
const core = @import("core.zig");
const ObjectChange = core.data.ObjectChange;

const c = @cImport({
    @cDefine("GLIB_DISABLE_DEPRECATION_WARNINGS", "1");
    @cInclude("gtk/gtk.h");
    @cInclude("cairo.h");
});

const AppData = struct {
    allocator: std.mem.Allocator,
    bt_provider: dbus_provider.DBusProvider,
    provider_started: bool,
    device_registry: DeviceRegistry,
    device_list: *gui.DeviceList,
};

var app_data: AppData = undefined;

fn onScanClicked(button: *c.GtkButton, user_data: ?*anyopaque) callconv(.c) void {
    _ = button;
    _ = user_data;

    std.debug.print("\n=== Starting Bluetooth Scan ===\n", .{});

    // Start provider if not already started
    if (!app_data.provider_started) {
        app_data.bt_provider.start() catch |err| {
            std.debug.print("Failed to start provider: {any}\n", .{err});
            return;
        };
        app_data.provider_started = true;
        std.debug.print("DBus provider started\n", .{});
    }

    // Start discovery
    app_data.bt_provider.startDiscovery() catch |err| {
        std.debug.print("Failed to start discovery: {any}\n", .{err});
        return;
    };

    std.debug.print("Discovery started - devices will appear below:\n", .{});
}

// GTK timer callback to check for Bluetooth events
fn onCheckBluetoothEvents(user_data: ?*anyopaque) callconv(.c) c.gboolean {
    _ = user_data;

    const queue = app_data.bt_provider.getEventQueue();

    // Try to get events without blocking
    while (queue.tryPop()) |event| {
        handleBluetoothEvent(event);
    }

    return 1; // Continue timer
}

fn handleBluetoothEvent(event: primitives.Event) void {
    // Apply event to device registry (single source of truth)
    // The registry will automatically emit ObjectChange events via ObjectContext
    // which the GUI observes and updates automatically
    app_data.device_registry.applyEvent(event) catch |err| {
        std.debug.print("Failed to apply event to registry: {any}\n", .{err});
        return;
    };
}

// ObjectContext observer callback - automatically updates GUI when models change
fn onObjectChanged(device_list: *gui.DeviceList, change: ObjectChange) void {
    switch (change.change_type) {
        .inserted, .updated => {
            // Parse the object ID to get the device address
            // Format is "Device/AA:BB:CC:DD:EE:FF"
            if (std.mem.eql(u8, change.object_id.type_name, "Device")) {
                // Parse address from unique_id
                const address = primitives.Address.parse(change.object_id.unique_id) catch {
                    std.debug.print("Failed to parse address from object ID\n", .{});
                    return;
                };

                // Get the device from registry and update GUI
                if (app_data.device_registry.getDevice(address)) |device| {
                    device_list.updateDevice(device) catch |err| {
                        std.debug.print("Failed to update device list: {any}\n", .{err});
                    };
                }
            }
        },
        .deleted => {
            // Handle device removal (not currently used but could be)
            if (std.mem.eql(u8, change.object_id.type_name, "Device")) {
                const address = primitives.Address.parse(change.object_id.unique_id) catch return;
                device_list.removeDevice(address);
            }
        },
    }
}

fn onActivate(app: *c.GtkApplication, user_data: ?*anyopaque) callconv(.c) void {
    _ = user_data;

    // Create main window
    const window = c.gtk_application_window_new(app);
    c.gtk_window_set_title(@ptrCast(window), "Bluetooth Research Tool");
    c.gtk_window_set_default_size(@ptrCast(window), 800, 600);

    // Create header bar
    const header_bar = c.gtk_header_bar_new();
    c.gtk_window_set_titlebar(@ptrCast(window), header_bar);

    // Create main box container
    const main_box = c.gtk_box_new(c.GTK_ORIENTATION_VERTICAL, 10);
    c.gtk_widget_set_margin_start(main_box, 10);
    c.gtk_widget_set_margin_end(main_box, 10);
    c.gtk_widget_set_margin_top(main_box, 10);
    c.gtk_widget_set_margin_bottom(main_box, 10);
    c.gtk_window_set_child(@ptrCast(window), main_box);

    // Create label
    const label = c.gtk_label_new("Bluetooth Research Tool");
    c.gtk_box_append(@ptrCast(main_box), label);

    // Create info label
    const info_label = c.gtk_label_new("Click 'Scan' to discover nearby Bluetooth devices.");
    c.gtk_box_append(@ptrCast(main_box), info_label);

    // Create scan button
    const scan_button = c.gtk_button_new_with_label("Scan for Devices");
    _ = c.g_signal_connect_data(
        scan_button,
        "clicked",
        @ptrCast(&onScanClicked),
        null,
        null,
        0,
    );
    c.gtk_box_append(@ptrCast(main_box), scan_button);

    // Create device list
    app_data.device_list = gui.DeviceList.create(app_data.allocator) catch {
        std.debug.print("Failed to create device list\n", .{});
        return;
    };
    c.gtk_box_append(@ptrCast(main_box), @ptrCast(app_data.device_list.getWidget()));

    // Register ObjectContext observer to automatically update GUI when devices change
    app_data.device_registry.object_context.addObserver(
        app_data.device_list,
        onObjectChanged,
    ) catch {
        std.debug.print("Failed to register ObjectContext observer\n", .{});
        return;
    };

    // Set up timer to check for Bluetooth events (every 100ms)
    _ = c.g_timeout_add(100, onCheckBluetoothEvents, null);

    c.gtk_window_present(@ptrCast(window));
}

pub fn main() !void {
    // Set up allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize app data with DBus provider and device registry
    app_data = AppData{
        .allocator = allocator,
        .bt_provider = undefined,
        .provider_started = false,
        .device_registry = DeviceRegistry.init(allocator),
        .device_list = undefined, // Created in onActivate
    };
    defer app_data.device_registry.deinit();

    try app_data.bt_provider.init(allocator);
    defer app_data.bt_provider.deinit();

    std.debug.print("Bluetooth DBus Provider initialized\n", .{});
    std.debug.print("Make sure bluetoothd is running: systemctl status bluetooth\n", .{});
    std.debug.print("=====================================\n\n", .{});

    // Initialize GTK (in GTK4, gtk_init returns void)
    c.gtk_init();

    // Create GTK application
    const app = c.gtk_application_new("com.bt.research", c.G_APPLICATION_DEFAULT_FLAGS);
    if (app == null) {
        return error.AppCreationFailed;
    }
    defer c.g_object_unref(app);

    // Connect activate signal
    _ = c.g_signal_connect_data(
        app,
        "activate",
        @ptrCast(&onActivate),
        null,
        null,
        0,
    );

    // Run application
    const exit_status = c.g_application_run(@ptrCast(app), 0, null);
    std.process.exit(@intCast(exit_status));
}
