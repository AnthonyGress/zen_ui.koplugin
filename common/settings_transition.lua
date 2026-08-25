local M = {}

function M.close()
    if not rawget(_G, "__ZEN_UI_SETTINGS_PAGE") then return false end
    local ok, settings_page = pcall(require, "modules/settings/zen_settings_page")
    if not (ok and type(settings_page.closeActive) == "function") then return false end
    settings_page.closeActive()
    return true
end

return M
