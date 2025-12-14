const std = @import("std");
const primitives = @import("../primitives.zig");
const core = @import("core");
const ObjectContext = core.data.ObjectContext;
const ObjectID = core.data.ObjectID;

/// Observable version of Device - demonstrates manual implementation
/// Read data via the public `data` field, mutate via explicit methods
pub const ObservableDevice = struct {
    // Private observation machinery
    context: *ObjectContext,
    object_id: ObjectID,

    // Public data - read-only access (use setters to mutate)
    data: Data,

    pub const RssiSample = struct {
        timestamp: i64,
        rssi: i8,
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

    /// The actual device data - public for read access
    pub const Data = struct {
        /// Primary key - Bluetooth MAC address
        address: primitives.Address,

        /// Human-readable device name (may be null if not advertised)
        name: ?[]const u8,

        /// Address type (public, random static, etc.)
        address_type: primitives.DeviceDiscovered.AddressType,

        /// Device type (classic, BLE, dual-mode, unknown)
        device_type: primitives.DeviceType,

        /// Class of Device for classic Bluetooth
        class_of_device: ?u24,

        /// BLE appearance value (e.g., phone, watch, keyboard)
        appearance: ?u16,

        /// Current connection state
        connection_state: primitives.ConnectionState,

        /// Signal strength history (most recent last)
        rssi_history: std.ArrayList(RssiSample),

        /// Transmit power level in dBm
        tx_power: ?i8,

        /// Manufacturer-specific advertising data
        manufacturer_data: ?[]const u8,

        /// List of advertised service UUIDs
        service_uuids: ?[]const primitives.UUID,

        /// Discovered GATT services (populated after connection)
        gatt_services: std.ArrayList(primitives.GattService),

        /// History of characteristic notifications/indications
        characteristic_updates: std.ArrayList(CharacteristicUpdate),

        /// Timestamp when device was first discovered
        first_seen: i64,

        /// Timestamp of most recent advertisement or event
        last_seen: i64,

        /// Timestamp when device was last connected
        last_connected: ?i64,

        /// Number of events processed for this device
        event_count: usize,
    };

    /// Initialize an observable device - requires a context
    pub fn init(context: *ObjectContext, address: primitives.Address, timestamp: i64) !ObservableDevice {
        const id_str = try std.fmt.allocPrint(context.allocator, "{any}", .{address});

        const device = ObservableDevice{
            .context = context,
            .object_id = ObjectID{
                .type_name = "Device",
                .unique_id = id_str,
            },
            .data = Data{
                .address = address,
                .name = null,
                .address_type = .public,
                .device_type = .unknown,
                .class_of_device = null,
                .appearance = null,
                .connection_state = .disconnected,
                .rssi_history = std.ArrayList(RssiSample).init(context.allocator),
                .tx_power = null,
                .manufacturer_data = null,
                .service_uuids = null,
                .gatt_services = std.ArrayList(primitives.GattService).init(context.allocator),
                .characteristic_updates = std.ArrayList(CharacteristicUpdate).init(context.allocator),
                .first_seen = timestamp,
                .last_seen = timestamp,
                .last_connected = null,
                .event_count = 0,
            },
        };

        // Register with context
        context.notifyInserted(device.object_id);

        return device;
    }

    pub fn deinit(self: *ObservableDevice) void {
        const allocator = self.context.allocator;

        self.context.notifyRemoved(self.object_id);

        if (self.data.name) |n| allocator.free(n);
        if (self.data.manufacturer_data) |d| allocator.free(d);
        if (self.data.service_uuids) |u| allocator.free(u);

        self.data.rssi_history.deinit();

        for (self.data.gatt_services.items) |*svc| {
            svc.deinit(allocator);
        }
        self.data.gatt_services.deinit();

        for (self.data.characteristic_updates.items) |*update| {
            update.deinit(allocator);
        }
        self.data.characteristic_updates.deinit();

        allocator.free(self.object_id.unique_id);
    }

    // ========================================================================
    // MUTATION METHODS - Update fields with automatic notifications
    // ========================================================================

    pub fn setName(self: *ObservableDevice, value: ?[]const u8) !void {
        const allocator = self.context.allocator;

        if (self.data.name) |old_name| {
            allocator.free(old_name);
        }

        if (value) |new_name| {
            self.data.name = try allocator.dupe(u8, new_name);
        } else {
            self.data.name = null;
        }

        self.context.notifyUpdated(self.object_id, "name");
    }

    pub fn setDeviceType(self: *ObservableDevice, value: primitives.DeviceType) void {
        self.data.device_type = value;
        self.context.notifyUpdated(self.object_id, "device_type");
    }

    pub fn setAppearance(self: *ObservableDevice, value: ?u16) void {
        self.data.appearance = value;
        self.context.notifyUpdated(self.object_id, "appearance");
    }

    pub fn setConnectionState(self: *ObservableDevice, value: primitives.ConnectionState) void {
        self.data.connection_state = value;
        self.context.notifyUpdated(self.object_id, "connection_state");
    }

    pub fn setTxPower(self: *ObservableDevice, value: ?i8) void {
        self.data.tx_power = value;
        self.context.notifyUpdated(self.object_id, "tx_power");
    }

    pub fn setManufacturerData(self: *ObservableDevice, value: ?[]const u8) !void {
        const allocator = self.context.allocator;

        if (self.data.manufacturer_data) |old_data| {
            allocator.free(old_data);
        }

        if (value) |new_data| {
            self.data.manufacturer_data = try allocator.dupe(u8, new_data);
        } else {
            self.data.manufacturer_data = null;
        }

        self.context.notifyUpdated(self.object_id, "manufacturer_data");
    }

    pub fn setServiceUuids(self: *ObservableDevice, value: ?[]const primitives.UUID) !void {
        const allocator = self.context.allocator;

        if (self.data.service_uuids) |old_uuids| {
            allocator.free(old_uuids);
        }

        if (value) |new_uuids| {
            self.data.service_uuids = try allocator.dupe(primitives.UUID, new_uuids);
        } else {
            self.data.service_uuids = null;
        }

        self.context.notifyUpdated(self.object_id, "service_uuids");
    }

    pub fn setLastSeen(self: *ObservableDevice, value: i64) void {
        self.data.last_seen = value;
        self.context.notifyUpdated(self.object_id, "last_seen");
    }

    pub fn setLastConnected(self: *ObservableDevice, value: ?i64) void {
        self.data.last_connected = value;
        self.context.notifyUpdated(self.object_id, "last_connected");
    }

    // ========================================================================
    // COLLECTION MUTATORS - Modify collections with notifications
    // ========================================================================

    pub fn addRssiSample(self: *ObservableDevice, timestamp: i64, rssi: i8) !void {
        try self.data.rssi_history.append(self.context.allocator, RssiSample{
            .timestamp = timestamp,
            .rssi = rssi,
        });

        if (self.data.rssi_history.items.len > 100) {
            _ = self.data.rssi_history.orderedRemove(0);
        }

        self.context.notifyUpdated(self.object_id, "rssi_history");
    }

    pub fn setGattServices(self: *ObservableDevice, services: []const primitives.GattService) !void {
        const allocator = self.context.allocator;

        // Clear existing services
        for (self.data.gatt_services.items) |*svc| {
            svc.deinit(allocator);
        }
        self.data.gatt_services.clearRetainingCapacity();

        // Deep copy new services
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

            try self.data.gatt_services.append(allocator, new_service);
        }

        self.context.notifyUpdated(self.object_id, "gatt_services");
    }

    pub fn addCharacteristicUpdate(
        self: *ObservableDevice,
        service_uuid: primitives.UUID,
        char_uuid: primitives.UUID,
        value: []const u8,
        timestamp: i64,
    ) !void {
        const allocator = self.context.allocator;

        try self.data.characteristic_updates.append(allocator, CharacteristicUpdate{
            .timestamp = timestamp,
            .service_uuid = service_uuid,
            .characteristic_uuid = char_uuid,
            .value = try allocator.dupe(u8, value),
        });

        if (self.data.characteristic_updates.items.len > 1000) {
            var old = self.data.characteristic_updates.orderedRemove(0);
            old.deinit(allocator);
        }

        self.context.notifyUpdated(self.object_id, "characteristic_updates");
    }

    // ========================================================================
    // UTILITY METHODS
    // ========================================================================

    pub fn getCurrentRssi(self: *const ObservableDevice) ?i8 {
        if (self.data.rssi_history.items.len == 0) return null;
        return self.data.rssi_history.items[self.data.rssi_history.items.len - 1].rssi;
    }

    pub fn getAverageRssi(self: *const ObservableDevice, sample_count: usize) ?i8 {
        if (self.data.rssi_history.items.len == 0) return null;

        const count = @min(sample_count, self.data.rssi_history.items.len);
        const start_idx = self.data.rssi_history.items.len - count;

        var sum: i32 = 0;
        for (self.data.rssi_history.items[start_idx..]) |sample| {
            sum += sample.rssi;
        }

        return @intCast(@divTrunc(sum, @as(i32, @intCast(count))));
    }

    pub fn isConnected(self: *const ObservableDevice) bool {
        return self.data.connection_state == .connected;
    }

    pub fn getDisplayName(self: *const ObservableDevice, allocator: std.mem.Allocator) ![]const u8 {
        if (self.data.name) |n| {
            return try allocator.dupe(u8, n);
        }
        return std.fmt.allocPrint(allocator, "{any}", .{self.data.address});
    }
};
