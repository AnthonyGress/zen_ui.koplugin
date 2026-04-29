-- settings/sections/menu.lua
-- Touch menu settings items for Zen UI (Quick Settings panel).
-- Receives ctx: { plugin, config, save_and_apply }

local _ = require("gettext")
local UIManager = require("ui/uimanager")
local utils = require("modules/settings/zen_settings_utils")

local M = {}

function M.build(ctx)
    local config = ctx.config
    local save_and_apply = ctx.save_and_apply

    local function save_and_apply_quick_settings() save_and_apply("quick_settings") end

    local function make_enable_feature_item(feature, text)
        return utils.make_enable_feature_item(feature, text, config, save_and_apply)
    end

    -- Resolve UI instance once for plugin-availability checks (fail-open if nil).
    local _ui
    do
        local ok_f, FM = pcall(require, "apps/filemanager/filemanager")
        local ok_r, RU = pcall(require, "apps/reader/readerui")
        _ui = (ok_f and FM.instance) or (ok_r and RU.instance)
    end
    -- Returns true when the plugin slot exists on the UI, or when the UI is
    -- unavailable (fail-open so we never silently hide a reachable button).
    local function hasPlugin(slot)
        return _ui == nil or _ui[slot] ~= nil
    end

    local quick_button_items = {
        { key = "wifi",    text = _("Wi-Fi")       },
        { key = "night",   text = _("Night mode")  },
        { key = "zen",     text = _("Zen mode")    },
        { key = "lockdown",text = _("Lockdown")    },
        { key = "rotate",  text = _("Rotate")      },
        { key = "usb",     text = _("USB")         },
        { key = "search",  text = _("File search") },
        { key = "restart", text = _("Restart")     },
        { key = "exit",    text = _("Exit")        },
        { key = "sleep",   text = _("Sleep")       },
        -- Optional: only shown when the plugin/feature is detected.
        { key = "quickrss",       text = _("QuickRSS"),        detect = function() local ok = pcall(require, "modules/ui/feed_view"); return ok end },
        { key = "cloud",          text = _("Cloud storage"),   detect = function() return hasPlugin("cloudstorage") end },
        { key = "zlibrary",       text = _("Z-Library"),       detect = function() return hasPlugin("zlibrary") end },
        { key = "calibre",        text = _("Calibre"),         detect = function() return hasPlugin("wireless") end },
        { key = "calibre_search", text = _("Calibre Search"),  detect = function() return hasPlugin("calibre") end },
        { key = "notion",         text = _("Notion"),          detect = function() return hasPlugin("NotionSync") end },
        { key = "streak",         text = _("Streak"),          detect = function() return hasPlugin("readingstreak") end },
        { key = "opds",           text = _("OPDS"),            detect = function() return hasPlugin("opds") end },
        { key = "filebrowser",    text = _("Filebrowser"),     detect = function() return hasPlugin("filebrowser") end },
        { key = "puzzle",         text = _("Slide Puzzle"),    detect = function() return hasPlugin("slidepuzzle") end },
        { key = "crossword",      text = _("Crossword"),       detect = function() return hasPlugin("crossword") end },
        { key = "connections",    text = _("Connections"),      detect = function() return hasPlugin("nytconnections") end },
        { key = "stats_progress", text = _("Stats: Progress"), detect = function() return hasPlugin("statistics") end },
        { key = "stats_calendar", text = _("Stats: Calendar"), detect = function() return hasPlugin("statistics") end },
        { key = "kosync",         text = _("Sync") },
    }

    -- Remove any button whose plugin/feature is not detected.
    do
        local filtered = {}
        for _, item in ipairs(quick_button_items) do
            if not item.detect or item.detect() then
                filtered[#filtered + 1] = item
            end
        end
        quick_button_items = filtered
    end

    table.sort(quick_button_items, function(a, b) return a.text < b.text end)

    local quick_button_label_by_id = {}
    for _, quick_item in ipairs(quick_button_items) do
        quick_button_label_by_id[quick_item.key] = quick_item.text
    end

    local quick_buttons_max = 9

    -- only count buttons that are actually toggleable in the UI
    local quick_button_key_set = {}
    for _, item in ipairs(quick_button_items) do
        quick_button_key_set[item.key] = true
    end

    local function countEnabledButtons()
        local count = 0
        for key, v in pairs(config.quick_settings.show_buttons) do
            if v == true and quick_button_key_set[key] then count = count + 1 end
        end
        return count
    end

    local quick_button_sub_items = {}

    table.insert(quick_button_sub_items, {
        text = _("Arrange buttons"),
        keep_menu_open = true,
        separator = true,
        callback = function()
            local SortWidget = require("ui/widget/sortwidget")
            local sort_items = {}
            for _, id in ipairs(config.quick_settings.button_order) do
                local label = quick_button_label_by_id[id]
                if label then
                    table.insert(sort_items, {
                        text = label,
                        orig_item = id,
                        dim = not (config.quick_settings.show_buttons[id] == true),
                    })
                end
            end
            UIManager:show(SortWidget:new{
                title = _("Arrange quick settings buttons"),
                item_table = sort_items,
                callback = function()
                    -- Replace the table to avoid leaving stale trailing entries
                    local new_order = {}
                    local in_sort = {}
                    for _, item in ipairs(sort_items) do
                        table.insert(new_order, item.orig_item)
                        in_sort[item.orig_item] = true
                    end
                    -- Preserve any orphaned entries not shown in the sort widget
                    for _, id in ipairs(config.quick_settings.button_order) do
                        if not in_sort[id] then
                            table.insert(new_order, id)
                        end
                    end
                    config.quick_settings.button_order = new_order
                    save_and_apply_quick_settings()
                end,
            })
        end,
    })

    for _, quick_item in ipairs(quick_button_items) do
        local key = quick_item.key
        table.insert(quick_button_sub_items, {
            text = quick_item.text,
            checked_func = function()
                return config.quick_settings.show_buttons[key] == true
            end,
            enabled_func = function()
                return config.quick_settings.show_buttons[key] == true
                    or countEnabledButtons() < quick_buttons_max
            end,
            callback = function()
                config.quick_settings.show_buttons[key] = not (config.quick_settings.show_buttons[key] == true)
                save_and_apply_quick_settings()
            end,
        })
    end

    return {
        text = _("Quick Settings"),
        sub_item_table = {
            {
                text = _("Buttons"),
                sub_item_table = quick_button_sub_items,
            },
            {
                text = _("Show brightness slider"),
                checked_func = function() return config.quick_settings.show_frontlight == true end,
                callback = function()
                    config.quick_settings.show_frontlight = not (config.quick_settings.show_frontlight == true)
                    save_and_apply_quick_settings()
                end,
            },
            {
                text = _("Show warmth slider"),
                checked_func = function() return config.quick_settings.show_warmth == true end,
                callback = function()
                    config.quick_settings.show_warmth = not (config.quick_settings.show_warmth == true)
                    save_and_apply_quick_settings()
                end,
            },
        },
    }
end

return M
