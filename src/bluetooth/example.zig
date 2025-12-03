const std = @import("std");
const primitives = @import("primitives.zig");
const providers = @import("providers.zig");
const DBusProvider = @import("dbus_provider.zig").DBusProvider;

/// Example showing how to use the provider system
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create a DBus provider
    var dbus_provider = DBusProvider{
        .allocator = undefined,
        .event_queue = undefined,
    };

    // Initialize it
    try dbus_provider.init(allocator);
    defer dbus_provider.deinit();

    // Convert to provider interface
    const provider = dbus_provider.asProvider();

    // Set up event callback
    provider.setEventCallback(eventCallback, null);

    // Start the provider
    try provider.start();
    defer provider.stop() catch {};

    // Get adapter info
    const adapter_info = try provider.getAdapterInfo();
    std.debug.print("Adapter: {} ({})\n", .{ adapter_info.address, adapter_info.name });
    defer {
        var info = adapter_info;
        info.deinit(allocator);
    }

    // Start discovery
    try provider.startDiscovery();

    // Let it run for a bit
    std.debug.print("Scanning for devices for 5 seconds...\n", .{});
    std.time.sleep(5 * std.time.ns_per_s);

    // Stop discovery
    try provider.stopDiscovery();

    std.debug.print("Done!\n", .{});
}

fn eventCallback(event: providers.Event, user_data: ?*anyopaque) void {
    _ = user_data;

    switch (event) {
        .device_discovered => |device| {
            std.debug.print("Device discovered: {}", .{device.address});
            if (device.name) |name| {
                std.debug.print(" ({})", .{name});
            }
            std.debug.print(" RSSI: {}dBm\n", .{device.rssi});
        },
        .device_connected => |conn| {
            std.debug.print("Device {} state: {}\n", .{ conn.address, conn.state });
        },
        .adapter_state_changed => |state| {
            std.debug.print("Adapter state: {}\n", .{state.state});
        },
        .services_discovered => |services| {
            std.debug.print("Services discovered for {}: {} services\n", .{
                services.address,
                services.services.len,
            });
        },
        .characteristic_changed => |char| {
            std.debug.print("Characteristic {} changed: {} bytes\n", .{
                char.characteristic_uuid,
                char.value.len,
            });
        },
        .hci_event => |hci| {
            std.debug.print("HCI event: type={} len={}\n", .{
                hci.packet_type,
                hci.data.len,
            });
        },
        .provider_error => |err| {
            std.debug.print("Provider error: {s}", .{err.message});
            if (err.code) |code| {
                std.debug.print(" (code: {})", .{code});
            }
            std.debug.print("\n", .{});
        },
    }
}
