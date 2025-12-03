# Bluetooth Provider Architecture

This directory contains the provider-based Bluetooth abstraction layer.

## Architecture Overview

```
┌─────────────────────────────────────────────────┐
│                 Application                     │
│            (GTK UI, CLI, etc.)                  │
└────────────────┬────────────────────────────────┘
                 │
                 │ Uses Provider interface
                 ▼
┌─────────────────────────────────────────────────┐
│           providers.zig (Interface)             │
│  - Provider trait/vtable                        │
│  - Event types                                  │
│  - Common operations (scan, connect, GATT)      │
└────────────────┬────────────────────────────────┘
                 │
                 │ Implemented by
                 ▼
┌─────────────────────────────────────────────────┐
│            Concrete Providers                   │
│  ┌───────────────┐  ┌──────────────┐           │
│  │ DBusProvider  │  │HCIProvider   │  ...      │
│  │               │  │              │           │
│  │ (BlueZ/DBus)  │  │(Raw HCI)     │           │
│  └───────┬───────┘  └──────┬───────┘           │
└──────────┼──────────────────┼───────────────────┘
           │                  │
           │ Emits            │ Emits
           ▼                  ▼
┌─────────────────────────────────────────────────┐
│         primitives.zig (Common Types)           │
│  - Address, UUID                                │
│  - DeviceDiscovered, ConnectionState            │
│  - GattService, GattCharacteristic              │
│  - HCI packet types (for low-level providers)   │
└─────────────────────────────────────────────────┘
           │
           │ Queued via
           ▼
┌─────────────────────────────────────────────────┐
│        core/async.zig (AsyncQueue)              │
│  - Thread-safe event queue                      │
│  - Push from provider thread                    │
│  - Pop from application thread                  │
└─────────────────────────────────────────────────┘
```

## Files

### Core Files

- **`primitives.zig`** - Transport-agnostic Bluetooth primitives
  - Address, UUID types with formatting
  - Device discovery events
  - GATT structures (services, characteristics, descriptors)
  - HCI packet types for low-level access
  - Connection states

- **`providers.zig`** - Provider interface and event system
  - `Provider` trait (using vtable pattern)
  - `Event` union for all provider events
  - `EventCallback` for async event delivery
  - `createProvider()` helper for implementing providers

### Providers

- **`dbus_provider.zig`** - BlueZ/DBus provider
  - Communicates with BlueZ daemon via DBus
  - High-level API (already parsed/marshalled)
  - Monitors DBus signals for async events
  - Uses AsyncQueue to deliver events

- **Future providers:**
  - `hci_provider.zig` - Direct HCI socket access
  - `ubertooth_provider.zig` - Ubertooth hardware
  - `sniffer_provider.zig` - Passive sniffing

### Support

- **`../core/async.zig`** - Thread-safe queue
  - Generic `AsyncQueue(T)` type
  - Used for event delivery from provider threads

## Usage Example

See `example.zig` for a complete example. Basic pattern:

```zig
// 1. Create concrete provider
var dbus_provider = DBusProvider{ ... };
try dbus_provider.init(allocator);
defer dbus_provider.deinit();

// 2. Convert to Provider interface
const provider = dbus_provider.asProvider();

// 3. Set event callback
provider.setEventCallback(myCallback, user_data);

// 4. Start provider
try provider.start();
defer provider.stop() catch {};

// 5. Use provider API
try provider.startDiscovery();
const info = try provider.getAdapterInfo();
try provider.connect(device_address);
```

## Event Flow

1. **Provider thread** monitors transport (DBus, HCI socket, USB)
2. When events occur, provider creates `Event` structs
3. Events are pushed to `AsyncQueue`
4. **Worker thread** pops events and calls application callback
5. Application processes event on its own thread

This decouples the provider's I/O from the application's event loop.

## Design Principles

### 1. **Transport Independence**
   - Primitives are independent of transport (DBus vs HCI vs USB)
   - Same `DeviceDiscovered` event from any provider
   - Application code doesn't care about the provider

### 2. **Separation of Concerns**
   - **Primitives**: What Bluetooth data looks like
   - **Providers**: How to get/send Bluetooth data
   - **AsyncQueue**: How to deliver events asynchronously

### 3. **Provider Flexibility**
   - DBus provider: High-level, leverages BlueZ parsing
   - HCI provider: Low-level, full control
   - Ubertooth: Specialized hardware, passive sniffing
   - All implement same interface

### 4. **Memory Management**
   - Events may contain allocated data (strings, arrays)
   - Each event has a `deinit()` method
   - Caller responsible for freeing events
   - Provider uses provided allocator

## Implementing a New Provider

To implement a new provider:

1. Create a struct with these fields:
   ```zig
   pub const MyProvider = struct {
       allocator: std.mem.Allocator,
       event_queue: AsyncQueue(providers.Event),
       callback: ?providers.EventCallback = null,
       callback_user_data: ?*anyopaque = null,
       // ... provider-specific fields
   };
   ```

2. Implement all required methods (see `Provider.VTable` in `providers.zig`)

3. Add `asProvider()` method:
   ```zig
   pub fn asProvider(self: *MyProvider) providers.Provider {
       return providers.createProvider(MyProvider, self);
   }
   ```

4. In your worker thread, push events to the queue:
   ```zig
   const event = providers.Event{
       .device_discovered = .{
           .address = addr,
           .name = name,
           // ...
       },
   };
   self.event_queue.push(event);
   ```

## TODO

### DBusProvider
- [ ] Implement actual DBus communication (using GDBus or libdbus)
- [ ] Monitor BlueZ signals (InterfacesAdded, PropertiesChanged)
- [ ] Parse DBus dictionaries into primitives
- [ ] Handle DBus errors gracefully

### HCIProvider
- [ ] Open HCI socket
- [ ] Parse HCI events into primitives
- [ ] Implement HCI commands (scan, connect, GATT)
- [ ] Handle HCI errors

### UbertoothProvider
- [ ] USB communication with Ubertooth
- [ ] Parse Ubertooth packet format
- [ ] Passive vs active mode support
- [ ] Channel hopping for discovery

### General
- [ ] Add more primitive types as needed
- [ ] Better error handling and recovery
- [ ] Provider capability detection
- [ ] Provider selection/fallback logic
