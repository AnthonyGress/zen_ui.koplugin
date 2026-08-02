local function apply_kindle_network_profile_guard()
    if rawget(_G, "__ZEN_UI_KINDLE_NETWORK_PROFILE_GUARD") then return end

    local Device = require("device")
    if not (Device.isKindle and Device:isKindle()) then return end

    local ok_nm, NetworkMgr = pcall(require, "ui/network/manager")
    if not ok_nm or not NetworkMgr or type(NetworkMgr.getNetworkList) ~= "function" then return end

    _G.__ZEN_UI_KINDLE_NETWORK_PROFILE_GUARD = true
    local logger = require("common/zen_logger").new("kindle_network_profile_guard")
    local _ = require("gettext")
    local orig_getNetworkList = NetworkMgr.getNetworkList

    NetworkMgr.getNetworkList = function(self, ...)
        local results = { pcall(orig_getNetworkList, self, ...) }
        if results[1] then
            return results[2], results[3]
        end

        local err = tostring(results[2])
        if err:find("device/kindle/device.lua", 1, true)
                and (err:find("current_profile", 1, true) or err:find("saved_profiles", 1, true)) then
            logger.warn("suppressed Kindle Wi-Fi profile scan crash", err)
            return nil, _("Could not scan Wi-Fi networks. Please try again after waking the device.")
        end

        error(results[2])
    end
end

return apply_kindle_network_profile_guard
