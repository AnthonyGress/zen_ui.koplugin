local shared = require("modules/filebrowser/patches/home/widgets/strip_common")
local _ = require("gettext")

return {
    id = "strip_recent",
    label = _("Recently read strip widget"),
    size = shared.SIZE,
    build = function(ctx)
        return shared.build_strip(ctx, "recently_read")
    end,
}
