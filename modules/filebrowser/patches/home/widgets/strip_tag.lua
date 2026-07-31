local shared = require("modules/filebrowser/patches/home/widgets/strip_common")

return {
    id = "strip_tag",
    label = "Tag strip widget",
    size = shared.SIZE,
    build = function(ctx)
        return shared.build_strip(ctx, "tag")
    end,
}
