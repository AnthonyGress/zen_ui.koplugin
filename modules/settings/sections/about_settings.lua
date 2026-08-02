-- settings/sections/about.lua
-- "About" info items: plugin version plus a grouped device subsection.
-- Receives ctx: { plugin, config, save_and_apply, settings_apply }

local _ = require("gettext")
local T = require("ffi/util").template
local UIManager = require("ui/uimanager")
local utils = require("modules/settings/zen_settings_utils")
local bugreporter = require("modules/settings/zen_bugreporter")
local updater = require("modules/settings/zen_updater")
local advanced_section = require("modules/settings/sections/advanced_settings")
local icons = require("common/inline_icon_map")
local IconItem = require("common/ui/icon_menu_item")

local M = {}

local function build_koreader_update_item()
    local ok_device, Device = pcall(require, "device")
    local has_ota = ok_device and Device and type(Device.hasOTAUpdates) == "function"
        and Device:hasOTAUpdates()
    if not has_ota then return nil end

    return {
        text = _("Update KOReader"),
        keep_menu_open = true,
        callback = function()
            local OTAManager = require("ui/otamanager")
            local NetworkMgr = require("ui/network/manager")
            NetworkMgr:runWhenOnline(function()
                OTAManager:fetchAndProcessUpdate()
            end)
        end,
    }
end

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
        text = _("Device"),
        sub_item_table = {
            {
                text_func = function()
                    return _("KOReader: ") .. utils.get_koreader_version()
                end,
                keep_menu_open = true,
            },
            {
                text_func = function()
                    return _("Device: ") .. utils.get_device_model_name()
                end,
                keep_menu_open = true,
            },
            {
                text_func = function()
                    return _("Firmware: ") .. utils.get_device_firmware_display()
                end,
                keep_menu_open = true,
            },
            {
                text_func = function()
                    return T(_("IP address: %1"), utils.get_device_ip_address() or "—")
                end,
                keep_menu_open = true,
            },
        },
    })

    table.insert(items, {
        text = _("Setup Guide"),
        callback = function()
            local ok_qs, QuickstartScreen = pcall(require, "common/quickstart/quickstart_screen")
            if not ok_qs then return end
            local ok_pg, pages_mod = pcall(require, "common/quickstart/quickstart_pages")
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
        text = _("Advanced"),
        sub_item_table = advanced_section.build(ctx),
    })

    local update_items = {
        updater.build_update_now_item(plugin),
        updater.build_changelog_item(),
        updater.build_channel_item(),
        updater.build_auto_check_item(),
    }
    local koreader_update_item = build_koreader_update_item()
    if koreader_update_item then
        table.insert(update_items, 2, koreader_update_item)
    end

    table.insert(items, {
        text = _("Updates"),
        separator = true,
        sub_item_table = update_items,
    })

    IconItem.decorate(items[1], icons.details)
    IconItem.decorate(items[2], icons.settings_device)
    IconItem.decorate(items[3], icons.settings_setup)
    IconItem.decorate(items[4], icons.settings_bug)
    IconItem.decorate(items[5], icons.settings_advanced)
    IconItem.decorate(items[6], icons.update)

    return items
end

return M
