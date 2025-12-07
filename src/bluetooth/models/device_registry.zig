const std = @import("std");
const primitives = @import("../primitives.zig");
const Device = @import("device.zig").Device;
const core = @import("../../core.zig");
const ObjectContext = core.data.ObjectContext;
const ObjectID = core.data.ObjectID;

/// Device registry - maintains the current state of all known devices
/// This is the event-sourced "view" that gets updated as events arrive
pub const DeviceRegistry = struct {
    allocator: std.mem.Allocator,
    devices: std.AutoHashMap(primitives.Address, Device),
    object_context: ObjectContext,

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

    pub fn init(allocator: std.mem.Allocator) DeviceRegistry {
        return DeviceRegistry{
            .allocator = allocator,
            .devices = std.AutoHashMap(primitives.Address, Device).init(allocator),
            .object_context = ObjectContext.init(allocator),
        };
    }

    pub fn deinit(self: *DeviceRegistry) void {
        var it = self.devices.valueIterator();
        while (it.next()) |device| {
            device.deinit(self.allocator);
        }
        self.devices.deinit();
        self.object_context.deinit();
    }

    /// Create an ObjectID for a device given its address
    fn createObjectID(self: *DeviceRegistry, address: primitives.Address) !ObjectID {
        const id_str = try std.fmt.allocPrint(self.allocator, "{any}", .{address});
        return ObjectID{
            .type_name = "Device",
            .unique_id = id_str,
        };
    }

    /// Process an event and update the device registry
    pub fn applyEvent(self: *DeviceRegistry, event: primitives.Event) !void {
        const timestamp = std.time.milliTimestamp();

        switch (event) {
            .device_discovered => |disc| {
                const entry = try self.devices.getOrPut(disc.address);
                const object_id = try self.createObjectID(disc.address);
                defer self.allocator.free(object_id.unique_id);

                if (entry.found_existing) {
                    // Update existing device
                    try entry.value_ptr.applyDiscoveryEvent(self.allocator, disc, timestamp);
                    self.object_context.notifyUpdated(object_id, null);
                } else {
                    // Create new device
                    entry.value_ptr.* = try Device.fromDiscoveryEvent(self.allocator, disc, timestamp);
                    self.object_context.notifyInserted(object_id);
                }
            },

            .device_connected => |conn| {
                if (self.devices.getPtr(conn.address)) |device| {
                    device.applyConnectionEvent(conn, timestamp);

                    const object_id = try self.createObjectID(conn.address);
                    defer self.allocator.free(object_id.unique_id);
                    self.object_context.notifyUpdated(object_id, "connection_state");
                }
                // If device not in registry, we could create it here or ignore
            },

            .services_discovered => |svc_disc| {
                if (self.devices.getPtr(svc_disc.address)) |device| {
                    try device.applyServicesDiscovered(self.allocator, svc_disc.services, timestamp);

                    const object_id = try self.createObjectID(svc_disc.address);
                    defer self.allocator.free(object_id.unique_id);
                    self.object_context.notifyUpdated(object_id, "gatt_services");
                }
            },

            .characteristic_changed => |char_change| {
                if (self.devices.getPtr(char_change.address)) |device| {
                    try device.applyCharacteristicChanged(
                        self.allocator,
                        char_change.service_uuid,
                        char_change.characteristic_uuid,
                        char_change.value,
                        timestamp,
                    );

                    const object_id = try self.createObjectID(char_change.address);
                    defer self.allocator.free(object_id.unique_id);
                    self.object_context.notifyUpdated(object_id, "characteristic_updates");
                }
            },

            .adapter_state_changed, .hci_event, .provider_error => {
                // These events don't affect device state
            },
        }
    }

    /// Get a device by address
    pub fn getDevice(self: *DeviceRegistry, address: primitives.Address) ?*Device {
        return self.devices.getPtr(address);
    }

    /// Get all devices as a slice (caller must free)
    pub fn getAllDevices(self: *DeviceRegistry, allocator: std.mem.Allocator) ![]Device {
        const devices = try allocator.alloc(Device, self.devices.count());
        var it = self.devices.valueIterator();
        var i: usize = 0;
        while (it.next()) |device| : (i += 1) {
            devices[i] = device.*;
        }
        return devices;
    }

    /// Get devices sorted by last seen (most recent first)
    pub fn getDevicesSortedByLastSeen(self: *DeviceRegistry, allocator: std.mem.Allocator) ![]Device {
        const devices = try self.getAllDevices(allocator);

        const SortContext = struct {
            pub fn lessThan(_: @This(), a: Device, b: Device) bool {
                return a.last_seen > b.last_seen; // Descending order
            }
        };

        std.mem.sort(Device, devices, SortContext{}, SortContext.lessThan);
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
