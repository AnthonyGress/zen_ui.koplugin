-- settings/sections/extras.lua
-- Extra integration settings for Zen UI.
-- Receives ctx: { plugin, config, settings_apply }

local _ = require("gettext")
local Rakuyomi = require("common/rakuyomi")
local SharedState = require("common/shared_state")
local global_settings = require("modules/settings/sections/global_settings")

local M = {}

function M.build(ctx)
    local config = ctx.config
    local plugin = ctx.plugin
    local settings_apply = ctx.settings_apply
    local items = {}

    do
        if type(config.opds) ~= "table" then
            config.opds = {}
        end
        if config.opds.display_mode ~= "list" and config.opds.display_mode ~= "classic" then
            config.opds.display_mode = "mosaic"
        end

        local display_modes = {
            { text = _("Mosaic"),  mode = "mosaic"  },
            { text = _("List"),    mode = "list"    },
            { text = _("Classic"), mode = "classic" },
        }
        local display_mode_items = {}
        for _i, entry in ipairs(display_modes) do
            table.insert(display_mode_items, {
                text = entry.text,
                radio = true,
                checked_func = function()
                    return config.opds.display_mode == entry.mode
                end,
                callback = function(touchmenu_instance)
                    if config.opds.display_mode == entry.mode then return end
                    config.opds.display_mode = entry.mode
                    plugin:saveConfig()
                    if touchmenu_instance then touchmenu_instance:updateItems() end
                end,
            })
        end

        table.insert(items, {
            text = _("Zen OPDS"),
            help_text = _("Enable Zen UI enhancements to the OPDS browser: cover art, list view, hold menu, and navigation improvements."),
            sub_item_table = {
                {
                    text = _("Enable Zen OPDS"),
                    checked_func = function()
                        return config.features.zen_opds ~= false
                    end,
                    callback = function(touchmenu_instance)
                        config.features.zen_opds = config.features.zen_opds == false
                        plugin:saveConfig()
                        if touchmenu_instance then touchmenu_instance:updateItems() end
                        settings_apply.prompt_restart()
                    end,
                },
                {
                    text = _("Display mode"),
                    sub_item_table = display_mode_items,
                },
            },
        })
    end

    if Rakuyomi.is_available() then
        if type(config.rakuyomi) ~= "table" then
            config.rakuyomi = {}
        end
        local migrated_rakuyomi = false
        if config.rakuyomi.return_to_chapter_list_on_exit == nil then
            if config.rakuyomi.return_to_chapter_list_on_reader_exit ~= nil then
                config.rakuyomi.return_to_chapter_list_on_exit =
                    config.rakuyomi.return_to_chapter_list_on_reader_exit
                migrated_rakuyomi = true
            else
                config.rakuyomi.return_to_chapter_list_on_exit = true
            end
        end
        if config.rakuyomi.return_to_chapter_list_on_reader_exit ~= nil then
            config.rakuyomi.return_to_chapter_list_on_reader_exit = nil
            migrated_rakuyomi = true
        end
        if config.rakuyomi.return_to_chapter_on_reader_exit ~= nil then
            config.rakuyomi.return_to_chapter_on_reader_exit = nil
            migrated_rakuyomi = true
        end
        if config.rakuyomi.reverse_page_scrolling == nil then
            config.rakuyomi.reverse_page_scrolling = false
        end
        if migrated_rakuyomi then
            plugin:saveConfig()
        end
        table.insert(items, {
            text = _("Rakuyomi"),
            sub_item_table = {
                {
                    text = _("Return to chapter list on exit"),
                    checked_func = function()
                        return config.rakuyomi.return_to_chapter_list_on_exit ~= false
                    end,
                    callback = function(touchmenu_instance)
                        config.rakuyomi.return_to_chapter_list_on_exit =
                            config.rakuyomi.return_to_chapter_list_on_exit == false
                        plugin:saveConfig()
                        if touchmenu_instance then touchmenu_instance:updateItems() end
                    end,
                },
                {
                    text = _("Reverse page scrolling"),
                    checked_func = function()
                        return config.rakuyomi.reverse_page_scrolling == true
                    end,
                    callback = function(touchmenu_instance)
                        local enabled = config.rakuyomi.reverse_page_scrolling ~= true
                        config.rakuyomi.reverse_page_scrolling = enabled
                        plugin:saveConfig()
                        local RakuyomiPatch = rawget(_G, "__ZEN_UI_RAKUYOMI")
                        if type(RakuyomiPatch) == "table"
                                and type(RakuyomiPatch.applyReversePageScrollingToCurrentReader) == "function" then
                            RakuyomiPatch.applyReversePageScrollingToCurrentReader(enabled)
                        end
                        if touchmenu_instance then touchmenu_instance:updateItems() end
                    end,
                },
            },
        })
    end

    local global_items = global_settings.build_extras_items(ctx)
    for _i, item in ipairs(global_items) do
        table.insert(items, item)
    end

     table.insert(items, {
        text = _("Include new books in TBR"),
        help_text = _("New includes unread books and books modified since they were last opened."),
        checked_func = function()
            return type(config.group_view) == "table"
                and config.group_view.include_new_in_tbr == true
        end,
        callback = function(touchmenu_instance)
            if type(config.group_view) ~= "table" then config.group_view = {} end
            config.group_view.include_new_in_tbr =
                config.group_view.include_new_in_tbr ~= true
            plugin:saveConfig()
            local home = SharedState.get(plugin, "home")
            if home and home.rebuildActive then
                home.rebuildActive()
            end
            if touchmenu_instance then touchmenu_instance:updateItems() end
        end,
    })

    table.insert(items, {
        text = _("Allow custom icons"),
        help_text = _("When enabled, icons placed in KOReader's user icons folder override the bundled Zen UI icons. Falls back to Zen UI icons, then KOReader built-ins."),
        checked_func = function()
            return config.features.custom_icons_enabled == true
        end,
        callback = function()
            config.features.custom_icons_enabled = config.features.custom_icons_enabled ~= true
            plugin:saveConfig()
            settings_apply.prompt_restart()
        end,
    })

    return items
end

return M
