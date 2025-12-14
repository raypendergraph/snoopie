const std = @import("std");
const primitives = @import("../primitives.zig");
const Device = @import("../models/device.zig").Device;
const core = @import("core");
const ObjectContext = core.data.ObjectContext;
const ObjectID = core.data.ObjectID;

/// Device registry - maintains the current state of all known devices
/// This is the event-sourced "view" that gets updated as events arrive
pub const DeviceRegistry = struct {
    allocator: std.mem.Allocator,
    devices: std.AutoHashMap(primitives.Address, *Device),
    object_context: ObjectContext,

    pub fn init(allocator: std.mem.Allocator) DeviceRegistry {
        return DeviceRegistry{
            .allocator = allocator,
            .devices = std.AutoHashMap(primitives.Address, *Device).init(allocator),
            .object_context = ObjectContext.init(allocator),
        };
    }

    pub fn deinit(self: *DeviceRegistry) void {
        var it = self.devices.valueIterator();
        while (it.next()) |device_ptr| {
            device_ptr.*.deinit();
            self.allocator.destroy(device_ptr.*);
        }
        self.devices.deinit();
        self.object_context.deinit();
    }

    // ========================================================================
    // EVENT SOURCING - Translate Bluetooth events to Device operations
    // ========================================================================

    /// Create a new device from a discovery event
    fn createDeviceFromDiscoveryEvent(self: *DeviceRegistry, event: primitives.DeviceDiscovered, timestamp: i64) !*Device {
        const device = try self.allocator.create(Device);
        device.* = try Device.init(&self.object_context, event.address, timestamp);

        // Set initial data from event
        device.data.address_type = event.address_type;
        device.data.device_type = event.device_type;
        device.data.class_of_device = event.class_of_device;
        device.data.appearance = event.appearance;
        device.data.tx_power = event.tx_power;
        device.data.event_count = 1;

        // Duplicate allocated data from event
        if (event.name) |name| {
            device.data.name = try self.allocator.dupe(u8, name);
        }

        if (event.manufacturer_data) |data| {
            device.data.manufacturer_data = try self.allocator.dupe(u8, data);
        }

        if (event.service_uuids) |uuids| {
            device.data.service_uuids = try self.allocator.dupe(primitives.UUID, uuids);
        }

        // Add initial RSSI sample
        if (event.rssi != -127) { // -127 is "unknown"
            try device.data.rssi_history.append(self.allocator, Device.RssiSample{
                .timestamp = timestamp,
                .rssi = event.rssi,
            });
        }

        return device;
    }

    /// Apply a discovery event to an existing device
    fn applyDiscoveryEventToDevice(device: *Device, event: primitives.DeviceDiscovered, timestamp: i64) !void {
        device.setLastSeen(timestamp);
        device.data.event_count += 1;

        // Update name if provided and different
        if (event.name) |new_name| {
            if (device.data.name == null or !std.mem.eql(u8, device.data.name.?, new_name)) {
                try device.setName(new_name);
            }
        }

        // Update device type if more specific
        if (event.device_type != .unknown) {
            device.setDeviceType(event.device_type);
        }

        // Update appearance if provided
        if (event.appearance) |app| {
            device.setAppearance(app);
        }

        // Update tx_power if provided
        if (event.tx_power) |power| {
            device.setTxPower(power);
        }

        // Add RSSI sample (with notification)
        if (event.rssi != -127) {
            try device.addRssiSample(timestamp, event.rssi);
        }

        // Update manufacturer data if provided and different
        if (event.manufacturer_data) |new_data| {
            if (device.data.manufacturer_data == null or !std.mem.eql(u8, device.data.manufacturer_data.?, new_data)) {
                try device.setManufacturerData(new_data);
            }
        }

        // Update service UUIDs if provided
        if (event.service_uuids) |new_uuids| {
            try device.setServiceUuids(new_uuids);
        }
    }

    /// Apply a connection state change event
    fn applyConnectionEventToDevice(device: *Device, event: primitives.DeviceConnected, timestamp: i64) void {
        device.setConnectionState(event.state);
        device.setLastSeen(timestamp);
        device.data.event_count += 1;

        if (event.state == .connected) {
            device.setLastConnected(timestamp);
        }
    }

    /// Apply a services discovered event
    fn applyServicesDiscoveredToDevice(device: *Device, services: []const primitives.GattService, timestamp: i64) !void {
        try device.setGattServices(services);
        device.setLastSeen(timestamp);
        device.data.event_count += 1;
    }

    /// Apply a characteristic changed event (notification/indication)
    fn applyCharacteristicChangedToDevice(
        device: *Device,
        service_uuid: primitives.UUID,
        char_uuid: primitives.UUID,
        value: []const u8,
        timestamp: i64,
    ) !void {
        try device.addCharacteristicUpdate(service_uuid, char_uuid, value, timestamp);
        device.setLastSeen(timestamp);
        device.data.event_count += 1;

        // Also update the characteristic value in GATT services if found
        const allocator = device.context.allocator;
        for (device.data.gatt_services.items) |*svc| {
            if (svc.uuid.eql(service_uuid)) {
                for (svc.characteristics) |*char| {
                    if (char.uuid.eql(char_uuid)) {
                        if (char.value) |old_val| {
                            allocator.free(old_val);
                        }
                        char.value = try allocator.dupe(u8, value);
                        break;
                    }
                }
                break;
            }
        }
    }

    /// Process an event and update the device registry
    pub fn applyEvent(self: *DeviceRegistry, event: primitives.Event) !void {
        const timestamp = std.time.milliTimestamp();

        switch (event) {
            .device_discovered => |disc| {
                const entry = try self.devices.getOrPut(disc.address);

                if (entry.found_existing) {
                    // Update existing device
                    try applyDiscoveryEventToDevice(entry.value_ptr.*, disc, timestamp);
                } else {
                    // Create new device and add to registry
                    entry.value_ptr.* = try self.createDeviceFromDiscoveryEvent(disc, timestamp);
                    // Notify observers AFTER device is in registry
                    self.object_context.notifyInserted(entry.value_ptr.*.object_id);
                }
            },

            .device_connected => |conn| {
                if (self.devices.get(conn.address)) |device| {
                    applyConnectionEventToDevice(device, conn, timestamp);
                }
            },

            .services_discovered => |svc_disc| {
                if (self.devices.get(svc_disc.address)) |device| {
                    try applyServicesDiscoveredToDevice(device, svc_disc.services, timestamp);
                }
            },

            .characteristic_changed => |char_change| {
                if (self.devices.get(char_change.address)) |device| {
                    try applyCharacteristicChangedToDevice(
                        device,
                        char_change.service_uuid,
                        char_change.characteristic_uuid,
                        char_change.value,
                        timestamp,
                    );
                }
            },

            .adapter_state_changed, .hci_event, .provider_error => {
                // These events don't affect device state
            },
        }
    }

    /// Get a device by address
    pub fn getDevice(self: *DeviceRegistry, address: primitives.Address) ?*Device {
        return self.devices.get(address);
    }

    /// Get all devices as a slice (caller must free)
    pub fn getAllDevices(self: *DeviceRegistry, allocator: std.mem.Allocator) ![]*Device {
        const devices = try allocator.alloc(*Device, self.devices.count());
        var it = self.devices.valueIterator();
        var i: usize = 0;
        while (it.next()) |device_ptr| : (i += 1) {
            devices[i] = device_ptr.*;
        }
        return devices;
    }

    /// Get devices sorted by last seen (most recent first)
    pub fn getDevicesSortedByLastSeen(self: *DeviceRegistry, allocator: std.mem.Allocator) ![]*Device {
        const devices = try self.getAllDevices(allocator);

        const SortContext = struct {
            pub fn lessThan(_: @This(), a: *Device, b: *Device) bool {
                return a.data.last_seen > b.data.last_seen; // Descending order
            }
        };

        std.mem.sort(*Device, devices, SortContext{}, SortContext.lessThan);
        return devices;
    }

    /// Get count of all devices
    pub fn getDeviceCount(self: *const DeviceRegistry) usize {
        return self.devices.count();
    }

    /// Get count of connected devices
    pub fn getConnectedDeviceCount(self: *const DeviceRegistry) usize {
        var count: usize = 0;
        var it = self.devices.valueIterator();
        while (it.next()) |device| {
            if (device.isConnected()) {
                count += 1;
            }
        }
        return count;
    }
};
