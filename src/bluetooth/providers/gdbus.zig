const std = @import("std");
pub const c = @cImport({
    @cInclude("gio/gio.h");
    @cInclude("glib.h");
});

/// GDBus connection wrapper
pub const Connection = struct {
    connection: *c.GDBusConnection,

    pub fn systemBus() !Connection {
        var err: ?*c.GError = null;
        const conn = c.g_bus_get_sync(c.G_BUS_TYPE_SYSTEM, null, &err);
        if (err != null) {
            defer c.g_error_free(err);
            return error.BusConnectionFailed;
        }
        if (conn == null) return error.BusConnectionFailed;

        return Connection{ .connection = conn.? };
    }

    pub fn close(self: *Connection) void {
        c.g_object_unref(self.connection);
    }

    /// Subscribe to DBus signals
    pub fn subscribeSignal(
        self: Connection,
        sender: ?[*:0]const u8,
        interface_name: ?[*:0]const u8,
        member: ?[*:0]const u8,
        object_path: ?[*:0]const u8,
        callback: c.GDBusSignalCallback,
        user_data: ?*anyopaque,
    ) u32 {
        return c.g_dbus_connection_signal_subscribe(
            self.connection,
            sender,
            interface_name,
            member,
            object_path,
            null, // arg0 filter
            c.G_DBUS_SIGNAL_FLAGS_NONE,
            callback,
            user_data,
            null, // user_data_free_func
        );
    }

    pub fn unsubscribe(self: Connection, subscription_id: u32) void {
        c.g_dbus_connection_signal_unsubscribe(self.connection, subscription_id);
    }

    /// Call a DBus method
    pub fn call(
        self: Connection,
        bus_name: [*:0]const u8,
        object_path: [*:0]const u8,
        interface_name: [*:0]const u8,
        method_name: [*:0]const u8,
        parameters: ?*c.GVariant,
        timeout_ms: i32,
    ) !*c.GVariant {
        var err: ?*c.GError = null;
        const result = c.g_dbus_connection_call_sync(
            self.connection,
            bus_name,
            object_path,
            interface_name,
            method_name,
            parameters,
            null, // reply_type
            c.G_DBUS_CALL_FLAGS_NONE,
            timeout_ms,
            null, // cancellable
            &err,
        );

        if (err != null) {
            defer c.g_error_free(err);
            return error.DbusCallFailed;
        }

        return result orelse error.DbusCallFailed;
    }

    /// Get a property value
    pub fn getProperty(
        self: Connection,
        bus_name: [*:0]const u8,
        object_path: [*:0]const u8,
        interface_name: [*:0]const u8,
        property_name: [*:0]const u8,
    ) !*c.GVariant {
        var err: ?*c.GError = null;
        const result = c.g_dbus_connection_call_sync(
            self.connection,
            bus_name,
            object_path,
            "org.freedesktop.DBus.Properties",
            "Get",
            c.g_variant_new("(ss)", interface_name, property_name),
            null,
            c.G_DBUS_CALL_FLAGS_NONE,
            -1,
            null,
            &err,
        );

        if (err != null) {
            defer c.g_error_free(err);
            return error.PropertyGetFailed;
        }

        return result orelse error.PropertyGetFailed;
    }
};

/// DBus signal information
pub const Signal = struct {
    sender: []const u8,
    object_path: []const u8,
    interface_name: []const u8,
    signal_name: []const u8,
    parameters: *c.GVariant,

    pub fn fromGDBus(
        sender: [*:0]const u8,
        object_path: [*:0]const u8,
        interface_name: [*:0]const u8,
        signal_name: [*:0]const u8,
        parameters: *c.GVariant,
    ) Signal {
        return Signal{
            .sender = std.mem.span(sender),
            .object_path = std.mem.span(object_path),
            .interface_name = std.mem.span(interface_name),
            .signal_name = std.mem.span(signal_name),
            .parameters = parameters,
        };
    }
};

/// Helper to extract string from GVariant
pub fn variantGetString(variant: *c.GVariant) ?[]const u8 {
    const str = c.g_variant_get_string(variant, null);
    if (str == null) return null;
    return std.mem.span(str);
}

/// Helper to extract int from GVariant
pub fn variantGetInt(variant: *c.GVariant) i32 {
    return c.g_variant_get_int32(variant);
}

/// Helper to extract bool from GVariant
pub fn variantGetBool(variant: *c.GVariant) bool {
    return c.g_variant_get_boolean(variant) != 0;
}
