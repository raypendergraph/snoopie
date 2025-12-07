const std = @import("std");
const primitives = @import("primitives.zig");
const AsyncQueue = @import("../core/async.zig").AsyncQueue;

/// Provider interface - all Bluetooth providers must implement this
pub const Provider = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        /// Initialize the provider
        init: *const fn (ptr: *anyopaque, allocator: std.mem.Allocator) anyerror!void,

        /// Clean up provider resources
        deinit: *const fn (ptr: *anyopaque) void,

        /// Start the provider (begin processing events)
        start: *const fn (ptr: *anyopaque) anyerror!void,

        /// Stop the provider
        stop: *const fn (ptr: *anyopaque) anyerror!void,

        /// Get the event queue for receiving events
        getEventQueue: *const fn (ptr: *anyopaque) *AsyncQueue(primitives.Event),

        /// Get adapter information
        getAdapterInfo: *const fn (ptr: *anyopaque) anyerror!primitives.AdapterInfo,

        /// Start device discovery
        startDiscovery: *const fn (ptr: *anyopaque) anyerror!void,

        /// Stop device discovery
        stopDiscovery: *const fn (ptr: *anyopaque) anyerror!void,

        /// Connect to a device
        connect: *const fn (ptr: *anyopaque, address: primitives.Address) anyerror!void,

        /// Disconnect from a device
        disconnect: *const fn (ptr: *anyopaque, address: primitives.Address) anyerror!void,

        /// Discover GATT services on a connected device
        discoverServices: *const fn (ptr: *anyopaque, address: primitives.Address) anyerror!void,

        /// Read a GATT characteristic
        readCharacteristic: *const fn (
            ptr: *anyopaque,
            address: primitives.Address,
            service_uuid: primitives.UUID,
            char_uuid: primitives.UUID,
        ) anyerror![]const u8,

        /// Write a GATT characteristic
        writeCharacteristic: *const fn (
            ptr: *anyopaque,
            address: primitives.Address,
            service_uuid: primitives.UUID,
            char_uuid: primitives.UUID,
            value: []const u8,
        ) anyerror!void,

        /// Enable notifications for a characteristic
        enableNotifications: *const fn (
            ptr: *anyopaque,
            address: primitives.Address,
            service_uuid: primitives.UUID,
            char_uuid: primitives.UUID,
        ) anyerror!void,

        /// Disable notifications for a characteristic
        disableNotifications: *const fn (
            ptr: *anyopaque,
            address: primitives.Address,
            service_uuid: primitives.UUID,
            char_uuid: primitives.UUID,
        ) anyerror!void,
    };

    // Wrapper methods that call through vtable

    pub fn init(self: Provider, allocator: std.mem.Allocator) !void {
        return self.vtable.init(self.ptr, allocator);
    }

    pub fn deinit(self: Provider) void {
        return self.vtable.deinit(self.ptr);
    }

    pub fn start(self: Provider) !void {
        return self.vtable.start(self.ptr);
    }

    pub fn stop(self: Provider) !void {
        return self.vtable.stop(self.ptr);
    }

    pub fn getEventQueue(self: Provider) *AsyncQueue(primitives.Event) {
        return self.vtable.getEventQueue(self.ptr);
    }

    pub fn getAdapterInfo(self: Provider) !primitives.AdapterInfo {
        return self.vtable.getAdapterInfo(self.ptr);
    }

    pub fn startDiscovery(self: Provider) !void {
        return self.vtable.startDiscovery(self.ptr);
    }

    pub fn stopDiscovery(self: Provider) !void {
        return self.vtable.stopDiscovery(self.ptr);
    }

    pub fn connect(self: Provider, address: primitives.Address) !void {
        return self.vtable.connect(self.ptr, address);
    }

    pub fn disconnect(self: Provider, address: primitives.Address) !void {
        return self.vtable.disconnect(self.ptr, address);
    }

    pub fn discoverServices(self: Provider, address: primitives.Address) !void {
        return self.vtable.discoverServices(self.ptr, address);
    }

    pub fn readCharacteristic(
        self: Provider,
        address: primitives.Address,
        service_uuid: primitives.UUID,
        char_uuid: primitives.UUID,
    ) ![]const u8 {
        return self.vtable.readCharacteristic(self.ptr, address, service_uuid, char_uuid);
    }

    pub fn writeCharacteristic(
        self: Provider,
        address: primitives.Address,
        service_uuid: primitives.UUID,
        char_uuid: primitives.UUID,
        value: []const u8,
    ) !void {
        return self.vtable.writeCharacteristic(self.ptr, address, service_uuid, char_uuid, value);
    }

    pub fn enableNotifications(
        self: Provider,
        address: primitives.Address,
        service_uuid: primitives.UUID,
        char_uuid: primitives.UUID,
    ) !void {
        return self.vtable.enableNotifications(self.ptr, address, service_uuid, char_uuid);
    }

    pub fn disableNotifications(
        self: Provider,
        address: primitives.Address,
        service_uuid: primitives.UUID,
        char_uuid: primitives.UUID,
    ) !void {
        return self.vtable.disableNotifications(self.ptr, address, service_uuid, char_uuid);
    }
};

