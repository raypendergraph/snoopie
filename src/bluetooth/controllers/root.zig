const std = @import("std");
const c = @import("root").c;
const core = @import("core");
const ObjectChange = core.data.ObjectChange;

// Bluetooth components - use relative imports since we're inside bluetooth module
const DeviceRegistry = @import("../domain/device_registry.zig").DeviceRegistry;
const MainPanel = @import("../gui/main_panel.zig").MainPanel;
const DBusProvider = @import("../providers/dbus_provider.zig").DBusProvider;
const Address = @import("../primitives.zig").Address;

/// Main Bluetooth controller - handles all Bluetooth business logic and UI coordination
pub const RootController = struct {
    allocator: std.mem.Allocator,
    device_registry: DeviceRegistry,
    main_panel: *MainPanel,
    provider: *DBusProvider,
    scan_button: ?*c.GtkWidget,

    pub fn init(allocator: std.mem.Allocator) !*RootController {
        const self = try allocator.create(RootController);

        // Initialize device registry
        const device_registry = DeviceRegistry.init(allocator);

        // Initialize Bluetooth provider
        const provider = try allocator.create(DBusProvider);
        try provider.init(allocator);

        // Start the provider (connect to D-Bus and subscribe to signals)
        try provider.start();

        // Create main panel
        const main_panel = try MainPanel.create(allocator);

        self.* = RootController{
            .allocator = allocator,
            .device_registry = device_registry,
            .main_panel = main_panel,
            .provider = provider,
            .scan_button = null,
        };

        // Register observer for device changes
        try self.device_registry.object_context.addObserver(self, onObjectChanged);

        return self;
    }

    pub fn deinit(self: *RootController) void {
        self.provider.stop() catch {}; // Stop provider and disconnect from D-Bus
        self.provider.deinit();
        self.main_panel.deinit();
        self.device_registry.deinit();
        self.allocator.destroy(self);
    }

    /// Get the main UI widget
    pub fn getWidget(self: *RootController) *c.GtkWidget {
        return self.main_panel.getWidget();
    }

    /// Set the scan button reference (called from UI setup)
    pub fn setScanButton(self: *RootController, button: *c.GtkWidget) void {
        self.scan_button = button;
    }

    /// Handle scan button clicked
    pub fn onScanClicked(self: *RootController) void {
        std.debug.print("Scan button clicked\n", .{});

        // Start discovery
        self.provider.startDiscovery() catch |err| {
            std.debug.print("Failed to start discovery: {any}\n", .{err});
            return;
        };

        // Update button state (could disable it, change text, etc.)
        if (self.scan_button) |button| {
            c.gtk_button_set_label(@ptrCast(button), "Scanning...");
            c.gtk_widget_set_sensitive(button, 0);
        }
    }

    /// Check for Bluetooth events (called by timer)
    pub fn checkBluetoothEvents(self: *RootController) void {
        const event_queue = self.provider.getEventQueue();
        while (event_queue.tryPop()) |event| {
            std.debug.print("[checkBluetoothEvents] Got event from queue, type: {s}\n", .{@tagName(event)});
            var mut_event = event;
            std.debug.print("[checkBluetoothEvents] Applying event to registry...\n", .{});
            self.device_registry.applyEvent(mut_event) catch |err| {
                std.debug.print("[checkBluetoothEvents] Failed to apply event: {any}\n", .{err});
            };
            std.debug.print("[checkBluetoothEvents] Deinit event...\n", .{});
            mut_event.deinit(self.allocator);
            std.debug.print("[checkBluetoothEvents] Event processed successfully\n", .{});
        }
    }

    /// ObjectContext observer callback - updates GUI when devices change
    fn onObjectChanged(self: *RootController, change: ObjectChange) void {
        std.debug.print("[onObjectChanged] Change type: {s}, object type: {s}, ID: {s}\n", .{
            @tagName(change.change_type),
            change.object_id.type_name,
            change.object_id.unique_id,
        });

        switch (change.change_type) {
            .inserted, .updated => {
                if (std.mem.eql(u8, change.object_id.type_name, "Device")) {
                    std.debug.print("[onObjectChanged] Processing Device change\n", .{});
                    // Parse address from ObjectID
                    const address = Address.parse(change.object_id.unique_id) catch {
                        std.debug.print("[onObjectChanged] Failed to parse address from object ID: {s}\n", .{change.object_id.unique_id});
                        return;
                    };
                    std.debug.print("[onObjectChanged] Parsed address successfully\n", .{});

                    // Get device pointer directly from registry
                    std.debug.print("[onObjectChanged] Getting device from registry...\n", .{});
                    if (self.device_registry.getDevice(address)) |device| {
                        std.debug.print("[onObjectChanged] Got device, updating UI...\n", .{});
                        self.main_panel.device_list.updateDevice(device) catch |err| {
                            std.debug.print("[onObjectChanged] Failed to update device list: {any}\n", .{err});
                        };
                        std.debug.print("[onObjectChanged] UI update complete\n", .{});
                    } else {
                        std.debug.print("[onObjectChanged] Device not found in registry\n", .{});
                    }
                }
            },
            .deleted => {
                if (std.mem.eql(u8, change.object_id.type_name, "Device")) {
                    const address = Address.parse(change.object_id.unique_id) catch return;
                    self.main_panel.device_list.removeDevice(address);
                }
            },
        }
    }
};

/// C callback wrappers for GTK
pub fn onScanClickedCallback(_: *c.GtkButton, user_data: ?*anyopaque) callconv(.c) void {
    const controller: *RootController = @ptrCast(@alignCast(user_data.?));
    controller.onScanClicked();
}

pub fn onCheckBluetoothEventsCallback(user_data: ?*anyopaque) callconv(.c) c.gboolean {
    const controller: *RootController = @ptrCast(@alignCast(user_data.?));
    controller.checkBluetoothEvents();
    return 1;
}
