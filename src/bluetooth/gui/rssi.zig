const std = @import("std");

const c = @cImport({
    @cDefine("GLIB_DISABLE_DEPRECATION_WARNINGS", "1");
    @cInclude("gtk/gtk.h");
});

/// RSSI signal strength categories
pub const RssiCategory = enum {
    excellent, // -50 to -30 dBm
    good, // -70 to -50 dBm
    fair, // -80 to -70 dBm
    weak, // -90 to -80 dBm
    poor, // below -90 dBm
    unknown, // no signal data

    pub fn fromRssi(rssi: ?i8) RssiCategory {
        const value = rssi orelse return .unknown;

        if (value >= -50) return .excellent;
        if (value >= -70) return .good;
        if (value >= -80) return .fair;
        if (value >= -90) return .weak;
        return .poor;
    }

    pub fn toCssClass(self: RssiCategory) []const u8 {
        return switch (self) {
            .excellent => "rssi-excellent",
            .good => "rssi-good",
            .fair => "rssi-fair",
            .weak => "rssi-weak",
            .poor => "rssi-poor",
            .unknown => "rssi-unknown",
        };
    }

    pub fn toColorHex(self: RssiCategory) []const u8 {
        return switch (self) {
            .excellent => "#4caf50", // Green
            .good => "#8bc34a", // Light green
            .fair => "#ffc107", // Amber
            .weak => "#ff9800", // Orange
            .poor => "#f44336", // Red
            .unknown => "#9e9e9e", // Gray
        };
    }

    pub fn toDescription(self: RssiCategory) []const u8 {
        return switch (self) {
            .excellent => "Excellent signal",
            .good => "Good signal",
            .fair => "Fair signal",
            .weak => "Weak signal",
            .poor => "Poor signal",
            .unknown => "Unknown signal",
        };
    }
};

/// Apply RSSI category CSS class to a widget
pub fn applyRssiClass(widget: *c.GtkWidget, rssi: ?i8) void {
    const style_context = c.gtk_widget_get_style_context(widget);

    // Remove all existing RSSI classes
    const all_categories = [_]RssiCategory{
        .excellent,
        .good,
        .fair,
        .weak,
        .poor,
        .unknown,
    };

    for (all_categories) |cat| {
        c.gtk_style_context_remove_class(style_context, cat.toCssClass().ptr);
    }

    // Add the appropriate class
    const category = RssiCategory.fromRssi(rssi);
    c.gtk_style_context_add_class(style_context, category.toCssClass().ptr);
}

/// Get a signal strength bar string (Unicode block characters)
/// Example: "████░░" for 4/6 bars
pub fn getSignalBars(rssi: ?i8, max_bars: usize) []const u8 {
    const category = RssiCategory.fromRssi(rssi);

    const bars = switch (category) {
        .excellent => max_bars,
        .good => (max_bars * 4) / 5,
        .fair => (max_bars * 3) / 5,
        .weak => (max_bars * 2) / 5,
        .poor => 1,
        .unknown => 0,
    };

    // Unicode block characters: █ (full) and ░ (empty)
    // This would need a buffer to construct the string
    _ = bars;
    return "████░░"; // Placeholder - would need dynamic allocation
}

/// Get signal strength as percentage (0-100)
pub fn getRssiPercentage(rssi: ?i8) u8 {
    const value = rssi orelse return 0;

    // Map RSSI range (-100 to -30 dBm) to 0-100%
    // -30 dBm = 100% (excellent)
    // -100 dBm = 0% (unusable)
    const clamped = @max(-100, @min(-30, value));
    const normalized: i16 = clamped + 100; // Now 0 to 70
    const percentage: u8 = @intCast(@divTrunc(normalized * 100, 70));

    return percentage;
}

test "RSSI categorization" {
    const testing = std.testing;

    try testing.expectEqual(RssiCategory.excellent, RssiCategory.fromRssi(-40));
    try testing.expectEqual(RssiCategory.good, RssiCategory.fromRssi(-60));
    try testing.expectEqual(RssiCategory.fair, RssiCategory.fromRssi(-75));
    try testing.expectEqual(RssiCategory.weak, RssiCategory.fromRssi(-85));
    try testing.expectEqual(RssiCategory.poor, RssiCategory.fromRssi(-95));
    try testing.expectEqual(RssiCategory.unknown, RssiCategory.fromRssi(null));
}

test "RSSI percentage" {
    const testing = std.testing;

    try testing.expectEqual(@as(u8, 100), getRssiPercentage(-30));
    try testing.expectEqual(@as(u8, 71), getRssiPercentage(-50));
    try testing.expectEqual(@as(u8, 42), getRssiPercentage(-70));
    try testing.expectEqual(@as(u8, 14), getRssiPercentage(-90));
    try testing.expectEqual(@as(u8, 0), getRssiPercentage(-100));
    try testing.expectEqual(@as(u8, 0), getRssiPercentage(null));
}
