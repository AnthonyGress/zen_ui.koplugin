local shared = require("modules/filebrowser/patches/home/widgets/featured_common")
local _ = require("gettext")

return {
    id = "featured",
    label = _("Featured book"),
    size = shared.SIZE,
    preferredHeight = function(ctx)
        return shared.preferred_height(ctx.width, ctx.module_cfg, ctx.data)
    end,
    build = function(ctx)
        return shared.build(ctx)
    end,
}
