const std = @import("std");

/// Bluetooth device address (BD_ADDR)
pub const Address = struct {
    bytes: [6]u8,

    pub const ZERO = Address{ .bytes = [_]u8{0} ** 6 };

    /// Format address as XX:XX:XX:XX:XX:XX
    pub fn format(
        self: Address,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;
        try writer.print("{X:0>2}:{X:0>2}:{X:0>2}:{X:0>2}:{X:0>2}:{X:0>2}", .{
            self.bytes[5],
            self.bytes[4],
            self.bytes[3],
            self.bytes[2],
            self.bytes[1],
            self.bytes[0],
        });
    }

    /// Parse address from string "XX:XX:XX:XX:XX:XX"
    pub fn parse(str: []const u8) !Address {
        if (str.len != 17) return error.InvalidAddress;

        var addr = Address{ .bytes = undefined };
        var i: usize = 0;
        while (i < 6) : (i += 1) {
            const offset = i * 3;
            addr.bytes[5 - i] = try std.fmt.parseInt(u8, str[offset .. offset + 2], 16);
            if (i < 5 and str[offset + 2] != ':') return error.InvalidAddress;
        }
        return addr;
    }

    pub fn eql(self: Address, other: Address) bool {
        return std.mem.eql(u8, &self.bytes, &other.bytes);
    }
};

/// Bluetooth UUID (16-bit, 32-bit, or 128-bit)
pub const UUID = union(enum) {
    uuid16: u16,
    uuid32: u32,
    uuid128: [16]u8,

    pub fn format(
        self: UUID,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;
        switch (self) {
            .uuid16 => |v| try writer.print("{X:0>4}", .{v}),
            .uuid32 => |v| try writer.print("{X:0>8}", .{v}),
            .uuid128 => |bytes| {
                try writer.print("{X:0>2}{X:0>2}{X:0>2}{X:0>2}-{X:0>2}{X:0>2}-{X:0>2}{X:0>2}-{X:0>2}{X:0>2}-{X:0>2}{X:0>2}{X:0>2}{X:0>2}{X:0>2}{X:0>2}", .{
                    bytes[0],  bytes[1],  bytes[2],  bytes[3],
                    bytes[4],  bytes[5],  bytes[6],  bytes[7],
                    bytes[8],  bytes[9],  bytes[10], bytes[11],
                    bytes[12], bytes[13], bytes[14], bytes[15],
                });
            },
        }
    }

    pub fn eql(self: UUID, other: UUID) bool {
        if (std.meta.activeTag(self) != std.meta.activeTag(other)) return false;
        return switch (self) {
            .uuid16 => |v| v == other.uuid16,
            .uuid32 => |v| v == other.uuid32,
            .uuid128 => |bytes| std.mem.eql(u8, &bytes, &other.uuid128),
        };
    }
};

/// Device type
pub const DeviceType = enum {
    unknown,
    classic, // BR/EDR
    le, // Low Energy
    dual, // Dual mode
};

/// Adapter state
pub const AdapterState = enum {
    unknown,
    powered_off,
    powered_on,
    discovering,
};

/// Discovered device information
pub const DeviceDiscovered = struct {
    address: Address,
    address_type: AddressType,
    name: ?[]const u8,
    rssi: i8,
    device_type: DeviceType,
    class_of_device: ?u24, // Classic only
    manufacturer_data: ?[]const u8,
    service_uuids: ?[]const UUID,
    tx_power: ?i8,
    appearance: ?u16,

    pub const AddressType = enum {
        public,
        random,
        public_identity,
        random_identity,
    };

    pub fn deinit(self: *DeviceDiscovered, allocator: std.mem.Allocator) void {
        if (self.name) |name| allocator.free(name);
        if (self.manufacturer_data) |data| allocator.free(data);
        if (self.service_uuids) |uuids| allocator.free(uuids);
    }
};

/// Connection state
pub const ConnectionState = enum {
    disconnected,
    connecting,
    connected,
    disconnecting,
};

/// Device connection event
pub const DeviceConnected = struct {
    address: Address,
    state: ConnectionState,
};

/// GATT characteristic properties
pub const GattProperties = packed struct {
    broadcast: bool = false,
    read: bool = false,
    write_without_response: bool = false,
    write: bool = false,
    notify: bool = false,
    indicate: bool = false,
    authenticated_signed_writes: bool = false,
    extended_properties: bool = false,
};

/// GATT service
pub const GattService = struct {
    uuid: UUID,
    primary: bool,
    characteristics: []GattCharacteristic,

    pub fn deinit(self: *GattService, allocator: std.mem.Allocator) void {
        for (self.characteristics) |*char| {
            char.deinit(allocator);
        }
        allocator.free(self.characteristics);
    }
};

