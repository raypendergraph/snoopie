const std = @import("std");

const c = @cImport({
    @cDefine("GLIB_DISABLE_DEPRECATION_WARNINGS", "1");
    @cInclude("gtk/gtk.h");
});

/// Generic list view wrapper for GTK ListBox
/// This is the VIEW component - just handles GTK widget operations
///
/// Usage:
/// ```zig
/// const MyListView = ListView(MyItem);
/// var view = try MyListView.create(allocator);
/// ```
pub fn ListView(comptime ItemType: type) type {
    return struct {
        const Self = @This();

        allocator: std.mem.Allocator,
        scroll_window: *c.GtkScrolledWindow,
        list_box: *c.GtkListBox,

        pub fn create(allocator: std.mem.Allocator) !*Self {
            const self = try allocator.create(Self);
            errdefer allocator.destroy(self);

            // Create scrolled window
            const scroll_window = c.gtk_scrolled_window_new();
            c.gtk_scrolled_window_set_policy(
                @ptrCast(scroll_window),
                c.GTK_POLICY_NEVER,
                c.GTK_POLICY_AUTOMATIC,
            );
            c.gtk_widget_set_vexpand(scroll_window, 1);

            const list_box = c.gtk_list_box_new();
            c.gtk_list_box_set_selection_mode(@ptrCast(list_box), c.GTK_SELECTION_SINGLE);

            c.gtk_scrolled_window_set_child(@ptrCast(scroll_window), list_box);

            self.* = Self{
                .allocator = allocator,
                .scroll_window = @ptrCast(scroll_window),
                .list_box = @ptrCast(list_box),
            };

            return self;
        }

        pub fn destroy(self: *Self) void {
            // GTK will destroy the widgets when the list_box is destroyed
            // We just need to clean up our wrapper
            self.allocator.destroy(self);
        }

        /// Get the GTK widget (the scrolled window)
        pub fn getWidget(self: *Self) *c.GtkWidget {
            return @ptrCast(self.scroll_window);
        }

        /// Insert item at specific index
        pub fn insertItem(self: *Self, index: usize, item: *ItemType) !void {
            c.gtk_list_box_insert(self.list_box, item.getWidget(), @intCast(index));
        }

        /// Append item to end
        pub fn appendItem(self: *Self, item: *ItemType) !void {
            c.gtk_list_box_append(self.list_box, item.getWidget());
        }

        /// Remove item at index (caller must destroy the item)
        pub fn removeItem(self: *Self, item: *ItemType) void {
            c.gtk_list_box_remove(self.list_box, item.getWidget());
            item.destroy(self.allocator);
        }

        /// Clear all items from the list
        pub fn clear(self: *Self) void {
            // Remove all children from the list box
            c.gtk_list_box_remove_all(self.list_box);
        }

        /// Set CSS class on the list box
        pub fn setCssClass(self: *Self, class_name: [*:0]const u8) void {
            c.gtk_widget_add_css_class(@ptrCast(self.list_box), class_name);
        }
    };
}
