local function apply_favorites()
    local FileManagerCollection = require("apps/filemanager/filemanagercollection")
    local Menu = require("ui/widget/menu")

    local zen_plugin = rawget(_G, "__ZEN_UI_PLUGIN")
    if not zen_plugin or type(zen_plugin.config) ~= "table" then
        return
    end

    local function is_enabled()
        local features = zen_plugin.config and zen_plugin.config.features
        return type(features) == "table" and features.favorites == true
    end

    -- Returns true when status_bar is enabled AND hide_browser_bar is true
    -- (matching what status_bar.lua does when creating the filebrowser titlebar).
    -- In that mode the filebrowser has a minimal-height TitleBar, and we must
    -- give favorites the exact same height so covers line up.
    local function should_match_statusbar_height()
        local features = zen_plugin.config and zen_plugin.config.features
        if type(features) ~= "table" or features.status_bar ~= true then
            return false
        end
        local sb_cfg = type(zen_plugin.config.status_bar) == "table"
            and zen_plugin.config.status_bar or {}
        -- Default for hide_browser_bar is true (matches status_bar config_default)
        local hide = sb_cfg.hide_browser_bar
        return hide == true or hide == nil
    end

    -- Hook Menu:init() so the favorites BookList TitleBar is created with the
    -- same minimal height as the filebrowser TitleBar (status_bar + hide_browser_bar
    -- case).  This makes others_height equal in both views so the first cover
    -- row appears at the same Y position — covers "line up" when switching tabs.
    --
    -- favorites is applied after navbar in FEATURES, so our wrapper
    -- is the outermost hook.  We temporarily patch TitleBar.new exactly the
    -- same way status_bar.lua does for FileManager.setupLayout.
    local orig_menu_init = Menu.init
    function Menu:init()
        if self.name == "collections" and is_enabled() and should_match_statusbar_height() then
            local TitleBar   = require("ui/widget/titlebar")
            local orig_tb_new = TitleBar.new
            TitleBar.new = function(cls, t)
                if type(t) == "table" then
                    t.subtitle                = nil
                    t.subtitle_fullwidth      = nil
                    t.left_icon               = nil
                    t.left_icon_tap_callback  = nil
                    t.left_icon_hold_callback = nil
                    t.right_icon              = nil
                    t.right_icon_tap_callback  = nil
                    t.right_icon_hold_callback = nil
                    t.close_callback          = nil   -- prevents TitleBar:init re-adding right "close" icon
                    t.title_tap_callback      = nil
                    t.title_hold_callback     = nil
                    t.bottom_v_padding        = 0
                    t.title                   = " "  -- same placeholder used by status_bar
                end
                return orig_tb_new(cls, t)
            end
            orig_menu_init(self)
            TitleBar.new = orig_tb_new
        else
            orig_menu_init(self)
        end
    end

    local function clean_nav(menu)
        if not menu then return end

        -- === Fix partial-row left-alignment ===
        -- CoverBrowser sets _do_center_partial_rows = true on the FIRST call to
        -- updateItemTable (inside its _coverbrowser_overridden setup block), which
        -- runs before this function.  Setting the flag false here and rebuilding
        -- items ensures the first *painted* frame is left-aligned.  Subsequent
        -- renders are handled by the updateItemTable hook below.
        menu._do_center_partial_rows = false
        local UIManager = require("ui/uimanager")
        menu:updateItems(1, true)

        -- === Permanently suppress the back-arrow button ===
        -- Must come AFTER updateItems() — updatePageInfo() (called by updateItems)
        -- runs page_return_arrow:showHide(onReturn ~= nil) which would re-show the
        -- arrow on every scroll if we only called hide().
        -- Fix: override show/showHide on the instance so it can never be made
        -- visible again, and zero its dimen so taps pass through it.
        local arrow = menu.page_return_arrow
        if arrow then
            local Geom = require("ui/geometry")
            arrow:hide()
            arrow.show     = function() end  -- neutered: show() is a permanent no-op
            arrow.showHide = function() end  -- neutered: showHide() is a permanent no-op
            arrow.dimen    = Geom:new{ w = 0, h = 0 }
        end

        -- === Swipe south from top → open KOReader menu (mirrors library behavior) ===
        -- The BookList is a standalone overlay so FileManager's FileManagerMenu
        -- event handlers are never reached from here.  Intercept south swipes
        -- that start in the top eighth of the screen and delegate to
        -- FileManagerMenu:onShowMenu(), same as the library does.
        local Device     = require("device")
        local Menu_class = require("ui/widget/menu")
        local orig_onSwipe = Menu_class.onSwipe
        menu.onSwipe = function(self_m, arg, ges_ev)
            if ges_ev.direction == "south" then
                if ges_ev.pos.y < Device.screen:getHeight() / 8 then
                    local fm = require("apps/filemanager/filemanager").instance
                    if fm and fm.menu then
                        local fm_menu = fm.menu
                        if fm_menu.activation_menu ~= "tap" then
                            fm_menu:onShowMenu(fm_menu:_getTabIndexFromLocation(ges_ev))
                            return true
                        end
                    end
                end
                -- Swallow all other south swipes — do not close favorites.
                return true
            end
            return orig_onSwipe(self_m, arg, ges_ev)
        end

        local tb = menu.title_bar
        if not tb then return end

        -- === Title-bar content ===
        local createStatusRow = zen_plugin._zen_shared
            and zen_plugin._zen_shared.createStatusRow

        if createStatusRow and tb.title_group and #tb.title_group >= 2 then
            local FileManager = require("apps/filemanager/filemanager")

            -- Build the status row (nil path → no back-chevron / folder name).
            local status_row = createStatusRow(nil, FileManager.instance)

            -- Replace the title widget with the status row in-place, same as
            -- FileManager:_updateStatusBar() does for the library view.
            tb.title_group[2] = status_row
            tb.title_group:resetLayout()

            -- Remove icon buttons from the TitleBar OverlapGroup so they no
            -- longer paint or intercept touches (they may be nil when the
            -- titlebar was created with the minimal wrapper above).
            local function remove_from_overlap(group, widget)
                if not widget then return end
                for i = #group, 1, -1 do
                    if rawequal(group[i], widget) then
                        table.remove(group, i)
                        return
                    end
                end
            end
            remove_from_overlap(tb, tb.left_button)
            remove_from_overlap(tb, tb.right_button)
            tb.has_left_icon  = false
            tb.has_right_icon = false

            UIManager:setDirty(menu, "ui", tb.dimen)
            -- Clock refresh is handled centrally by status_bar.lua's autoRefresh.
        else
            -- Fallback when status_bar is not active: swap hamburger → star icon.
            if tb.setLeftIcon then tb:setLeftIcon("zen_favorites") end
        end
    end

    -- Prevent centering on *subsequent* updateItemTable calls (refreshes, page
    -- turns).  On the first call CoverBrowser's setup block always runs after
    -- this wrapper and re-sets the flag to true; clean_nav() corrects that via
    -- a manual updateItems() call after the initial build.
    local orig_updateItemTable = FileManagerCollection.updateItemTable
    function FileManagerCollection:updateItemTable(...)
        if is_enabled() and self.booklist_menu then
            self.booklist_menu._do_center_partial_rows = false
        end
        return orig_updateItemTable(self, ...)
    end

    local orig_onShowColl = FileManagerCollection.onShowColl
    function FileManagerCollection:onShowColl(collection_name)
        -- Sync the collection display mode to match the filemanager (library)
        -- display mode BEFORE orig_onShowColl runs, because that call creates
        -- booklist_menu and immediately calls updateItemTable — which is when
        -- CoverBrowser patches the instance with mosaic/list overrides.
        -- We must set the correct mode before that first patching happens.
        if is_enabled() and self.ui then
            local coverbrowser = self.ui.coverbrowser
            if coverbrowser and type(coverbrowser.setupWidgetDisplayMode) == "function" then
                local BookInfoManager = require("bookinfomanager")
                local fm_mode   = BookInfoManager:getSetting("filemanager_display_mode")
                local coll_mode = BookInfoManager:getSetting("collection_display_mode")
                if fm_mode ~= coll_mode then
                    coverbrowser.setupWidgetDisplayMode("collections", fm_mode)
                end
            end
        end
        orig_onShowColl(self, collection_name)
        if not is_enabled() then return end
        clean_nav(self.booklist_menu)
    end

end

return apply_favorites
