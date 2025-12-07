const std = @import("std");
const Emitter = @import("../events.zig").Emitter;

/// Unique identifier for an object in the context
pub const ObjectID = struct {
    type_name: []const u8,
    unique_id: []const u8,

    /// Format as "TypeName/unique_id"
    pub fn format(
        self: ObjectID,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;
        try writer.print("{s}/{s}", .{ self.type_name, self.unique_id });
    }

    /// Parse from "TypeName/unique_id" format
    pub fn parse(allocator: std.mem.Allocator, str: []const u8) !ObjectID {
        const sep_idx = std.mem.indexOf(u8, str, "/") orelse return error.InvalidObjectID;
        return ObjectID{
            .type_name = try allocator.dupe(u8, str[0..sep_idx]),
            .unique_id = try allocator.dupe(u8, str[sep_idx + 1 ..]),
        };
    }

    pub fn deinit(self: *ObjectID, allocator: std.mem.Allocator) void {
        allocator.free(self.type_name);
        allocator.free(self.unique_id);
    }

    pub fn eql(self: ObjectID, other: ObjectID) bool {
        return std.mem.eql(u8, self.type_name, other.type_name) and
            std.mem.eql(u8, self.unique_id, other.unique_id);
    }

    /// Create a hash for use in HashMaps
    pub fn hash(self: ObjectID) u64 {
        var hasher = std.hash.Wyhash.init(0);
        hasher.update(self.type_name);
        hasher.update(self.unique_id);
        return hasher.final();
    }
};

/// Type of change that occurred to an object
pub const ChangeType = enum {
    inserted,
    updated,
    deleted,
};

/// Represents a change to an object in the context
pub const ObjectChange = struct {
    object_id: ObjectID,
    change_type: ChangeType,
    property_name: ?[]const u8 = null, // null = entire object changed

    pub fn format(
        self: ObjectChange,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;
        try writer.print("{s}({any}", .{ @tagName(self.change_type), self.object_id });
        if (self.property_name) |prop| {
            try writer.print(".{s}", .{prop});
        }
        try writer.writeAll(")");
    }
};

/// Central context for managing objects and their change notifications
/// Similar to Core Data's NSManagedObjectContext
pub const ObjectContext = struct {
    allocator: std.mem.Allocator,
    change_emitter: Emitter(ObjectChange),

    // Store type-erased object pointers keyed by ObjectID
    // Note: We don't own these objects, just track them
    objects: std.StringHashMap(*anyopaque),

    pub fn init(allocator: std.mem.Allocator) ObjectContext {
        return ObjectContext{
            .allocator = allocator,
            .change_emitter = Emitter(ObjectChange).init(allocator),
            .objects = std.StringHashMap(*anyopaque).init(allocator),
        };
    }

    pub fn deinit(self: *ObjectContext) void {
        // Free all ObjectID keys
        var it = self.objects.keyIterator();
        while (it.next()) |key| {
            self.allocator.free(key.*);
        }
        self.objects.deinit();
        self.change_emitter.deinit();
    }

    /// Register an object in the context
    pub fn registerObject(self: *ObjectContext, object_id: ObjectID, object: anytype) !void {
        const key = try std.fmt.allocPrint(self.allocator, "{any}", .{object_id});
        try self.objects.put(key, object);
    }

    /// Unregister an object from the context
    pub fn unregisterObject(self: *ObjectContext, object_id: ObjectID) !void {
        const key = try std.fmt.allocPrint(self.allocator, "{any}", .{object_id});
        defer self.allocator.free(key);

        if (self.objects.fetchRemove(key)) |entry| {
            self.allocator.free(entry.key);
        }
    }

    /// Notify observers that an object was inserted
    pub fn notifyInserted(self: *ObjectContext, object_id: ObjectID) void {
        self.change_emitter.emit(ObjectChange{
            .object_id = object_id,
            .change_type = .inserted,
        });
    }

    /// Notify observers that an object was updated
    pub fn notifyUpdated(self: *ObjectContext, object_id: ObjectID, property_name: ?[]const u8) void {
        self.change_emitter.emit(ObjectChange{
            .object_id = object_id,
            .change_type = .updated,
            .property_name = property_name,
        });
    }

    /// Notify observers that an object was deleted
    pub fn notifyDeleted(self: *ObjectContext, object_id: ObjectID) void {
        self.change_emitter.emit(ObjectChange{
            .object_id = object_id,
            .change_type = .deleted,
        });
    }

    /// Add an observer for object changes
    pub fn addObserver(
        self: *ObjectContext,
        context: anytype,
        comptime callback: fn (ctx: @TypeOf(context), change: ObjectChange) void,
    ) !void {
        try self.change_emitter.addObserver(context, callback);
    }

    /// Remove an observer
    pub fn removeObserver(self: *ObjectContext, context: *const anyopaque) void {
        self.change_emitter.removeObserver(context);
    }
};
