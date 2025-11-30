const std = @import("std");
const bt = @import("bluetooth.zig");

const c = @cImport({
    @cDefine("GLIB_DISABLE_DEPRECATION_WARNINGS", "1");
    @cInclude("gtk/gtk.h");
    @cInclude("cairo.h");
});

const App = struct {
    app: *c.GtkApplication,
    window: ?*c.GtkWidget,

    pub fn init() !App {
        return App{
            .app = undefined,
            .window = null,
        };
    }
};

fn onScanClicked(button: *c.GtkButton, user_data: ?*anyopaque) callconv(.C) void {
    _ = button;
    _ = user_data;

    std.debug.print("Scanning for Bluetooth devices...\n", .{});

    // Test Bluetooth binding - get default adapter
    const dev_id = bt.getRoute(null) catch |err| {
        std.debug.print("Error getting Bluetooth adapter: {}\n", .{err});
        return;
    };

    std.debug.print("Found Bluetooth adapter: {}\n", .{dev_id});

    // Get device info
    const info = bt.getDeviceInfo(dev_id) catch |err| {
        std.debug.print("Error getting device info: {}\n", .{err});
        return;
    };

    const addr = bt.addrToString(&info.bdaddr) catch return;
    std.debug.print("Adapter address: {s}\n", .{addr});
}

fn onActivate(app: *c.GtkApplication, user_data: ?*anyopaque) callconv(.C) void {
    _ = user_data;

    // Create main window
    const window = c.gtk_application_window_new(app);
    c.gtk_window_set_title(@ptrCast(window), "Bluetooth Research Tool");
    c.gtk_window_set_default_size(@ptrCast(window), 800, 600);

    // Create header bar
    const header_bar = c.gtk_header_bar_new();
    c.gtk_window_set_titlebar(@ptrCast(window), header_bar);

    // Create main box container
    const main_box = c.gtk_box_new(c.GTK_ORIENTATION_VERTICAL, 10);
    c.gtk_widget_set_margin_start(main_box, 10);
    c.gtk_widget_set_margin_end(main_box, 10);
    c.gtk_widget_set_margin_top(main_box, 10);
    c.gtk_widget_set_margin_bottom(main_box, 10);
    c.gtk_window_set_child(@ptrCast(window), main_box);

    // Create label
    const label = c.gtk_label_new("Bluetooth Research & Hacking Tool");
    c.gtk_box_append(@ptrCast(main_box), label);

    // Create scan button
    const scan_button = c.gtk_button_new_with_label("Scan for Devices");
    _ = c.g_signal_connect_data(
        scan_button,
        "clicked",
        @ptrCast(&onScanClicked),
        null,
        null,
        0,
    );
    c.gtk_box_append(@ptrCast(main_box), scan_button);

    c.gtk_window_present(@ptrCast(window));
}

pub fn main() !void {
    // Initialize GTK (in GTK4, gtk_init returns void)
    c.gtk_init();

    // Create GTK application
    const app = c.gtk_application_new("com.bt.research", c.G_APPLICATION_DEFAULT_FLAGS);
    if (app == null) {
        return error.AppCreationFailed;
    }
    defer c.g_object_unref(app);

    // Connect activate signal
    _ = c.g_signal_connect_data(
        app,
        "activate",
        @ptrCast(&onActivate),
        null,
        null,
        0,
    );

    // Run application
    const exit_status = c.g_application_run(@ptrCast(app), 0, null);
    std.process.exit(@intCast(exit_status));
}
