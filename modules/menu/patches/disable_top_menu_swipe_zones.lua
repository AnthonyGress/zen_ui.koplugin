local function apply_disable_top_menu_swipe_zones()
    local ReaderMenu = require("apps/reader/modules/readermenu")
    local zen_plugin = rawget(_G, "__ZEN_UI_PLUGIN")

    local function is_enabled()
        local features = zen_plugin and zen_plugin.config and zen_plugin.config.features
        return type(features) == "table" and features.disable_top_menu_swipe_zones == true
    end

    local _reader_getTabIndexFromLocation_orig = ReaderMenu._getTabIndexFromLocation
    ReaderMenu._getTabIndexFromLocation = function(self, ges)
        if not is_enabled() then
            return _reader_getTabIndexFromLocation_orig(self, ges)
        end
        return self.last_tab_index
    end

    local FileManagerMenu = require("apps/filemanager/filemanagermenu")

    local _fm_getTabIndexFromLocation_orig = FileManagerMenu._getTabIndexFromLocation
    FileManagerMenu._getTabIndexFromLocation = function(self, ges)
        if not is_enabled() then
            return _fm_getTabIndexFromLocation_orig(self, ges)
        end
        return self.last_tab_index
    end
end

return apply_disable_top_menu_swipe_zones
