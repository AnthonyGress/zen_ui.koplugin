local function apply_screensaver_cover()
    -- When a book has no cover (or the user hasn't set a screensaver folder),
    -- KOReader falls back to "resources/koreader.png".  Replace that with the
    -- Zen UI logo so the device shows our branding instead.

    -- Resolve both SVG variants from this file's path at apply-time.
    local _icons_dir
    do
        local src = debug.getinfo(1, "S").source or ""
        if src:sub(1, 1) == "@" then
            local root = src:sub(2):match("^(.*)/modules/")
            if root then
                local lfs = require("libs/libkoreader-lfs")
                local p = root .. "/icons/zen_ui.svg"
                if lfs.attributes(p, "mode") == "file" then
                    _icons_dir = root .. "/icons/"
                end
            end
        end
    end

    if not _icons_dir then return end

    local Screensaver = require("ui/screensaver")
    local orig_setup = Screensaver.setup

    function Screensaver:setup(event, event_message)
        orig_setup(self, event, event_message)
        if self.image_file == "resources/koreader.png" then
            -- Choose logo variant based on the background fill setting:
            -- black background → white logo; white/none → dark logo.
            local bg = G_reader_settings:readSetting("screensaver_img_background")
            if bg == "black" then
                self.image_file = _icons_dir .. "zen_ui_light.svg"
            else
                self.image_file = _icons_dir .. "zen_ui.svg"
            end
        end
    end
end

return apply_screensaver_cover
