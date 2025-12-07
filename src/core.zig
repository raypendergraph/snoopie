const std = @import("std");

/// Async utilities (queues, synchronization, etc.)
pub const async = @import("core/async.zig");

/// GUI utilities (GTK helpers, etc.)
pub const gui = @import("core/gui.zig");

/// Collection utilities (sorted lists, etc.)
pub const collections = @import("core/collections.zig");

/// Event system (emitters, observers, etc.)
pub const events = @import("core/events.zig");

/// Data management (object context, editors, etc.)
pub const data = @import("core/data.zig");
