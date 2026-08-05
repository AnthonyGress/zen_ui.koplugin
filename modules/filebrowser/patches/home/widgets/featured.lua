local shared = require("modules/filebrowser/patches/home/widgets/featured_common")
local _ = require("gettext")

return {
    id = "featured",
    label = _("Featured widget"),
    size = shared.SIZE,
    build = function(ctx)
        return shared.build(ctx)
    end,
}
