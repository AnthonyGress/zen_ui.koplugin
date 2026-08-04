local shared = require("modules/filebrowser/patches/home/widgets/featured_common")
local _ = require("gettext")

return {
    id = "featured_recent",
    label = _("Recently read featured widget"),
    size = shared.SIZE,
    build = function(ctx)
        return shared.build(ctx, "recently_read")
    end,
}
