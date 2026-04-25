local _ = require("gettext")
local UIManager = require("ui/uimanager")

local settings_apply = require("modules/settings/zen_settings_apply")
local updater        = require("modules/settings/zen_updater")
local utils          = require("modules/settings/zen_settings_utils")

local lib_section      = require("modules/settings/sections/library_settings")
local navbar_section   = require("modules/settings/sections/library_settings/navbar_settings")
local menu_section     = require("modules/settings/sections/menu_settings")
local reader_section   = require("modules/settings/sections/reader_settings")
local global_section   = require("modules/settings/sections/global_settings")
local advanced_section = require("modules/settings/sections/advanced_settings")
local about_section    = require("modules/settings/sections/about_settings")

local M = {}

function M.build(plugin)
    -- Lazy one-shot update check (cached; silent if offline or on failure).
    updater.check_for_update()

    local config = plugin.config

    local function apply_feature(feature)
        local enabled = config.features[feature] == true
        settings_apply.apply_feature_toggle(plugin, feature, enabled)
    end

    local function save_and_apply(feature)
        plugin:saveConfig()
        apply_feature(feature)
    end

    local ctx = {
        plugin         = plugin,
        config         = config,
        save_and_apply = save_and_apply,
        apply_feature  = apply_feature,
        settings_apply = settings_apply,
    }

    local filebrowser_items    = lib_section.build(ctx)
    local navbar_item          = navbar_section.build(ctx)
    local quick_settings_item  = menu_section.build(ctx)
    local reader_items         = reader_section.build(ctx)
    local global_items      = global_section.build(ctx)
    local advanced_items    = advanced_section.build(ctx)
    local general_items     = about_section.build(ctx)

    table.insert(general_items, {
        text = _("Quit KOReader"),
        separator = true,
        callback = function()
            UIManager:show(require("ui/widget/confirmbox"):new{
                text = _("Are you sure you want to quit KOReader?"),
                ok_text = _("Quit"),
                ok_callback = function()
                    UIManager:broadcastEvent(require("ui/event"):new("Exit"))
                end,
            })
        end,
    })
    table.insert(general_items, updater.build_channel_item())
    table.insert(general_items, updater.build_update_now_item(plugin))

    -- -------------------------------------------------------------------------
    -- Item ordering
    -- -------------------------------------------------------------------------

    filebrowser_items = utils.order_items_by_text(filebrowser_items, {
        _("Display mode"),
        _("Items per page"),
        _("Sort by"),
        _("Status bar"),
    })

    utils.reorder_nested_items_by_text(filebrowser_items, _("Status bar"), {
        _("Enable custom status bar"),
        _("12-hour time"),
        _("Show bottom border"),
        _("Bold text"),
        _("Colored status icons"),
        _("Left items"),
        _("Center items"),
        _("Right items"),
    })

    utils.reorder_nested_items_by_text({ navbar_item }, _("Navbar"), {
        _("Tabs"),
        _("Styling"),
        _("Show labels"),
    })

    utils.reorder_nested_items_by_text({ navbar_item }, _("Tabs"), {
        _("Visibility"),
        _("Arrange tabs"),
    })

    utils.reorder_nested_items_by_text({ navbar_item }, _("Styling"), {
        _("Show top border"),
        _("Active tab styling"),
        _("Bold active tab"),
        _("Active tab underline"),
        _("Underline above icon"),
        _("Colored active tab"),
        _("Active tab color"),
        _("Refresh navbar"),
    })

    -- -------------------------------------------------------------------------
    -- Root menu assembly
    -- -------------------------------------------------------------------------

    local root_items = {
        {
            text = _("Zen Mode"),
            checked_func = function()
                return config.features["zen_mode"] == true
            end,
            callback = function()
                config.features["zen_mode"] = not (config.features["zen_mode"] == true)
                save_and_apply("zen_mode")
            end,
        },
        quick_settings_item,
        { text = _("Library"),  sub_item_table = filebrowser_items },
        navbar_item,
        { text = _("Reader"),   sub_item_table = reader_items      },
        { text = _("Global"),   sub_item_table = global_items      },
        { text = _("Advanced"), sub_item_table = advanced_items    },
        {
            text = _("About"),
            sub_item_table = general_items,
        },
    }

    -- Insert banner if an update is already known.
    local update_banner = updater.build_update_available_item(plugin)
    if update_banner then
        table.insert(root_items, 1, update_banner)
    end

    -- KOReader reuses tab_item_table across menu open/close cycles, so
    -- setUpdateItemTable (and build()) only runs once per session. The
    -- tab callback fires on every switchMenuTab call — including when the
    -- menu reopens — letting us keep the banner current in-place.
    root_items.callback = function()
        if root_items[1] and root_items[1]._zen_update_banner then
            table.remove(root_items, 1)
        end
        local banner = updater.build_update_available_item(plugin)
        if banner then
            table.insert(root_items, 1, banner)
        end
    end

    -- fires when navigating back from a submenu (e.g. About after manual check).
    root_items.needs_refresh = true
    root_items.refresh_func  = function()
        return M.build(plugin).sub_item_table
    end

    return {
        text = _("Zen UI"),
        sub_item_table = root_items,
    }
end

return M
