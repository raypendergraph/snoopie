const std = @import("std");
const bluetooth = @import("bluetooth.zig");
const BluetoothController = bluetooth.controllers.BluetoothController;
const bt_callbacks = @import("bluetooth/controllers/root.zig");

// C bindings - exported publicly so other modules can access via @import("root").c
pub const c = @cImport({
    @cDefine("GLIB_DISABLE_DEPRECATION_WARNINGS", "1");
    @cInclude("gtk/gtk.h");
    @cInclude("cairo.h");
});

const AppData = struct {
    allocator: std.mem.Allocator,
    bt_controller: *bluetooth.controllers.RootController,
};

var app_data: AppData = undefined;

fn onActivate(app: *c.GtkApplication, user_data: ?*anyopaque) callconv(.c) void {
    _ = user_data;

    const allocator = app_data.allocator;

    // Create main window
    const window = c.gtk_application_window_new(app);
    c.gtk_window_set_title(@ptrCast(window), "Snoopie - Bluetooth Research Tool");
    c.gtk_window_set_default_size(@ptrCast(window), 800, 600);

    // Create main vertical box
    const main_box = c.gtk_box_new(c.GTK_ORIENTATION_VERTICAL, 0);

    // Create header bar with scan button
    const header = c.gtk_header_bar_new();
    const scan_button = c.gtk_button_new_with_label("Start Scan");
    c.gtk_header_bar_pack_start(@ptrCast(header), scan_button);
    c.gtk_window_set_titlebar(@ptrCast(window), header);

    // Initialize Bluetooth controller
    const bt_controller = bluetooth.controllers.RootController.init(allocator) catch |err| {
        std.debug.print("Failed to initialize Bluetooth controller: {any}\n", .{err});
        return;
    };
    app_data.bt_controller = bt_controller;

    // Connect scan button
    bt_controller.setScanButton(scan_button);
    _ = c.g_signal_connect_data(
        scan_button,
        "clicked",
        @ptrCast(&bt_callbacks.onScanClickedCallback),
        bt_controller,
        null,
        0,
    );

    // Add Bluetooth panel to main window
    c.gtk_box_append(@ptrCast(main_box), bt_controller.getWidget());

    // Set main box as window child
    c.gtk_window_set_child(@ptrCast(window), main_box);

    // Set up timer to check for Bluetooth events (every 100ms)
    const timer_id = c.g_timeout_add(
        100,
        bt_callbacks.onCheckBluetoothEventsCallback,
        bt_controller,
    );
    std.debug.print("Timer set up with ID: {}\n", .{timer_id});

    // Show window
    c.gtk_window_present(@ptrCast(window));
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    app_data = AppData{
        .allocator = allocator,
        .bt_controller = undefined, // Will be set in onActivate
    };

    const app = c.gtk_application_new("com.snoopie.bluetooth", c.G_APPLICATION_DEFAULT_FLAGS);
    defer c.g_object_unref(app);

    _ = c.g_signal_connect_data(app, "activate", @ptrCast(&onActivate), null, null, 0);

    const status = c.g_application_run(@ptrCast(app), 0, null);
    if (status != 0) {
        std.debug.print("Application exited with status: {}\n", .{status});
    }
}
