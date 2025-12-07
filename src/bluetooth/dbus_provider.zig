const std = @import("std");
const provider = @import("provider.zig");
const primitives = @import("primitives.zig");
const core = @import("../core.zig");
const AsyncQueue = core.async.Queue;
const gdbus = @import("gdbus.zig");

/// DBus provider - interacts with BlueZ via DBus
/// Note: Requires GLib main loop to be running (e.g., GTK application)
pub const DBusProvider = struct {
    allocator: std.mem.Allocator,
    event_queue: AsyncQueue(primitives.Event),
    dbus_conn: ?gdbus.Connection = null,
    subscription_ids: std.ArrayList(u32),

    pub fn init(self: *DBusProvider, allocator: std.mem.Allocator) !void {
        self.allocator = allocator;
        self.event_queue = try AsyncQueue(primitives.Event).init(allocator, 64);
        self.dbus_conn = null;
        self.subscription_ids = std.ArrayList(u32){};
    }

    pub fn deinit(self: *DBusProvider) void {
        self.stop() catch {}; // Clean up any active connections
        self.subscription_ids.deinit(self.allocator);
        self.event_queue.deinit();
    }

    pub fn start(self: *DBusProvider) !void {
        if (self.dbus_conn != null) {
            return error.AlreadyRunning;
        }

        // Connect to system bus
        self.dbus_conn = try gdbus.Connection.systemBus();

        // Subscribe to BlueZ signals
        // Signals will be delivered via onDbusSignal callback from GLib main loop
        try self.subscribeToSignals();
    }

    pub fn stop(self: *DBusProvider) !void {
        if (self.dbus_conn) |conn| {
            // Unsubscribe from all signals
            for (self.subscription_ids.items) |id| {
                conn.unsubscribe(id);
            }
            self.subscription_ids.clearRetainingCapacity();

            var conn_mut = self.dbus_conn.?;
            conn_mut.close();
            self.dbus_conn = null;
        }
    }

    pub fn getEventQueue(self: *DBusProvider) *AsyncQueue(primitives.Event) {
        return &self.event_queue;
    }

    fn subscribeToSignals(self: *DBusProvider) !void {
        const conn = self.dbus_conn orelse return error.NoConnection;

        // Subscribe to InterfacesAdded (device discovery)
        const id1 = conn.subscribeSignal(
            BLUEZ_SERVICE,
            "org.freedesktop.DBus.ObjectManager",
            "InterfacesAdded",
            null, // any object path
            onDbusSignal,
            self,
        );
        try self.subscription_ids.append(self.allocator, id1);

        // Subscribe to PropertiesChanged (state changes, notifications)
        const id2 = conn.subscribeSignal(
            BLUEZ_SERVICE,
            "org.freedesktop.DBus.Properties",
            "PropertiesChanged",
            null, // any object path
            onDbusSignal,
            self,
        );
        try self.subscription_ids.append(self.allocator, id2);

        // Subscribe to InterfacesRemoved (device removal)
        const id3 = conn.subscribeSignal(
            BLUEZ_SERVICE,
            "org.freedesktop.DBus.ObjectManager",
            "InterfacesRemoved",
            null,
            onDbusSignal,
            self,
        );
        try self.subscription_ids.append(self.allocator, id3);
    }

    pub fn getAdapterInfo(self: *DBusProvider) !primitives.AdapterInfo {
        // TODO: Query DBus for adapter information
        // For now, return stub data
        return primitives.AdapterInfo{
            .address = primitives.Address.ZERO,
            .name = try self.allocator.dupe(u8, "hci0"),
            .powered = true,
            .discoverable = false,
            .pairable = true,
            .discovering = false,
        };
    }

    pub fn startDiscovery(self: *DBusProvider) !void {
        const conn = self.dbus_conn orelse return error.NotConnected;

        std.debug.print("[DBusProvider] Starting discovery...\n", .{});

        // Call StartDiscovery method on adapter
        const result = conn.call(
            BLUEZ_SERVICE,
            BLUEZ_ADAPTER_PATH,
            BLUEZ_ADAPTER_INTERFACE,
            "StartDiscovery",
            null, // no parameters
            -1, // default timeout
        ) catch |err| {
            std.debug.print("[DBusProvider] StartDiscovery failed: {any}\n", .{err});
            return err;
        };

        gdbus.c.g_variant_unref(result);

        std.debug.print("[DBusProvider] Discovery started\n", .{});
    }

    pub fn stopDiscovery(_: *DBusProvider) !void {
        // TODO: Call BlueZ StopDiscovery via DBus
        std.debug.print("[DBusProvider] Stopping discovery...\n", .{});
    }

    pub fn connect(_: *DBusProvider, address: primitives.Address) !void {
        // TODO: Call BlueZ Device.Connect via DBus
        std.debug.print("[DBusProvider] Connecting to device {}\n", .{address});
    }

    pub fn disconnect(_: *DBusProvider, address: primitives.Address) !void {
        // TODO: Call BlueZ Device.Disconnect via DBus
        std.debug.print("[DBusProvider] Disconnecting from device {}\n", .{address});
    }

    pub fn discoverServices(_: *DBusProvider, address: primitives.Address) !void {
        // TODO: Query BlueZ for GATT services via DBus
        std.debug.print("[DBusProvider] Discovering services for {}\n", .{address});
    }

    pub fn readCharacteristic(
        _: *DBusProvider,
        address: primitives.Address,
        service_uuid: primitives.UUID,
        char_uuid: primitives.UUID,
    ) ![]const u8 {
        // TODO: Call BlueZ GattCharacteristic.ReadValue via DBus
        std.debug.print("[DBusProvider] Reading characteristic {} from service {} on {}\n", .{
            char_uuid,
            service_uuid,
            address,
        });
        return &[_]u8{};
    }

    pub fn writeCharacteristic(
        _: *DBusProvider,
        address: primitives.Address,
        service_uuid: primitives.UUID,
        char_uuid: primitives.UUID,
        value: []const u8,
    ) !void {
        // TODO: Call BlueZ GattCharacteristic.WriteValue via DBus
        std.debug.print("[DBusProvider] Writing {} bytes to characteristic {} from service {} on {}\n", .{
            value.len,
            char_uuid,
            service_uuid,
            address,
        });
    }

    pub fn enableNotifications(
        _: *DBusProvider,
        address: primitives.Address,
        service_uuid: primitives.UUID,
        char_uuid: primitives.UUID,
    ) !void {
        // TODO: Call BlueZ GattCharacteristic.StartNotify via DBus
        std.debug.print("[DBusProvider] Enabling notifications for {} from service {} on {}\n", .{
            char_uuid,
            service_uuid,
            address,
        });
    }

    pub fn disableNotifications(
        _: *DBusProvider,
        address: primitives.Address,
        service_uuid: primitives.UUID,
        char_uuid: primitives.UUID,
    ) !void {
        // TODO: Call BlueZ GattCharacteristic.StopNotify via DBus
        std.debug.print("[DBusProvider] Disabling notifications for {} from service {} on {}\n", .{
            char_uuid,
            service_uuid,
            address,
        });
    }

    /// GDBus signal callback - called from GLib's main loop (GTK event loop)
    /// This is called on the main thread whenever a BlueZ signal arrives
    fn onDbusSignal(
        connection: ?*gdbus.c.GDBusConnection,
        sender_name: [*c]const u8,
        object_path: [*c]const u8,
        interface_name: [*c]const u8,
        signal_name: [*c]const u8,
        parameters: ?*gdbus.c.GVariant,
        user_data: ?*anyopaque,
    ) callconv(.c) void {
        _ = connection;
        _ = sender_name;

        const self: *DBusProvider = @ptrCast(@alignCast(user_data orelse return));

        const path = std.mem.span(object_path);
        const iface = std.mem.span(interface_name);
        const signal = std.mem.span(signal_name);

        std.debug.print("[DBusProvider] Signal: {s}.{s} on {s}\n", .{ iface, signal, path });

        // Dispatch based on interface.signal combination
        if (std.mem.eql(u8, iface, "org.freedesktop.DBus.ObjectManager")) {
            if (std.mem.eql(u8, signal, "InterfacesAdded")) {
                self.handleInterfacesAddedSignal(path, parameters) catch |err| {
                    std.debug.print("[DBusProvider] Failed to handle InterfacesAdded: {any}\n", .{err});
                };
            } else if (std.mem.eql(u8, signal, "InterfacesRemoved")) {
                std.debug.print("[DBusProvider] TODO: Handle InterfacesRemoved\n", .{});
            }
        } else if (std.mem.eql(u8, iface, "org.freedesktop.DBus.Properties")) {
            if (std.mem.eql(u8, signal, "PropertiesChanged")) {
                std.debug.print("[DBusProvider] TODO: Handle PropertiesChanged\n", .{});
            }
        }
    }

    /// Handle org.freedesktop.DBus.ObjectManager.InterfacesAdded signal
    /// Parses the GVariant and creates a device_discovered event
    fn handleInterfacesAddedSignal(self: *DBusProvider, object_path: []const u8, parameters: ?*gdbus.c.GVariant) !void {
        const variant = parameters orelse return;

        // InterfacesAdded signature: (oa{sa{sv}})
        // object_path is already provided as first param
        // variant contains: dict<string, dict<string, variant>>

        // Check if this is a Device interface
        if (!std.mem.startsWith(u8, object_path, "/org/bluez/hci")) return;
        if (std.mem.indexOf(u8, object_path, "/dev_") == null) return;

        // Get the interface dictionary
        var interfaces_iter: gdbus.c.GVariantIter = undefined;
        _ = gdbus.c.g_variant_iter_init(&interfaces_iter, variant);

        var interface_name: [*c]const u8 = undefined;
        var properties_variant: ?*gdbus.c.GVariant = null;

        // Iterate through interfaces
        while (gdbus.c.g_variant_iter_next(&interfaces_iter, "{&s@a{sv}}", &interface_name, &properties_variant) != 0) {
            defer if (properties_variant) |v| gdbus.c.g_variant_unref(v);

            const iface = std.mem.span(interface_name);

            // We're interested in org.bluez.Device1
            if (std.mem.eql(u8, iface, "org.bluez.Device1")) {
                const device = self.parseDeviceProperties(object_path, properties_variant.?) catch |err| {
                    std.debug.print("[DBusProvider] Failed to parse device properties: {any}\n", .{err});
                    continue;
                };

                // Create event and push to queue
                const event = primitives.Event{ .device_discovered = device };
                self.event_queue.push(event) catch |err| {
                    std.debug.print("[DBusProvider] Failed to queue event: {any}\n", .{err});
                    // Clean up device on error
                    var dev_mut = device;
                    dev_mut.deinit(self.allocator);
                };

                std.debug.print("[DBusProvider] Device discovered: {s}\n", .{object_path});
                break;
            }
        }
    }

    /// Parse BlueZ Device1 properties into DeviceDiscovered
    fn parseDeviceProperties(self: *DBusProvider, object_path: []const u8, properties: *gdbus.c.GVariant) !primitives.DeviceDiscovered {
        const props_variant = properties;

        // Initialize with defaults
        var device = primitives.DeviceDiscovered{
            .address = primitives.Address.ZERO,
            .address_type = .public,
            .name = null,
            .rssi = -127,
            .device_type = .unknown,
            .class_of_device = null,
            .manufacturer_data = null,
            .service_uuids = null,
            .tx_power = null,
            .appearance = null,
        };

        // Extract address from object path: /org/bluez/hci0/dev_XX_XX_XX_XX_XX_XX
        if (std.mem.lastIndexOf(u8, object_path, "dev_")) |dev_idx| {
            const addr_str = object_path[dev_idx + 4 ..];
            var addr_buf: [17]u8 = undefined;
            var buf_idx: usize = 0;
            for (addr_str) |char| {
                if (char == '_') {
                    if (buf_idx < 17) {
                        addr_buf[buf_idx] = ':';
                        buf_idx += 1;
                    }
                } else {
                    if (buf_idx < 17) {
                        addr_buf[buf_idx] = char;
                        buf_idx += 1;
                    }
                }
            }
            device.address = primitives.Address.parse(addr_buf[0 .. buf_idx - 1]) catch primitives.Address.ZERO;
        }

        // Iterate through properties
        var props_iter: gdbus.c.GVariantIter = undefined;
        _ = gdbus.c.g_variant_iter_init(&props_iter, props_variant);

        var key: [*c]const u8 = undefined;
        var value_variant: ?*gdbus.c.GVariant = null;

        while (gdbus.c.g_variant_iter_next(&props_iter, "{&sv}", &key, &value_variant) != 0) {
            defer if (value_variant) |v| gdbus.c.g_variant_unref(v);

            const prop_name = std.mem.span(key);
            const val = value_variant orelse continue;

            if (std.mem.eql(u8, prop_name, "Name")) {
                if (gdbus.c.g_variant_get_string(val, null)) |name_ptr| {
                    const name = std.mem.span(name_ptr);
                    device.name = self.allocator.dupe(u8, name) catch null;
                }
            } else if (std.mem.eql(u8, prop_name, "RSSI")) {
                device.rssi = @intCast(gdbus.c.g_variant_get_int16(val));
            } else if (std.mem.eql(u8, prop_name, "TxPower")) {
                device.tx_power = @intCast(gdbus.c.g_variant_get_int16(val));
            } else if (std.mem.eql(u8, prop_name, "Appearance")) {
                device.appearance = @intCast(gdbus.c.g_variant_get_uint16(val));
            }
            // TODO: Parse more properties:
            // - AddressType
            // - Class (for Classic BT)
            // - ManufacturerData
            // - ServiceUUIDs
        }

        return device;
    }

    /// Handle org.freedesktop.DBus.Properties.PropertiesChanged signal
    /// Converts to various events based on object path and property
    fn handlePropertiesChanged(self: *DBusProvider, signal: anytype) bool {
        _ = self;
        _ = signal;
        // TODO: Check if signal is PropertiesChanged
        // if (!std.mem.eql(u8, signal.interface, "org.freedesktop.DBus.Properties")) return false;
        // if (!std.mem.eql(u8, signal.member, "PropertiesChanged")) return false;

        // TODO: Dispatch based on object path and changed properties
        // if (isAdapterPath(signal.path)) {
        //     handleAdapterPropertiesChanged(self, signal);
        // } else if (isDevicePath(signal.path)) {
        //     handleDevicePropertiesChanged(self, signal);
        // } else if (isCharacteristicPath(signal.path)) {
        //     handleCharacteristicPropertiesChanged(self, signal);
        // }

        return false;
    }

    /// Handle org.freedesktop.DBus.ObjectManager.InterfacesRemoved signal
    /// Could be used to detect device disconnection
    fn handleInterfacesRemoved(self: *DBusProvider, signal: anytype) bool {
        _ = self;
        _ = signal;
        // TODO: Handle device removal if needed
        return false;
    }

    // Helper conversion functions

    fn handleAdapterPropertiesChanged(self: *DBusProvider, signal: anytype) void {
        _ = self;
        _ = signal;
        // TODO: Parse adapter state changes (Powered, Discovering, etc.)
        // and push Event.adapter_state_changed
    }

    fn handleDevicePropertiesChanged(self: *DBusProvider, signal: anytype) void {
        _ = self;
        _ = signal;
        // TODO: Parse device property changes (Connected, RSSI, etc.)
        // and push Event.device_connected or updated device_discovered
    }

    fn handleCharacteristicPropertiesChanged(self: *DBusProvider, signal: anytype) void {
        _ = self;
        _ = signal;
        // TODO: Parse characteristic Value property changes
        // and push Event.characteristic_changed (notifications/indications)
    }

    /// Convert this implementation to a Provider interface
    pub fn asProvider(self: *DBusProvider) provider.Provider {
        return provider.createProvider(DBusProvider, self);
    }
};

// BlueZ DBus constants

/// DBus object path for BlueZ adapter
const BLUEZ_ADAPTER_PATH = "/org/bluez/hci0";

/// DBus service name for BlueZ
const BLUEZ_SERVICE = "org.bluez";

/// DBus interface names
const BLUEZ_ADAPTER_INTERFACE = "org.bluez.Adapter1";
const BLUEZ_DEVICE_INTERFACE = "org.bluez.Device1";
const BLUEZ_GATT_SERVICE_INTERFACE = "org.bluez.GattService1";
const BLUEZ_GATT_CHARACTERISTIC_INTERFACE = "org.bluez.GattCharacteristic1";