/// Helper to create a provider from a concrete implementation
pub fn createProvider(comptime T: type, impl: *T) Provider {
    const s = struct {
        fn initFn(ptr: *anyopaque, allocator: std.mem.Allocator) !void {
            const self: *T = @ptrCast(@alignCast(ptr));
            return self.init(allocator);
        }

        fn deinitFn(ptr: *anyopaque) void {
            const self: *T = @ptrCast(@alignCast(ptr));
            return self.deinit();
        }

        fn startFn(ptr: *anyopaque) !void {
            const self: *T = @ptrCast(@alignCast(ptr));
            return self.start();
        }

        fn stopFn(ptr: *anyopaque) !void {
            const self: *T = @ptrCast(@alignCast(ptr));
            return self.stop();
        }

        fn getEventQueueFn(ptr: *anyopaque) *AsyncQueue(primitives.Event) {
            const self: *T = @ptrCast(@alignCast(ptr));
            return self.getEventQueue();
        }

        fn getAdapterInfoFn(ptr: *anyopaque) !primitives.AdapterInfo {
            const self: *T = @ptrCast(@alignCast(ptr));
            return self.getAdapterInfo();
        }

        fn startDiscoveryFn(ptr: *anyopaque) !void {
            const self: *T = @ptrCast(@alignCast(ptr));
            return self.startDiscovery();
        }

        fn stopDiscoveryFn(ptr: *anyopaque) !void {
            const self: *T = @ptrCast(@alignCast(ptr));
            return self.stopDiscovery();
        }

        fn connectFn(ptr: *anyopaque, address: primitives.Address) !void {
            const self: *T = @ptrCast(@alignCast(ptr));
            return self.connect(address);
        }

        fn disconnectFn(ptr: *anyopaque, address: primitives.Address) !void {
            const self: *T = @ptrCast(@alignCast(ptr));
            return self.disconnect(address);
        }

        fn discoverServicesFn(ptr: *anyopaque, address: primitives.Address) !void {
            const self: *T = @ptrCast(@alignCast(ptr));
            return self.discoverServices(address);
        }

        fn readCharacteristicFn(
            ptr: *anyopaque,
            address: primitives.Address,
            service_uuid: primitives.UUID,
            char_uuid: primitives.UUID,
        ) ![]const u8 {
            const self: *T = @ptrCast(@alignCast(ptr));
            return self.readCharacteristic(address, service_uuid, char_uuid);
        }

        fn writeCharacteristicFn(
            ptr: *anyopaque,
            address: primitives.Address,
            service_uuid: primitives.UUID,
            char_uuid: primitives.UUID,
            value: []const u8,
        ) !void {
            const self: *T = @ptrCast(@alignCast(ptr));
            return self.writeCharacteristic(address, service_uuid, char_uuid, value);
        }

        fn enableNotificationsFn(
            ptr: *anyopaque,
            address: primitives.Address,
            service_uuid: primitives.UUID,
            char_uuid: primitives.UUID,
        ) !void {
            const self: *T = @ptrCast(@alignCast(ptr));
            return self.enableNotifications(address, service_uuid, char_uuid);
        }

        fn disableNotificationsFn(
            ptr: *anyopaque,
            address: primitives.Address,
            service_uuid: primitives.UUID,
            char_uuid: primitives.UUID,
        ) !void {
            const self: *T = @ptrCast(@alignCast(ptr));
            return self.disableNotifications(address, service_uuid, char_uuid);
        }

        const vtable = Provider.VTable{
            .init = initFn,
            .deinit = deinitFn,
            .start = startFn,
            .stop = stopFn,
            .getEventQueue = getEventQueueFn,
            .getAdapterInfo = getAdapterInfoFn,
            .startDiscovery = startDiscoveryFn,
            .stopDiscovery = stopDiscoveryFn,
            .connect = connectFn,
            .disconnect = disconnectFn,
            .discoverServices = discoverServicesFn,
            .readCharacteristic = readCharacteristicFn,
            .writeCharacteristic = writeCharacteristicFn,
            .enableNotifications = enableNotificationsFn,
            .disableNotifications = disableNotificationsFn,
        };
    };

    return Provider{
        .ptr = impl,
        .vtable = &s.vtable,
    };
}
