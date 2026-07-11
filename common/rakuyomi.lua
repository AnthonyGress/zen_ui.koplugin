local M = {}

local function live_plugin()
    local fm_mod = package.loaded["apps/filemanager/filemanager"]
    local fm = fm_mod and fm_mod.instance
    if type(fm) == "table" and type(fm.rakuyomi) == "table" then
        return fm.rakuyomi
    end
end

local function loaded_plugin()
    local ok_loader, loader = pcall(require, "pluginloader")
    if not ok_loader or not loader then return nil end

    local loaded = loader.loaded_plugins
    if type(loaded) == "table" and type(loaded.rakuyomi) == "table" then
        return loaded.rakuyomi
    end

    if type(loader.getPluginInstance) == "function" then
        local ok_plugin, plugin = pcall(loader.getPluginInstance, loader, "rakuyomi")
        if ok_plugin and type(plugin) == "table" then
            return plugin
        end
    end
end

function M.is_available()
    return live_plugin() ~= nil or loaded_plugin() ~= nil
end

return M
