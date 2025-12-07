const std = @import("std");
const ObjectContext = @import("object_context.zig").ObjectContext;
const ObjectID = @import("object_context.zig").ObjectID;

/// Generate an editor wrapper for a model type that emits change notifications
/// Usage:
///   const DeviceEditor = Editor(Device, "address");
///   var editor = DeviceEditor.init(&context, &device);
///   editor.set("name", new_value); // Automatically emits change event
///
/// Note: For now, this is a simple wrapper. We can add comptime-generated
/// setters later if needed, but that adds complexity.
pub fn Editor(comptime T: type, comptime id_field: []const u8) type {
    return struct {
        const Self = @This();

        context: *ObjectContext,
        object: *T,
        object_id: ObjectID,

        /// Initialize an editor for the given object
        pub fn init(context: *ObjectContext, object: *T, type_name: []const u8) !Self {
            // Get the ID field value and format it as a string
            const id_value = @field(object.*, id_field);
            const id_str = try std.fmt.allocPrint(
                context.allocator,
                "{any}",
                .{id_value},
            );

            return Self{
                .context = context,
                .object = object,
                .object_id = ObjectID{
                    .type_name = type_name,
                    .unique_id = id_str,
                },
            };
        }

        pub fn deinit(self: *Self) void {
            self.context.allocator.free(self.object_id.unique_id);
        }

        /// Set a field value and emit a change notification
        /// Usage: editor.set("name", new_value)
        pub fn set(self: *Self, comptime field_name: []const u8, value: anytype) void {
            @field(self.object.*, field_name) = value;
            self.context.notifyUpdated(self.object_id, field_name);
        }

        /// Notify that the entire object changed (useful after multiple updates)
        pub fn notifyChanged(self: *Self) void {
            self.context.notifyUpdated(self.object_id, null);
        }
    };
}
