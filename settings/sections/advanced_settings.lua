-- settings/sections/advanced.lua
-- Advanced / developer settings items for Zen UI.
-- Receives ctx: { plugin, config, save_and_apply, settings_apply }

local _ = require("gettext")
local UIManager = require("ui/uimanager")
local utils = require("settings/zen_settings_utils")

local M = {}

function M.build(ctx)
    local config = ctx.config
    local plugin = ctx.plugin
    local save_and_apply = ctx.save_and_apply
    local settings_apply = ctx.settings_apply

    local items = {}

    table.insert(items, {
        text = _("Preload book metadata"),
        checked_func = function()
            return not (type(config.browser_preload_bookinfo) == "table"
                and config.browser_preload_bookinfo.preload_bookinfo == false)
        end,
        callback = function()
            if type(config.browser_preload_bookinfo) ~= "table" then
                config.browser_preload_bookinfo = {}
            end
            local cur = not (config.browser_preload_bookinfo.preload_bookinfo == false)
            config.browser_preload_bookinfo.preload_bookinfo = not cur
            plugin:saveConfig()
        end,
    })

    table.insert(items, {
        text = _("Partial pages refresh"),
        checked_func = function()
            return config.features.partial_page_repaint == true
        end,
        callback = function()
            config.features.partial_page_repaint = not (config.features.partial_page_repaint == true)
            plugin:saveConfig()
            settings_apply.prompt_restart()
        end,
    })

    table.insert(items, {
        text = _("Show hidden and unsupported files outside home folder"),
        checked_func = function()
            return type(config.developer) == "table"
                and config.developer.show_hidden_outside_home == true
        end,
        callback = function()
            if type(config.developer) ~= "table" then
                config.developer = {}
            end
            local enabling = not (config.developer.show_hidden_outside_home == true)
            config.developer.show_hidden_outside_home = enabling
            plugin:saveConfig()

            if enabling then
                local current_dir = utils.get_current_dir()
                local home_dir = utils.get_home_dir()
                local is_outside_home = current_dir ~= home_dir
                    and current_dir:sub(1, #home_dir + 1) ~= home_dir .. "/"
                G_reader_settings:saveSetting("show_hidden", is_outside_home)
                G_reader_settings:saveSetting("show_unsupported", is_outside_home)
            else
                G_reader_settings:saveSetting("show_hidden", false)
                G_reader_settings:saveSetting("show_unsupported", false)
                local ok, FileManager = pcall(require, "apps/filemanager/filemanager")
                local fm = ok and FileManager and FileManager.instance
                if fm and fm.file_chooser then
                    fm.file_chooser.show_hidden = false
                    fm.file_chooser.show_unsupported = false
                    fm.file_chooser:refreshPath()
                end
            end

            UIManager:nextTick(function()
                settings_apply.prompt_restart()
            end)
        end,
        keep_menu_open = true,
    })

    table.insert(items, {
        text = _("Clear all gestures"),
        callback = function()
            local ConfirmBox = require("ui/widget/confirmbox")
            UIManager:show(ConfirmBox:new{
                text = _("Set all gestures to pass-through? Top-right corner in reader will be kept as Toggle bookmark."),
                ok_text = _("Clear"),
                ok_callback = function()
                    local ok_ds, DataStorage = pcall(require, "datastorage")
                    local ok_ls, LuaSettings = pcall(require, "luasettings")
                    if not ok_ds or not ok_ls then return end
                    local gestures_path = DataStorage:getSettingsDir() .. "/gestures.lua"
                    local settings = LuaSettings:open(gestures_path)
                    for _, section in ipairs({ "gesture_fm", "gesture_reader" }) do
                        if type(settings.data[section]) == "table" then
                            for k in pairs(settings.data[section]) do
                                settings.data[section][k] = nil
                            end
                        else
                            settings.data[section] = {}
                        end
                    end
                    settings.data.gesture_reader.tap_top_right_corner = { toggle_bookmark = true }
                    settings:flush()
                    settings_apply.prompt_restart()
                end,
            })
        end,
    })

    table.insert(items, {
        text = _("Plugin management"),
        sub_item_table_func = function()
            local ok, PluginLoader = pcall(require, "pluginloader")
            if ok and PluginLoader and type(PluginLoader.genPluginManagerSubItem) == "function" then
                return PluginLoader:genPluginManagerSubItem()
            end
            return {}
        end,
    })

    do
        local ok, patch_item = pcall(dofile, "frontend/ui/elements/patch_management.lua")
        if ok and type(patch_item) == "table" then
            table.insert(items, patch_item)
        end
    end

    return items
end

return M
