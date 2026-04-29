-- settings/sections/about.lua
-- "About" info items: plugin version, KOReader version, device, firmware.
-- Receives ctx: { plugin }

local _ = require("gettext")
local UIManager = require("ui/uimanager")
local utils = require("modules/settings/zen_settings_utils")
local bugreporter = require("modules/settings/zen_bugreporter")
local updater = require("modules/settings/zen_updater")

local M = {}

function M.build(ctx)
    local plugin = ctx.plugin
    local items = {}

    table.insert(items, {
        text_func = function()
            return _("Zen UI: ") .. utils.get_plugin_version(plugin)
        end,
        keep_menu_open = true,
    })

    table.insert(items, {
        text_func = function()
            return _("KOReader: ") .. utils.get_koreader_version()
        end,
        keep_menu_open = true,
    })

    table.insert(items, {
        text_func = function()
            return _("Device: ") .. utils.get_device_model_name()
        end,
        keep_menu_open = true,
    })

    local fw = utils.get_device_firmware_display()
    if fw ~= "n/a" then
        table.insert(items, {
            text_func = function()
                return _("Firmware: ") .. utils.get_device_firmware_display()
            end,
            keep_menu_open = true,
            separator = true
        })
    end

    table.insert(items, {
        text = _("Setup Guide"),
        separator = true,
        callback = function()
            local ok_qs, QuickstartScreen = pcall(require, "common/quickstart_screen")
            if not ok_qs then return end
            local ok_pg, pages_mod = pcall(require, "common/quickstart_pages")
            if not ok_pg then return end
            UIManager:show(QuickstartScreen:new{
                pages    = pages_mod.build_install_pages({
                    plugin = plugin,
                    config = ctx.config,
                }),
                on_close = function()
                    UIManager:nextTick(function()
                        local reinject = _G.__ZEN_UI_REINJECT_FM_NAVBAR
                        if type(reinject) == "function" then reinject() end
                        local ok, FileManager = pcall(require, "apps/filemanager/filemanager")
                        local fm = ok and FileManager and FileManager.instance
                        if fm and type(fm._updateStatusBar) == "function" then
                            fm:_updateStatusBar()
                        end
                    end)
                end,
            })
        end,
    })

    table.insert(items, {
        text      = _("Report a Bug"),
        callback  = function()
            bugreporter.show_dialog(ctx)
        end,
        keep_menu_open = true,
    })

    table.insert(items, {
        text = _("Updates"),
        separator = true,
        sub_item_table = {
            updater.build_update_now_item(plugin),
            updater.build_channel_item(),
        },
    })

    return items
end

return M