/// GATT characteristic
pub const GattCharacteristic = struct {
    uuid: UUID,
    properties: GattProperties,
    value: ?[]const u8,
    descriptors: []GattDescriptor,

    pub fn deinit(self: *GattCharacteristic, allocator: std.mem.Allocator) void {
        if (self.value) |val| allocator.free(val);
        for (self.descriptors) |*desc| {
            desc.deinit(allocator);
        }
        allocator.free(self.descriptors);
    }
};

/// GATT descriptor
pub const GattDescriptor = struct {
    uuid: UUID,
    value: ?[]const u8,

    pub fn deinit(self: *GattDescriptor, allocator: std.mem.Allocator) void {
        if (self.value) |val| allocator.free(val);
    }
};

/// Adapter information
pub const AdapterInfo = struct {
    address: Address,
    name: []const u8,
    powered: bool,
    discoverable: bool,
    pairable: bool,
    discovering: bool,

    pub fn deinit(self: *AdapterInfo, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
    }
};

/// HCI packet types (for lower-level providers)
pub const HciPacketType = enum(u8) {
    command = 0x01,
    acl_data = 0x02,
    sco_data = 0x03,
    event = 0x04,
    iso_data = 0x05,
};

/// HCI event codes
pub const HciEventCode = enum(u8) {
    inquiry_complete = 0x01,
    inquiry_result = 0x02,
    connection_complete = 0x03,
    connection_request = 0x04,
    disconnection_complete = 0x05,
    authentication_complete = 0x06,
    remote_name_request_complete = 0x07,
    encryption_change = 0x08,
    command_complete = 0x0E,
    command_status = 0x0F,
    hardware_error = 0x10,
    role_change = 0x12,
    number_of_completed_packets = 0x13,
    mode_change = 0x14,
    le_meta_event = 0x3E,
    _,
};

/// LE meta event subtypes
pub const LeMetaEventType = enum(u8) {
    connection_complete = 0x01,
    advertising_report = 0x02,
    connection_update_complete = 0x03,
    read_remote_features_complete = 0x04,
    long_term_key_request = 0x05,
    remote_connection_parameter_request = 0x06,
    data_length_change = 0x07,
    read_local_p256_public_key_complete = 0x08,
    generate_dhkey_complete = 0x09,
    enhanced_connection_complete = 0x0A,
    directed_advertising_report = 0x0B,
    extended_advertising_report = 0x0D,
    _,
};

test "Address format" {
    const addr = Address{ .bytes = .{ 0x78, 0x56, 0x34, 0x12, 0xAB, 0xCD } };
    const str = try std.fmt.allocPrint(std.testing.allocator, "{}", .{addr});
    defer std.testing.allocator.free(str);
    try std.testing.expectEqualStrings("CD:AB:12:34:56:78", str);
}

test "Address parse" {
    const addr = try Address.parse("CD:AB:12:34:56:78");
    try std.testing.expectEqual([_]u8{ 0x78, 0x56, 0x34, 0x12, 0xAB, 0xCD }, addr.bytes);
}

/// Provider events that can be emitted
pub const Event = union(enum) {
    /// A new device was discovered during scanning
    device_discovered: DeviceDiscovered,

    /// Device connection state changed
    device_connected: DeviceConnected,

    /// Adapter state changed
    adapter_state_changed: AdapterStateChanged,

    /// GATT services discovered for a device
    services_discovered: ServicesDiscovered,

    /// GATT characteristic value changed (notification/indication)
    characteristic_changed: CharacteristicChanged,

    /// Raw HCI event (for low-level providers)
    hci_event: HciEvent,

    /// Provider error
    provider_error: ProviderError,

    pub const AdapterStateChanged = struct {
        state: AdapterState,
    };

    pub const ServicesDiscovered = struct {
        address: Address,
        services: []GattService,
    };

    pub const CharacteristicChanged = struct {
        address: Address,
        service_uuid: UUID,
        characteristic_uuid: UUID,
        value: []const u8,
    };

    pub const HciEvent = struct {
        packet_type: HciPacketType,
        data: []const u8,
    };

    pub const ProviderError = struct {
        message: []const u8,
        code: ?i32,
    };

    pub fn deinit(self: *Event, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .device_discovered => |*d| d.deinit(allocator),
            .adapter_state_changed => {},
            .device_connected => {},
            .services_discovered => |*s| {
                for (s.services) |*svc| {
                    svc.deinit(allocator);
                }
                allocator.free(s.services);
            },
            .characteristic_changed => |*c| allocator.free(c.value),
            .hci_event => |*h| allocator.free(h.data),
            .provider_error => |*e| allocator.free(e.message),
        }
    }
};

/// Event callback function type
pub const EventCallback = *const fn (event: Event, user_data: ?*anyopaque) void;
