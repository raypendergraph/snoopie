const std = @import("std");
const c = @import("root").c;

/// Load CSS styles from embedded content (compile-time only)
pub fn loadComponentCss(comptime css_content: []const u8) void {
    const provider = c.gtk_css_provider_new();

    c.gtk_css_provider_load_from_data(
        provider,
        css_content.ptr,
        css_content.len,
    );

    c.gtk_style_context_add_provider_for_display(
        c.gdk_display_get_default(),
        @ptrCast(provider),
        c.GTK_STYLE_PROVIDER_PRIORITY_APPLICATION,
    );

    c.g_object_unref(provider);
}
