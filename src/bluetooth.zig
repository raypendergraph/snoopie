const std = @import("std");

pub const providers = struct {
    pub const DBus = @import("bluetooth/providers/dbus_provider.zig").DBusProvider;
};

pub const gui = struct {
    pub const MainPanel = @import("bluetooth/gui/main_panel.zig").MainPanel;
    pub const DeviceList = @import("bluetooth/gui/device_list.zig").DeviceList;
    pub const DeviceListItem = @import("bluetooth/gui/device_list_item.zig").DeviceListItem;
};

pub const controllers = struct {
    pub const RootController = @import("bluetooth/controllers/root.zig").RootController;
};

pub const DeviceRegistry = @import("bluetooth/domain/device_registry.zig").DeviceRegistry;
pub const Device = @import("bluetooth/models/device.zig").Device;

const primitives = @import("bluetooth/primitives.zig");
pub const Event = primitives.Event;
pub const Address = primitives.Address;
pub const UUID = primitives.UUID;
pub const DeviceType = primitives.DeviceType;
pub const AdapterState = primitives.AdapterState;
pub const DeviceDiscovered = primitives.DeviceDiscovered;
pub const ConnectionState = primitives.ConnectionState;
pub const DeviceConnected = primitives.DeviceConnected;
pub const GattProperties = primitives.GattProperties;
pub const GattService = primitives.GattService;
pub const GattCharacteristic = primitives.GattCharacteristic;
pub const GattDescriptor = primitives.GattDescriptor;
pub const AdapterInfo = primitives.AdapterInfo;
pub const HciPacketType = primitives.HciPacketType;
pub const HciEventCode = primitives.HciEventCode;
pub const LeMetaEventType = primitives.LeMetaEventType;
pub const EventCallback = primitives.EventCallback;
