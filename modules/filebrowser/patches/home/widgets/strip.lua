local shared = require("modules/filebrowser/patches/home/widgets/strip_common")
local _ = require("gettext")

return {
    id = "strip",
    label = _("Book strip"),
    size = shared.SIZE,
    build = function(ctx)
        return shared.build_strip(ctx)
    end,
}
