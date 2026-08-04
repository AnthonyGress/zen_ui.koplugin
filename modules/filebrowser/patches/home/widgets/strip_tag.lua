local shared = require("modules/filebrowser/patches/home/widgets/strip_common")
local _ = require("gettext")

return {
    id = "strip_tag",
    label = _("Tag strip widget"),
    size = shared.SIZE,
    build = function(ctx)
        return shared.build_strip(ctx, "tag")
    end,
}
