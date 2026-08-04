local shared = require("modules/filebrowser/patches/home/widgets/featured_common")
local _ = require("gettext")

return {
    id = "featured_tbr",
    label = _("To Be Read featured widget"),
    size = shared.SIZE,
    build = function(ctx)
        return shared.build(ctx, "to_be_read")
    end,
}
