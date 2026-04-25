-- Built-in sleep screen presets shipped with Zen UI.
-- icons_dir is resolved at runtime so paths work on any device.

local function get(icons_dir)
    local utils = require("common/utils")
    local zen_svg = utils.resolveIcon(icons_dir, "zen_ui") or (icons_dir .. "zen_ui.svg")
    return {
        {
            name = "Book cover - Black Fill",
            builtin = true,
            screensaver_type = "cover",
            screensaver_img_background = "black",
            screensaver_show_message = false,
            screensaver_stretch_images = false,
            screensaver_stretch_limit_percentage = 8,
        },
        {
            name = "Zen - White",
            builtin = true,
            screensaver_type = "document_cover",
            screensaver_document_cover = zen_svg,
            screensaver_img_background = "white",
            screensaver_show_message = false,
            screensaver_stretch_images = false,
            screensaver_stretch_limit_percentage = 8,
        },
        {
            name = "Zen - Transparent",
            builtin = true,
            screensaver_type = "document_cover",
            screensaver_document_cover = zen_svg,
            screensaver_img_background = "none",
            screensaver_show_message = false,
            screensaver_stretch_images = false,
            screensaver_stretch_limit_percentage = 8,
        },
    }
end

return { get = get }
