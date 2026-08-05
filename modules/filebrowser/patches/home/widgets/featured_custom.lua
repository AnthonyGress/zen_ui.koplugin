local shared = require("modules/filebrowser/patches/home/widgets/featured_common")
local _ = require("gettext")

return {
    id = "featured_custom",
    label = _("Custom featured widget"),
    size = shared.SIZE,
    build = function(ctx)
        return shared.build(ctx, "custom_featured")
    end,
}
