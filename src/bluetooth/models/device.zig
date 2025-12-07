const std = @import("std");
const primitives = @import("../primitives.zig");

/// Device model - the aggregate root for a Bluetooth device
/// This is a projection/view built from events over time
pub const Device = struct {
    /// Primary key - Bluetooth MAC address
    address: primitives.Address,

    /// Device metadata
    name: ?[]const u8 = null,
    address_type: primitives.DeviceDiscovered.AddressType = .public,
    device_type: primitives.DeviceType = .unknown,
    class_of_device: ?u24 = null, // Classic Bluetooth only
    appearance: ?u16 = null, // BLE appearance value

    /// Connection state
    connection_state: primitives.ConnectionState = .disconnected,

    /// Signal strength history (most recent first)
    rssi_history: std.ArrayList(RssiSample),

    /// Transmit power
    tx_power: ?i8 = null,

    /// Manufacturer-specific data
    manufacturer_data: ?[]const u8 = null,

    /// Advertised service UUIDs
    service_uuids: ?[]const primitives.UUID = null,

    /// Discovered GATT services (populated after connection)
    gatt_services: std.ArrayList(primitives.GattService),

    /// Characteristic notifications/indications received
    characteristic_updates: std.ArrayList(CharacteristicUpdate),

    /// Timestamps
    first_seen: i64, // Unix timestamp in milliseconds
    last_seen: i64, // Unix timestamp in milliseconds
    last_connected: ?i64 = null, // Unix timestamp when last connected

    /// Event sequence for this device (for replay/debugging)
    event_count: usize = 0,

    pub const RssiSample = struct {
        timestamp: i64, // Unix timestamp in milliseconds
        rssi: i8, // Signal strength in dBm
    };

    pub const CharacteristicUpdate = struct {
        timestamp: i64,
        service_uuid: primitives.UUID,
        characteristic_uuid: primitives.UUID,
        value: []const u8,

        pub fn deinit(self: *CharacteristicUpdate, allocator: std.mem.Allocator) void {
            allocator.free(self.value);
        }
    };

    /// Create a new device from a discovery event
    pub fn fromDiscoveryEvent(allocator: std.mem.Allocator, event: primitives.DeviceDiscovered, timestamp: i64) !Device {
        var device = Device{
            .address = event.address,
            .address_type = event.address_type,
            .device_type = event.device_type,
            .class_of_device = event.class_of_device,
            .appearance = event.appearance,
            .tx_power = event.tx_power,
            .rssi_history = std.ArrayList(RssiSample){},
            .gatt_services = std.ArrayList(primitives.GattService){},
            .characteristic_updates = std.ArrayList(CharacteristicUpdate){},
            .first_seen = timestamp,
            .last_seen = timestamp,
            .event_count = 1,
            .name = null,
            .manufacturer_data = null,
            .service_uuids = null,
        };

        // Duplicate allocated data from event
        if (event.name) |name| {
            device.name = try allocator.dupe(u8, name);
        }

        if (event.manufacturer_data) |data| {
            device.manufacturer_data = try allocator.dupe(u8, data);
        }

        if (event.service_uuids) |uuids| {
            device.service_uuids = try allocator.dupe(primitives.UUID, uuids);
        }

        // Add initial RSSI sample
        if (event.rssi != -127) { // -127 is "unknown"
            try device.rssi_history.append(allocator, RssiSample{
                .timestamp = timestamp,
                .rssi = event.rssi,
            });
        }

        return device;
    }

    /// Apply a discovery event to update the device state
    pub fn applyDiscoveryEvent(self: *Device, allocator: std.mem.Allocator, event: primitives.DeviceDiscovered, timestamp: i64) !void {
        self.last_seen = timestamp;
        self.event_count += 1;

        // Update name if provided and different
        if (event.name) |new_name| {
            if (self.name == null or !std.mem.eql(u8, self.name.?, new_name)) {
                if (self.name) |old_name| {
                    allocator.free(old_name);
                }
                self.name = try allocator.dupe(u8, new_name);
            }
        }

        // Update device type if more specific
        if (event.device_type != .unknown) {
            self.device_type = event.device_type;
        }

        // Update appearance if provided
        if (event.appearance) |app| {
            self.appearance = app;
        }

        // Update tx_power if provided
        if (event.tx_power) |power| {
            self.tx_power = power;
        }

        // Add RSSI sample
        if (event.rssi != -127) {
            try self.rssi_history.append(allocator, RssiSample{
                .timestamp = timestamp,
                .rssi = event.rssi,
            });

            // Keep only last 100 samples to prevent unbounded growth
            if (self.rssi_history.items.len > 100) {
                _ = self.rssi_history.orderedRemove(0);
            }
        }

        // Update manufacturer data if provided and different
        if (event.manufacturer_data) |new_data| {
            if (self.manufacturer_data == null or !std.mem.eql(u8, self.manufacturer_data.?, new_data)) {
                if (self.manufacturer_data) |old_data| {
                    allocator.free(old_data);
                }
                self.manufacturer_data = try allocator.dupe(u8, new_data);
            }
        }

        // Update service UUIDs if provided
        if (event.service_uuids) |new_uuids| {
            if (self.service_uuids) |old_uuids| {
                allocator.free(old_uuids);
            }
            self.service_uuids = try allocator.dupe(primitives.UUID, new_uuids);
        }
    }

    /// Apply a connection state change event
    pub fn applyConnectionEvent(self: *Device, event: primitives.DeviceConnected, timestamp: i64) void {
        self.connection_state = event.state;
        self.last_seen = timestamp;
        self.event_count += 1;

        if (event.state == .connected) {
            self.last_connected = timestamp;
        }
    }

    /// Apply a services discovered event
    pub fn applyServicesDiscovered(self: *Device, allocator: std.mem.Allocator, services: []primitives.GattService, timestamp: i64) !void {
        self.last_seen = timestamp;
        self.event_count += 1;

        // Clear existing services
        for (self.gatt_services.items) |*svc| {
            svc.deinit(allocator);
        }
        self.gatt_services.clearRetainingCapacity();

        // Deep copy services (they contain allocated data)
        for (services) |svc| {
            var new_service = primitives.GattService{
                .uuid = svc.uuid,
                .primary = svc.primary,
                .characteristics = try allocator.alloc(primitives.GattCharacteristic, svc.characteristics.len),
            };

            for (svc.characteristics, 0..) |char, i| {
                var new_char = primitives.GattCharacteristic{
                    .uuid = char.uuid,
                    .properties = char.properties,
                    .value = null,
                    .descriptors = try allocator.alloc(primitives.GattDescriptor, char.descriptors.len),
                };

                if (char.value) |val| {
                    new_char.value = try allocator.dupe(u8, val);
                }

                for (char.descriptors, 0..) |desc, j| {
                    new_char.descriptors[j] = primitives.GattDescriptor{
                        .uuid = desc.uuid,
                        .value = if (desc.value) |val| try allocator.dupe(u8, val) else null,
                    };
                }

                new_service.characteristics[i] = new_char;
            }

            try self.gatt_services.append(allocator, new_service);
        }
    }

    /// Apply a characteristic changed event (notification/indication)
    pub fn applyCharacteristicChanged(
        self: *Device,
        allocator: std.mem.Allocator,
        service_uuid: primitives.UUID,
        char_uuid: primitives.UUID,
        value: []const u8,
        timestamp: i64,
    ) !void {
        self.last_seen = timestamp;
        self.event_count += 1;

        // Add to update history
        try self.characteristic_updates.append(allocator, CharacteristicUpdate{
            .timestamp = timestamp,
            .service_uuid = service_uuid,
            .characteristic_uuid = char_uuid,
            .value = try allocator.dupe(u8, value),
        });

        // Keep only last 1000 updates to prevent unbounded growth
        if (self.characteristic_updates.items.len > 1000) {
            var old = self.characteristic_updates.orderedRemove(0);
            old.deinit(allocator);
        }

        // Also update the characteristic value in GATT services if found
        for (self.gatt_services.items) |*svc| {
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

    /// Get the most recent RSSI value
    pub fn getCurrentRssi(self: *const Device) ?i8 {
        if (self.rssi_history.items.len == 0) return null;
        return self.rssi_history.items[self.rssi_history.items.len - 1].rssi;
    }

    /// Get average RSSI over last N samples
    pub fn getAverageRssi(self: *const Device, sample_count: usize) ?i8 {
        if (self.rssi_history.items.len == 0) return null;

        const count = @min(sample_count, self.rssi_history.items.len);
        const start_idx = self.rssi_history.items.len - count;

        var sum: i32 = 0;
        for (self.rssi_history.items[start_idx..]) |sample| {
            sum += sample.rssi;
        }

        return @intCast(@divTrunc(sum, @as(i32, @intCast(count))));
    }

    /// Check if device is currently connected
    pub fn isConnected(self: *const Device) bool {
        return self.connection_state == .connected;
    }

    /// Get human-readable device name or address
    pub fn getDisplayName(self: *const Device, allocator: std.mem.Allocator) ![]const u8 {
        if (self.name) |name| {
            return try allocator.dupe(u8, name);
        }
        return std.fmt.allocPrint(allocator, "{any}", .{self.address});
    }

    pub fn deinit(self: *Device, allocator: std.mem.Allocator) void {
        if (self.name) |name| allocator.free(name);
        if (self.manufacturer_data) |data| allocator.free(data);
        if (self.service_uuids) |uuids| allocator.free(uuids);

        self.rssi_history.deinit(allocator);

        for (self.gatt_services.items) |*svc| {
            svc.deinit(allocator);
        }
        self.gatt_services.deinit(allocator);

        for (self.characteristic_updates.items) |*update| {
            update.deinit(allocator);
        }
        self.characteristic_updates.deinit(allocator);
    }
};
