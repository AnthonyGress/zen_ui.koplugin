-- settings/sections/global.lua
-- Global / device-wide settings: schedules and sleep screen.
-- Receives ctx: { plugin, config, save_and_apply }

local _ = require("gettext")
local UIManager = require("ui/uimanager")
local Device = require("device")
local ConfirmBox = require("ui/widget/confirmbox")
local utils = require("modules/settings/zen_settings_utils")

local M = {}

function M.build(ctx)
    local config = ctx.config
    local plugin = ctx.plugin

    -- -------------------------------------------------------------------------
    -- Schedule helpers
    -- -------------------------------------------------------------------------

    local function get_night_schedule_config()
        if type(config.night_mode_schedule) ~= "table" then
            config.night_mode_schedule = {}
        end
        local cfg = config.night_mode_schedule
        return {
            night_on_h  = tonumber(cfg.night_on_h)  or 22,
            night_on_m  = tonumber(cfg.night_on_m)  or 0,
            night_off_h = tonumber(cfg.night_off_h) or 7,
            night_off_m = tonumber(cfg.night_off_m) or 0,
        }
    end

    local function trigger_night_schedule_reschedule()
        local sched = rawget(_G, "__ZEN_UI_NIGHT_SCHEDULE")
        if sched and type(sched.reschedule) == "function" then
            sched.reschedule()
        end
    end

    local function get_warmth_schedule_config()
        if type(config.warmth_schedule) ~= "table" then
            config.warmth_schedule = {}
        end
        local cfg = config.warmth_schedule
        return {
            day_h       = tonumber(cfg.day_h)       or 7,
            day_m       = tonumber(cfg.day_m)       or 0,
            day_value   = tonumber(cfg.day_value)   or 30,
            night_h     = tonumber(cfg.night_h)     or 20,
            night_m     = tonumber(cfg.night_m)     or 0,
            night_value = tonumber(cfg.night_value) or 80,
        }
    end

    local function trigger_warmth_schedule_reschedule()
        local sched = rawget(_G, "__ZEN_UI_WARMTH_SCHEDULE")
        if sched and type(sched.reschedule) == "function" then
            sched.reschedule()
        end
    end

    local function get_brightness_schedule_config()
        if type(config.brightness_schedule) ~= "table" then
            config.brightness_schedule = {}
        end
        local cfg = config.brightness_schedule
        return {
            day_h       = tonumber(cfg.day_h)       or 7,
            day_m       = tonumber(cfg.day_m)       or 0,
            day_value   = tonumber(cfg.day_value)   or 80,
            night_h     = tonumber(cfg.night_h)     or 20,
            night_m     = tonumber(cfg.night_m)     or 0,
            night_value = tonumber(cfg.night_value) or 20,
        }
    end

    local function trigger_brightness_schedule_reschedule()
        local sched = rawget(_G, "__ZEN_UI_BRIGHTNESS_SCHEDULE")
        if sched and type(sched.reschedule) == "function" then
            sched.reschedule()
        end
    end

    -- -------------------------------------------------------------------------
    -- Sleep screen helpers
    -- -------------------------------------------------------------------------

    local _icons_dir
    do
        local src = debug.getinfo(1, "S").source or ""
        if src:sub(1, 1) == "@" then
            local root = src:sub(2):match("^(.*)/modules/settings/")
            if root then
                local lfs = require("libs/libkoreader-lfs")
                if lfs.attributes(root .. "/icons/zen_ui.svg", "mode") == "file" then
                    _icons_dir = root .. "/icons/"
                end
            end
        end
    end

    local builtin_presets = {}
    if _icons_dir then
        local ok_bp, bp_mod = pcall(require, "config/screensaver_presets")
        if ok_bp and bp_mod and type(bp_mod.get) == "function" then
            builtin_presets = bp_mod.get(_icons_dir)
        end
    end

    local function get_sleep_screen_presets()
        if type(config.sleep_screen) ~= "table" then
            config.sleep_screen = { presets = {}, active_preset = nil }
        end
        if type(config.sleep_screen.presets) ~= "table" then
            config.sleep_screen.presets = {}
        end
        return config.sleep_screen.presets
    end

    local function get_all_presets()
        local user = get_sleep_screen_presets()
        local all = {}
        for _, p in ipairs(builtin_presets) do table.insert(all, p) end
        for _, p in ipairs(user)            do table.insert(all, p) end
        return all
    end

    local function capture_sleep_screen_state()
        return {
            screensaver_type = G_reader_settings:readSetting("screensaver_type"),
            screensaver_message = G_reader_settings:readSetting("screensaver_message"),
            screensaver_show_message = G_reader_settings:isTrue("screensaver_show_message"),
            screensaver_img_background = G_reader_settings:readSetting("screensaver_img_background"),
            screensaver_document_cover = G_reader_settings:readSetting("screensaver_document_cover"),
            screensaver_stretch_images = G_reader_settings:isTrue("screensaver_stretch_images"),
            screensaver_stretch_limit_percentage = G_reader_settings:readSetting("screensaver_stretch_limit_percentage"),
        }
    end

    local function apply_sleep_screen_preset(preset)
        if type(preset) ~= "table" then return end
        if preset.screensaver_type then
            G_reader_settings:saveSetting("screensaver_type", preset.screensaver_type)
        end
        if preset.screensaver_message ~= nil then
            G_reader_settings:saveSetting("screensaver_message", preset.screensaver_message)
        end
        if preset.screensaver_show_message ~= nil then
            if preset.screensaver_show_message then
                G_reader_settings:makeTrue("screensaver_show_message")
            else
                G_reader_settings:makeFalse("screensaver_show_message")
            end
        end
        if preset.screensaver_img_background then
            G_reader_settings:saveSetting("screensaver_img_background", preset.screensaver_img_background)
        end
        if preset.screensaver_document_cover ~= nil then
            G_reader_settings:saveSetting("screensaver_document_cover", preset.screensaver_document_cover)
        end
        -- "cover" type uses the last book; stale document_cover paths are irrelevant.
        if preset.screensaver_type == "cover" then
            G_reader_settings:delSetting("screensaver_document_cover")
        end
        if preset.screensaver_stretch_images ~= nil then
            if preset.screensaver_stretch_images then
                G_reader_settings:makeTrue("screensaver_stretch_images")
            else
                G_reader_settings:makeFalse("screensaver_stretch_images")
            end
        end
        if preset.screensaver_stretch_limit_percentage ~= nil then
            G_reader_settings:saveSetting(
                "screensaver_stretch_limit_percentage",
                preset.screensaver_stretch_limit_percentage)
        end
    end

    local function find_preset_by_name(name)
        local user_presets = get_sleep_screen_presets()
        for i, p in ipairs(user_presets) do
            if p.name == name then return p, i end
        end
        return nil, nil
    end

    local function build_preset_items()
        local user_presets = get_sleep_screen_presets()
        local all = get_all_presets()
        local preset_items = {}

        table.insert(preset_items, {
            text = _("Save current settings as preset"),
            keep_menu_open = true,
            callback = function(touchmenu_instance)
                local InputDialog = require("ui/widget/inputdialog")
                local dlg
                dlg = InputDialog:new{
                    title = _("Preset name"),
                    input = "",
                    buttons = {{
                        {
                            text = _("Cancel"),
                            id = "close",
                            callback = function() UIManager:close(dlg) end,
                        },
                        {
                            text = _("Save"),
                            is_enter_default = true,
                            callback = function()
                                local name = dlg:getInputText()
                                if not name or name:match("^%s*$") then return end
                                name = name:match("^%s*(.-)%s*$")
                                UIManager:close(dlg)
                                local _, idx = find_preset_by_name(name)
                                if idx then
                                    table.remove(user_presets, idx)
                                end
                                local state = capture_sleep_screen_state()
                                state.name = name
                                table.insert(user_presets, state)
                                config.sleep_screen.active_preset = name
                                plugin:saveConfig()
                                if touchmenu_instance then
                                    touchmenu_instance.item_table = build_preset_items()
                                    touchmenu_instance:updateItems()
                                end
                            end,
                        },
                    }},
                }
                UIManager:show(dlg)
                dlg:onShowKeyboard()
            end,
            separator = #all > 0,
        })

        for i, preset in ipairs(all) do
            local pname = preset.name
            local is_builtin = preset.builtin == true
            local is_last = (i == #all)
            table.insert(preset_items, {
                text_func = function()
                    local active = config.sleep_screen.active_preset
                    local prefix = (active == pname) and "\u{2713} " or ""
                    return prefix .. pname
                end,
                callback = function(touchmenu_instance)
                    apply_sleep_screen_preset(preset)
                    config.sleep_screen.active_preset = pname
                    plugin:saveConfig()
                    if touchmenu_instance then touchmenu_instance:updateItems() end
                end,
                hold_callback = not is_builtin and function(touchmenu_instance)
                    UIManager:show(ConfirmBox:new{
                        text = _("Delete preset?") .. "\n\n" .. pname,
                        ok_text = _("Delete"),
                        ok_callback = function()
                            local _, idx = find_preset_by_name(pname)
                            if idx then
                                table.remove(user_presets, idx)
                            end
                            if config.sleep_screen.active_preset == pname then
                                config.sleep_screen.active_preset = nil
                            end
                            plugin:saveConfig()
                            if touchmenu_instance then
                                touchmenu_instance.item_table = build_preset_items()
                                touchmenu_instance:updateItems()
                            end
                        end,
                    })
                end or nil,
                separator = is_last
                    or (is_builtin and all[i + 1] ~= nil and not all[i + 1].builtin),
            })
        end

        return preset_items
    end

    -- -------------------------------------------------------------------------
    -- Build items
    -- -------------------------------------------------------------------------

    local items = {}

    -- Night mode schedule
    table.insert(items, {
        text = _("Night mode schedule"),
        sub_item_table = {
            {
                text = _("Enable night mode schedule"),
                checked_func = function()
                    return config.features.night_mode_schedule == true
                end,
                callback = function()
                    config.features.night_mode_schedule =
                        not (config.features.night_mode_schedule == true)
                    plugin:saveConfig()
                    trigger_night_schedule_reschedule()
                end,
            },
            {
                text_func = function()
                    local cfg = get_night_schedule_config()
                    return _("Night mode on: ") .. utils.fmt_time(cfg.night_on_h, cfg.night_on_m)
                end,
                enabled_func = function()
                    return config.features.night_mode_schedule == true
                end,
                keep_menu_open = true,
                callback = function(touchmenu_instance)
                    local cfg = get_night_schedule_config()
                    utils.show_time_picker(_("Night mode on time"),
                        cfg.night_on_h, cfg.night_on_m,
                        function(h, m)
                            if type(config.night_mode_schedule) ~= "table" then
                                config.night_mode_schedule = {}
                            end
                            config.night_mode_schedule.night_on_h = h
                            config.night_mode_schedule.night_on_m = m
                            plugin:saveConfig()
                            trigger_night_schedule_reschedule()
                            if touchmenu_instance then touchmenu_instance:updateItems() end
                        end)
                end,
            },
            {
                text_func = function()
                    local cfg = get_night_schedule_config()
                    return _("Night mode off: ") .. utils.fmt_time(cfg.night_off_h, cfg.night_off_m)
                end,
                enabled_func = function()
                    return config.features.night_mode_schedule == true
                end,
                keep_menu_open = true,
                callback = function(touchmenu_instance)
                    local cfg = get_night_schedule_config()
                    utils.show_time_picker(_("Night mode off time"),
                        cfg.night_off_h, cfg.night_off_m,
                        function(h, m)
                            if type(config.night_mode_schedule) ~= "table" then
                                config.night_mode_schedule = {}
                            end
                            config.night_mode_schedule.night_off_h = h
                            config.night_mode_schedule.night_off_m = m
                            plugin:saveConfig()
                            trigger_night_schedule_reschedule()
                            if touchmenu_instance then touchmenu_instance:updateItems() end
                        end)
                end,
            },
        },
    })

    -- Brightness schedule
    table.insert(items, {
        text = _("Brightness schedule"),
        sub_item_table = {
            {
                text = _("Enable brightness schedule"),
                checked_func = function()
                    return config.features.brightness_schedule == true
                end,
                callback = function()
                    config.features.brightness_schedule =
                        not (config.features.brightness_schedule == true)
                    plugin:saveConfig()
                    trigger_brightness_schedule_reschedule()
                end,
            },
            {
                text_func = function()
                    local cfg = get_brightness_schedule_config()
                    return _("Day brightness time: ") .. utils.fmt_time(cfg.day_h, cfg.day_m)
                end,
                enabled_func = function()
                    return config.features.brightness_schedule == true
                end,
                keep_menu_open = true,
                callback = function(touchmenu_instance)
                    local cfg = get_brightness_schedule_config()
                    utils.show_time_picker(_("Day brightness time"), cfg.day_h, cfg.day_m,
                        function(h, m)
                            if type(config.brightness_schedule) ~= "table" then
                                config.brightness_schedule = {}
                            end
                            config.brightness_schedule.day_h = h
                            config.brightness_schedule.day_m = m
                            plugin:saveConfig()
                            trigger_brightness_schedule_reschedule()
                            if touchmenu_instance then touchmenu_instance:updateItems() end
                        end)
                end,
            },
            {
                text_func = function()
                    local cfg = get_brightness_schedule_config()
                    return _("Day brightness: ") .. cfg.day_value
                end,
                enabled_func = function()
                    return config.features.brightness_schedule == true
                end,
                keep_menu_open = true,
                callback = function(touchmenu_instance)
                    local cfg = get_brightness_schedule_config()
                    local powerd = Device.powerd
                    utils.show_value_picker(_("Day brightness"), cfg.day_value,
                        function(v)
                            if type(config.brightness_schedule) ~= "table" then
                                config.brightness_schedule = {}
                            end
                            config.brightness_schedule.day_value = v
                            plugin:saveConfig()
                            if touchmenu_instance then touchmenu_instance:updateItems() end
                        end, powerd.fl_min, powerd.fl_max)
                end,
            },
            {
                text_func = function()
                    local cfg = get_brightness_schedule_config()
                    return _("Night brightness time: ") .. utils.fmt_time(cfg.night_h, cfg.night_m)
                end,
                enabled_func = function()
                    return config.features.brightness_schedule == true
                end,
                keep_menu_open = true,
                callback = function(touchmenu_instance)
                    local cfg = get_brightness_schedule_config()
                    utils.show_time_picker(_("Night brightness time"), cfg.night_h, cfg.night_m,
                        function(h, m)
                            if type(config.brightness_schedule) ~= "table" then
                                config.brightness_schedule = {}
                            end
                            config.brightness_schedule.night_h = h
                            config.brightness_schedule.night_m = m
                            plugin:saveConfig()
                            trigger_brightness_schedule_reschedule()
                            if touchmenu_instance then touchmenu_instance:updateItems() end
                        end)
                end,
            },
            {
                text_func = function()
                    local cfg = get_brightness_schedule_config()
                    return _("Night brightness: ") .. cfg.night_value
                end,
                enabled_func = function()
                    return config.features.brightness_schedule == true
                end,
                keep_menu_open = true,
                callback = function(touchmenu_instance)
                    local cfg = get_brightness_schedule_config()
                    local powerd = Device.powerd
                    utils.show_value_picker(_("Night brightness"), cfg.night_value,
                        function(v)
                            if type(config.brightness_schedule) ~= "table" then
                                config.brightness_schedule = {}
                            end
                            config.brightness_schedule.night_value = v
                            plugin:saveConfig()
                            if touchmenu_instance then touchmenu_instance:updateItems() end
                        end, powerd.fl_min, powerd.fl_max)
                end,
            },
        },
    })

    -- Warmth schedule
    table.insert(items, {
        text = _("Warmth schedule"),
        enabled_func = function() return Device:hasNaturalLight() end,
        sub_item_table = {
            {
                text = _("Enable warmth schedule"),
                checked_func = function()
                    return config.features.warmth_schedule == true
                end,
                callback = function()
                    config.features.warmth_schedule = not (config.features.warmth_schedule == true)
                    plugin:saveConfig()
                    trigger_warmth_schedule_reschedule()
                end,
            },
            {
                text_func = function()
                    local cfg = get_warmth_schedule_config()
                    return _("Day warmth time: ") .. utils.fmt_time(cfg.day_h, cfg.day_m)
                end,
                enabled_func = function()
                    return config.features.warmth_schedule == true
                end,
                keep_menu_open = true,
                callback = function(touchmenu_instance)
                    local cfg = get_warmth_schedule_config()
                    utils.show_time_picker(_("Day warmth time"), cfg.day_h, cfg.day_m,
                        function(h, m)
                            if type(config.warmth_schedule) ~= "table" then
                                config.warmth_schedule = {}
                            end
                            config.warmth_schedule.day_h = h
                            config.warmth_schedule.day_m = m
                            plugin:saveConfig()
                            trigger_warmth_schedule_reschedule()
                            if touchmenu_instance then touchmenu_instance:updateItems() end
                        end)
                end,
            },
            {
                text_func = function()
                    local cfg = get_warmth_schedule_config()
                    return _("Day warmth: ") .. cfg.day_value
                end,
                enabled_func = function()
                    return config.features.warmth_schedule == true
                end,
                keep_menu_open = true,
                callback = function(touchmenu_instance)
                    local cfg = get_warmth_schedule_config()
                    local powerd = Device.powerd
                    utils.show_value_picker(_("Day warmth"), cfg.day_value,
                        function(v)
                            if type(config.warmth_schedule) ~= "table" then
                                config.warmth_schedule = {}
                            end
                            config.warmth_schedule.day_value = v
                            plugin:saveConfig()
                            if touchmenu_instance then touchmenu_instance:updateItems() end
                        end, powerd.fl_warmth_min, powerd.fl_warmth_max)
                end,
            },
            {
                text_func = function()
                    local cfg = get_warmth_schedule_config()
                    return _("Night warmth time: ") .. utils.fmt_time(cfg.night_h, cfg.night_m)
                end,
                enabled_func = function()
                    return config.features.warmth_schedule == true
                end,
                keep_menu_open = true,
                callback = function(touchmenu_instance)
                    local cfg = get_warmth_schedule_config()
                    utils.show_time_picker(_("Night warmth time"), cfg.night_h, cfg.night_m,
                        function(h, m)
                            if type(config.warmth_schedule) ~= "table" then
                                config.warmth_schedule = {}
                            end
                            config.warmth_schedule.night_h = h
                            config.warmth_schedule.night_m = m
                            plugin:saveConfig()
                            trigger_warmth_schedule_reschedule()
                            if touchmenu_instance then touchmenu_instance:updateItems() end
                        end)
                end,
            },
            {
                text_func = function()
                    local cfg = get_warmth_schedule_config()
                    return _("Night warmth: ") .. cfg.night_value
                end,
                enabled_func = function()
                    return config.features.warmth_schedule == true
                end,
                keep_menu_open = true,
                callback = function(touchmenu_instance)
                    local cfg = get_warmth_schedule_config()
                    local powerd = Device.powerd
                    utils.show_value_picker(_("Night warmth"), cfg.night_value,
                        function(v)
                            if type(config.warmth_schedule) ~= "table" then
                                config.warmth_schedule = {}
                            end
                            config.warmth_schedule.night_value = v
                            plugin:saveConfig()
                            if touchmenu_instance then touchmenu_instance:updateItems() end
                        end, powerd.fl_warmth_min, powerd.fl_warmth_max)
                end,
            },
        },
    })

    -- Sleep
    table.insert(items, {
        text = _("Sleep"),
        enabled_func = function()
            local ok, Dev = pcall(require, "device")
            return ok and Dev and type(Dev.supportsScreensaver) == "function"
                and Dev:supportsScreensaver()
        end,
        sub_item_table_func = function()
            local ok, screen_items = pcall(dofile, "frontend/ui/elements/screensaver_menu.lua")
            local sub = (ok and type(screen_items) == "table") and screen_items or {}
            table.insert(sub, {
                text = _("Presets"),
                sub_item_table_func = build_preset_items,
            })
            -- find current UI instance to access plugin instances
            local ok_r, ReaderUI = pcall(require, "apps/reader/readerui")
            local ok_f, FileManager = pcall(require, "apps/filemanager/filemanager")
            local ui = (ok_r and ReaderUI and ReaderUI.instance)
                     or (ok_f and FileManager and FileManager.instance)
            -- Automatic dimmer (autodim.koplugin)
            if ui and ui.autodim and type(ui.autodim.getAutoDimMenu) == "function" then
                local autodim_item = ui.autodim:getAutoDimMenu()
                if autodim_item then table.insert(sub, autodim_item) end
            end
            -- Automatic suspend (autosuspend.koplugin)
            if ui and ui.autosuspend and type(ui.autosuspend.addToMainMenu) == "function" then
                local menu_items = {}
                ui.autosuspend:addToMainMenu(menu_items)
                local suspend_sub = {}
                for _, key in ipairs({ "autosuspend", "autoshutdown", "autostandby" }) do
                    if menu_items[key] then table.insert(suspend_sub, menu_items[key]) end
                end
                if #suspend_sub > 0 then
                    table.insert(sub, {
                        text = _("Automatic suspend"),
                        sub_item_table = suspend_sub,
                    })
                end
            end
            return sub
        end,
    })

    -- Lockdown mode
    table.insert(items, {
        text = _("Lockdown mode"),
        sub_item_table = {
            {
                text = _("Magnify UI"),
                checked_func = function()
                    return config.lockdown and config.lockdown.magnify_ui == true
                end,
                callback = function()
                    if type(config.lockdown) ~= "table" then config.lockdown = {} end
                    config.lockdown.magnify_ui = not config.lockdown.magnify_ui
                    plugin:saveConfig()
                end,
            },
            {
                text = _("Library"),
                sub_item_table = {
                    {
                        text = _("Disable context menu"),
                        checked_func = function()
                            return config.lockdown and config.lockdown.disable_context_menu == true
                        end,
                        callback = function()
                            if type(config.lockdown) ~= "table" then config.lockdown = {} end
                            config.lockdown.disable_context_menu = not config.lockdown.disable_context_menu
                            plugin:saveConfig()
                        end,
                    },
                },
            },
            {
                text = _("Quick Settings"),
                sub_item_table = {
                    {
                        text = _("Require hold to toggle buttons"),
                        checked_func = function()
                            return config.lockdown and config.lockdown.require_hold_in_qs == true
                        end,
                        callback = function()
                            if type(config.lockdown) ~= "table" then config.lockdown = {} end
                            config.lockdown.require_hold_in_qs = not config.lockdown.require_hold_in_qs
                            plugin:saveConfig()
                        end,
                    },
                    {
                        text = _("Disable settings panel"),
                        checked_func = function()
                            return config.lockdown and config.lockdown.disable_settings_panel == true
                        end,
                        callback = function()
                            if type(config.lockdown) ~= "table" then config.lockdown = {} end
                            config.lockdown.disable_settings_panel = not config.lockdown.disable_settings_panel
                            plugin:saveConfig()
                        end,
                    },
                },
            },
            {
                text = _("Reader"),
                sub_item_table = {
                    {
                        text = _("Disable bottom menu swipe"),
                        checked_func = function()
                            return config.lockdown and config.lockdown.disable_bottom_menu_swipe == true
                        end,
                        callback = function()
                            if type(config.lockdown) ~= "table" then config.lockdown = {} end
                            config.lockdown.disable_bottom_menu_swipe = not config.lockdown.disable_bottom_menu_swipe
                            plugin:saveConfig()
                        end,
                    },
                    {
                        text = _("Disable multi-word selection"),
                        checked_func = function()
                            return config.lockdown and config.lockdown.disable_word_selection == true
                        end,
                        callback = function()
                            if type(config.lockdown) ~= "table" then config.lockdown = {} end
                            config.lockdown.disable_word_selection = not config.lockdown.disable_word_selection
                            plugin:saveConfig()
                        end,
                    },
                    {
                        text = _("Disable word search on hold"),
                        checked_func = function()
                            return config.lockdown and config.lockdown.disable_hold_search == true
                        end,
                        callback = function()
                            if type(config.lockdown) ~= "table" then config.lockdown = {} end
                            config.lockdown.disable_hold_search = not config.lockdown.disable_hold_search
                            plugin:saveConfig()
                        end,
                    },
                },
            },
        },
    })

    return items
end

return M
