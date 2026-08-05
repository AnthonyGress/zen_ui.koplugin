-- Physical Home button support for KOReader's stock Cloud storage browser.
-- CloudStorage doesn't register a Home key handler by default, so pressing
-- Home there normally does nothing. Close the browser (regardless of folder
-- depth) and return to the default navbar tab underneath, matching the
-- behavior in the File Manager and other Zen UI library views.

local function apply_cloud_storage_home()
    local ok_cs, CloudStorage = pcall(require, "apps/cloudstorage/cloudstorage")
    if not ok_cs or not CloudStorage then return end
    if CloudStorage._zen_home_patched then return end
    CloudStorage._zen_home_patched = true

    local Device = require("device")
    local UIManager = require("ui/uimanager")

    local orig_init = CloudStorage.init
    function CloudStorage:init()
        orig_init(self)
        if Device:hasKeys() then
            self.key_events = self.key_events or {}
            self.key_events.Home = { { "Home" } }
        end
    end

    function CloudStorage:onHome()
        UIManager:close(self)
        local open_default = rawget(_G, "__ZEN_UI_NAVBAR_OPEN_DEFAULT_TAB")
        if type(open_default) == "function" then
            open_default()
        end
        return true
    end
end

return apply_cloud_storage_home
