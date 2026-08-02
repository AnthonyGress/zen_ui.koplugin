local function apply_library_navigation()
    local ReaderUI = require("apps/reader/readerui")
    if ReaderUI._zen_library_navigation_patched then return end

    local plugin = rawget(_G, "__ZEN_UI_PLUGIN")
    local original_onHome = ReaderUI.onHome

    function ReaderUI:onHome(...)
        if self.document then
            return require("common/library_navigation").showFromReader(self, plugin)
        end
        return original_onHome(self, ...)
    end

    ReaderUI._zen_library_navigation_patched = true
end

return apply_library_navigation
