local function apply_quick_settings()
    -- Quick Settings tab for KOReader top menu
    -- Adds a new tab at the far left with Wi-Fi, action buttons, and frontlight/warmth sliders.
    -- Works in both File Manager and Book Reader views.
    -- Additional buttons for the Quick Settings tab.
    -- Adds optional buttons for OPDS Catalog, NotionSync, and Reading Streak.
    -- OPDS Catalog is included with KOReader and allows browsing OPDS book catalogs.
    -- NotionSync plugin by Cezary Pukownik: https://github.com/CezaryPukownik/notionsync.koplugin
    -- Reading Streak plugin by advokatb: https://github.com/advokatb/readingstreak.koplugin

    local Blitbuffer = require("ffi/blitbuffer")
    local CenterContainer = require("ui/widget/container/centercontainer")
    local Device = require("device")
    local Event = require("ui/event")
    local Font = require("ui/font")
    local FrameContainer = require("ui/widget/container/framecontainer")
    local Geom = require("ui/geometry")
    local HorizontalGroup = require("ui/widget/horizontalgroup")
    local HorizontalSpan = require("ui/widget/horizontalspan")
    local IconWidget = require("ui/widget/iconwidget")
    local NetworkMgr = require("ui/network/manager")
    local Button = require("ui/widget/button")
    local ConfirmBox = require("ui/widget/confirmbox")
    local TextWidget = require("ui/widget/textwidget")
    local UIManager = require("ui/uimanager")
    local ZenSlider = require("common/zen_slider")
    local ZenToggle = require("common/zen_toggle")
    local VerticalGroup = require("ui/widget/verticalgroup")
    local VerticalSpan = require("ui/widget/verticalspan")
    local utils = require("common/utils")
    local build_brightness_slider = require("modules/menu/patches/brightness_slider")
    local build_warmth_slider     = require("modules/menu/patches/warmth_slider")
    local _ = require("gettext")
    local Screen = Device.screen

    local zen_plugin = rawget(_G, "__ZEN_UI_PLUGIN")
    if not zen_plugin or type(zen_plugin.config) ~= "table" then
        return
    end

    -- Resolve plugin icons/ dir from this file's path at apply-time.
    local _icons_dir
    do
        local src = debug.getinfo(1, "S").source or ""
        if src:sub(1,1) == "@" then
            local root = src:sub(2):match("^(.*)/modules/")
            if root then _icons_dir = root .. "/icons/" end
        end
    end

    local function is_enabled()
        local features = zen_plugin.config and zen_plugin.config.features
        return type(features) == "table" and features.quick_settings == true
    end

    -- ============================================================
    -- Configuration
    -- ============================================================

    local config_default = {
        button_order = { "wifi", "night", "rotate", "zen", "usb", "search", "quickrss", "cloud", "zlibrary", "calibre", "notion", "streak", "opds", "filebrowser", "restart", "exit", "sleep" },
        show_buttons = {
            wifi = true,
            night = true,
            rotate = true,
            zen = true,
            usb = false,
            search = false,
            quickrss = false,
            cloud = false,
            zlibrary = false,
            calibre = false,
            restart = true,
            exit = true,
            sleep = true,
            -- External plugin buttons (disabled by default; enable if plugin is installed)
            notion = false,
            streak = false,
            opds = false,
            filebrowser = false,
        },
        show_frontlight = true,
        show_warmth = true,
        open_on_start = false,
    }

    local config

    local function loadConfig()
        config = zen_plugin.config.quick_settings or {}
        for k, v in pairs(config_default) do
            if config[k] == nil then
                config[k] = utils.deepcopy(v)
            end
        end
        if type(config.show_buttons) == "table" then
            for k, v in pairs(config_default.show_buttons) do
                if config.show_buttons[k] == nil then
                    config.show_buttons[k] = v
                end
            end
        else
            config.show_buttons = utils.deepcopy(config_default.show_buttons)
        end
        if type(config.button_order) ~= "table" then
            config.button_order = utils.deepcopy(config_default.button_order)
        else
            -- Ensure all known buttons are in the order list
            local known = {}
            for _, id in ipairs(config.button_order) do
                known[id] = true
            end
            for _, id in ipairs(config_default.button_order) do
                if not known[id] then
                    table.insert(config.button_order, id)
                end
            end
        end
        zen_plugin.config.quick_settings = config
    end

    local function saveConfig()
        zen_plugin.config.quick_settings = config
        if zen_plugin.saveConfig then
            zen_plugin:saveConfig()
        end
    end

    local function getStatusBarConfig()
        if type(zen_plugin.config.status_bar) ~= "table" then
            zen_plugin.config.status_bar = {}
        end
        return zen_plugin.config.status_bar
    end

    loadConfig()

    -- ============================================================
    -- Button definitions (data-driven)
    -- ============================================================

    local button_defs = {
        wifi = {
            icon = "quick_wifi",
            label = _("Wi-Fi"),
            label_func = function()
                if NetworkMgr:isWifiOn() then
                    local net = NetworkMgr:getCurrentNetwork()
                    if net and net.ssid then
                        return net.ssid
                    end
                end
                return _("Wi-Fi")
            end,
            active_func = function() return NetworkMgr:isWifiOn() end,
            callback = function(touch_menu)
                if NetworkMgr:isWifiOn() then
                    NetworkMgr:toggleWifiOff()
                else
                    NetworkMgr:toggleWifiOn()
                end
                UIManager:scheduleIn(1, function()
                    if touch_menu.item_table and touch_menu.item_table.panel then
                        touch_menu:updateItems(1)
                    end
                end)
            end,
            hold_callback = function(touch_menu)
                -- Long-hold: (re)connect and show the AP picker.
                -- If Wi-Fi is currently on, turn it off first, then bring it
                -- back up with long_press=true so the network list appears.
                -- If already off, go straight to the long-press connect flow.
                local function do_connect()
                    NetworkMgr:toggleWifiOn(function()
                        UIManager:scheduleIn(0.5, function()
                            if touch_menu.item_table and touch_menu.item_table.panel then
                                touch_menu:updateItems(1)
                            end
                        end)
                    end, true, true)
                end
                if NetworkMgr:isWifiOn() then
                    NetworkMgr:toggleWifiOff(function()
                        do_connect()
                    end, true)
                else
                    do_connect()
                end
            end,
        },
        night = {
            icon = "quick_nightmode",
            label = _("Night"),
            active_func = function() return G_reader_settings:isTrue("night_mode") end,
            callback = function(touch_menu)
                local night_mode = G_reader_settings:isTrue("night_mode")
                Screen:toggleNightMode()
                UIManager:ToggleNightMode(not night_mode)
                G_reader_settings:saveSetting("night_mode", not night_mode)
                touch_menu:updateItems(1)
                UIManager:setDirty("all", "full")
            end,
        },
        rotate = {
            icon = "quick_rotate",
            label = _("Rotate"),
            callback = function()
                UIManager:broadcastEvent(Event:new("SwapRotation"))
            end,
        },
        usb = {
            icon = "quick_usb",
            label = _("USB"),
            callback = function()
                if Device:canToggleMassStorage() then
                    UIManager:broadcastEvent(Event:new("RequestUSBMS"))
                end
            end,
        },
        restart = {
            icon = "quick_restart",
            label = _("Restart"),
            callback = function()
                UIManager:show(ConfirmBox:new{
                    text = _("Are you sure you want to restart KOReader?"),
                    ok_text = _("Restart"),
                    ok_callback = function()
                        UIManager:broadcastEvent(Event:new("Restart"))
                    end,
                })
            end,
        },
        exit = {
            icon = "quick_exit",
            label = _("Exit"),
            callback = function()
                UIManager:show(ConfirmBox:new{
                    text = _("Are you sure you want to exit KOReader?"),
                    ok_text = _("Exit"),
                    ok_callback = function()
                        UIManager:broadcastEvent(Event:new("Exit"))
                    end,
                })
            end,
        },
        sleep = {
            icon = "quick_sleep",
            label = _("Sleep"),
            callback = function()
                if Device:canSuspend() then
                    UIManager:broadcastEvent(Event:new("RequestSuspend"))
                elseif Device:canPowerOff() then
                    UIManager:broadcastEvent(Event:new("RequestPowerOff"))
                end
            end,
        },
        search = {
            icon = "quick_search",
            label = _("Search"),
            callback = function()
                UIManager:broadcastEvent(Event:new("ShowFileSearch"))
            end,
        },
        quickrss = {
            icon = "quick_quickrss",
            label = _("QuickRSS"),
            callback = function()
                local ok, QuickRSSUI = pcall(require, "modules/ui/feed_view")
                if ok and QuickRSSUI then
                    local view = QuickRSSUI:new{}
                    UIManager:show(view)
                    view:_fetch()
                else
                    local InfoMessage = require("ui/widget/infomessage")
                    UIManager:show(InfoMessage:new{
                        text = _("QuickRSS plugin is not installed."),
                    })
                end
            end,
        },
        cloud = {
            icon = "quick_cloud",
            label = _("Cloud"),
            callback = function()
                UIManager:broadcastEvent(Event:new("ShowCloudStorage"))
            end,
        },
        zlibrary = {
            icon = "quick_zlib",
            label = _("Z-Lib"),
            callback = function()
                UIManager:broadcastEvent(Event:new("ZlibrarySearch"))
            end,
        },
        calibre = {
            icon = "quick_calibre",
            label = _("Calibre"),
            active_func = function()
                local CW = package.loaded["wireless"]
                return CW ~= nil and CW.calibre_socket ~= nil
            end,
            callback = function(touch_menu)
                local CW = package.loaded["wireless"]
                if CW and CW.calibre_socket ~= nil then
                    UIManager:broadcastEvent(Event:new("CloseWirelessConnection"))
                else
                    UIManager:broadcastEvent(Event:new("StartWirelessConnection"))
                end
                UIManager:scheduleIn(1, function()
                    touch_menu:updateItems(1)
                end)
            end,
        },
    	notion = {
            icon = "quick_notion",
            label = _("NotionSync"),
            callback = function()
                local ok_r, ReaderUI = pcall(require, "apps/reader/readerui")
                local ok_f, FileManager = pcall(require, "apps/filemanager/filemanager")
                local ui = (ok_r and ReaderUI.instance) or (ok_f and FileManager.instance)
                if ui and ui.NotionSync then
                    ui.NotionSync:onSyncAllBooksRequested()
                end
            end,
        },
        streak = {
            icon = "quick_streak",
            label = _("Streak"),
            callback = function()
                UIManager:broadcastEvent(Event:new("ShowReadingStreakCalendar"))
            end,
        },
        opds = {
            icon = "quick_opds",
            label = _("OPDS"),
            callback = function()
                UIManager:broadcastEvent(Event:new("ShowOPDSCatalog"))
            end,
        },
        zen = {
            icon = "quick_zen",
            label = _("Zen"),
            active_func = function()
                local features = zen_plugin.config and zen_plugin.config.features
                return type(features) == "table" and features.zen_mode == true
            end,
            callback = function()
                local features = zen_plugin.config and zen_plugin.config.features
                if type(features) == "table" then
                    features.zen_mode = not features.zen_mode
                    if zen_plugin.saveConfig then
                        zen_plugin:saveConfig()
                    end
                end
                UIManager:show(ConfirmBox:new{
                    text = _("This change requires a restart to take effect."),
                    ok_text = _("Restart now"),
                    cancel_text = _("Later"),
                    ok_callback = function()
                        UIManager:broadcastEvent(Event:new("Restart"))
                    end,
                })
            end,
        },
        filebrowser = {
            icon = "quick_opds",
            label = _("FileBrowser"),
            active_func = function()
                -- Fast check: just test if the pidfile exists
                local pid_path = "/tmp/filebrowser_koreader.pid"
                local f = io.open(pid_path, "r")
                if f then f:close() return true end
                return false
            end,
            callback = function(touch_menu)
                local ok_f, FileManager = pcall(require, "apps/filemanager/filemanager")
                local ok_r, ReaderUI = pcall(require, "apps/reader/readerui")
                local ui = (ok_f and FileManager.instance) or (ok_r and ReaderUI.instance)
                if ui and ui.filebrowser then
                    ui.filebrowser:onToggleFilebrowser()
                    UIManager:scheduleIn(1.5, function()
                        if touch_menu.item_table and touch_menu.item_table.panel then
                            touch_menu:updateItems(1)
                        end
                    end)
                else
                    local InfoMessage = require("ui/widget/infomessage")
                    UIManager:show(InfoMessage:new{
                        text = _("Filebrowser plugin is not installed."),
                    })
                end
            end,
        },

    }

    -- ============================================================
    -- Panel builder — returns panel widget + refs for tap handling
    -- ============================================================

    local function createQuickSettingsPanel(touch_menu)
        local panel_width = touch_menu.item_width
        local padding = Screen:scaleBySize(10)
        local inner_width = panel_width - padding * 2
        local powerd = Device:getPowerDevice()

        -- Refs table: stored on touch_menu for gesture handling
        local refs = { buttons = {}, sliders = {}, toggles = {} }

        -- ----- Top row: action buttons -----

        -- Collect visible buttons in order
        local visible_buttons = {}
        for _, id in ipairs(config.button_order) do
            if config.show_buttons[id] and button_defs[id] then
                table.insert(visible_buttons, { id = id, def = button_defs[id] })
            end
        end

        local num_buttons = #visible_buttons
        local action_btn_size = Screen:scaleBySize(64)
        local icon_size = math.floor(action_btn_size * 0.5)
        local label_font = Font:getFace("xx_smallinfofont")

        -- Active styling
        local normal_border = Screen:scaleBySize(2)

        local function makeActionButton(icon_name, label_text, active)
            local icon_path = _icons_dir and utils.resolveLocalIcon(_icons_dir, icon_name)
            local icon = IconWidget:new{
                file   = icon_path or nil,
                icon   = icon_path and nil or icon_name,
                width  = icon_size,
                height = icon_size,
                -- alpha=false → BlitBuffer8 (opaque grayscale); invertRect flips
                -- pixel values so the icon renders white-on-black for active state.
                alpha  = not active,
            }
            if active then
                -- Force the cached buffer to be populated, then copy it before
                -- inverting so the shared cache entry is never mutated (otherwise
                -- invertRect would flip back on every second open).
                icon:_render()
                if icon._bb then
                    local bb_copy = icon._bb:copy()
                    bb_copy:invertRect(0, 0, bb_copy:getWidth(), bb_copy:getHeight())
                    icon._bb = bb_copy
                end
            end
            local border = active and 0 or normal_border
            local circle = FrameContainer:new{
                width      = action_btn_size,
                height     = action_btn_size,
                radius     = math.floor(action_btn_size / 2),
                bordersize = border,
                background = active and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_WHITE,
                padding    = 0,
                CenterContainer:new{
                    dimen = Geom:new{
                        w = action_btn_size - border * 2,
                        h = action_btn_size - border * 2,
                    },
                    icon,
                },
            }
            local label = TextWidget:new{
                text = label_text,
                face = label_font,
                max_width = action_btn_size + Screen:scaleBySize(4),
            }
            local group = VerticalGroup:new{
                align = "center",
                circle,
                VerticalSpan:new{ width = Screen:scaleBySize(2) },
                label,
            }
            return group, circle
        end

        -- Build button row
        local top_row = HorizontalGroup:new{ align = "center" }

        if num_buttons > 0 then
            local btn_gap = math.floor((inner_width - num_buttons * action_btn_size) / math.max(num_buttons - 1, 1))

            for i, entry in ipairs(visible_buttons) do
                local def = entry.def
                local label_text = def.label
                if def.label_func then
                    label_text = def.label_func()
                end
                local active = def.active_func and def.active_func() or false
                local btn_widget, btn_circle = makeActionButton(def.icon, label_text, active)

                table.insert(refs.buttons, {
                    widget = btn_circle,
                    callback = function()
                        def.callback(touch_menu)
                    end,
                    hold_callback = def.hold_callback and function()
                        def.hold_callback(touch_menu)
                    end or nil,
                })

                table.insert(top_row, btn_widget)
                if i < num_buttons then
                    table.insert(top_row, HorizontalSpan:new{ width = btn_gap })
                end
            end
        end

        -- ----- Frontlight / warmth sliders -----

        local medium_font     = Font:getFace("ffont")
        local small_btn_size  = Screen:scaleBySize(14)
        local small_btn_width = Screen:scaleBySize(56)
        local toggle_width    = Screen:scaleBySize(56)
        local slider_gap      = Screen:scaleBySize(4)
        local slider_width    = inner_width - 2 * small_btn_width - 2 * slider_gap

        local slider_opts = {
            inner_width     = inner_width,
            slider_width    = slider_width,
            small_btn_width = small_btn_width,
            toggle_width    = toggle_width,
            slider_gap      = slider_gap,
            medium_font     = medium_font,
            small_btn_size  = small_btn_size,
            powerd          = powerd,
            refs            = refs,
        }

        local fl_group = VerticalGroup:new{ align = "center" }
        if config.show_frontlight then
            fl_group = build_brightness_slider(touch_menu, slider_opts)
        end

        local warmth_group = VerticalGroup:new{ align = "center" }
        if config.show_warmth and Device:hasNaturalLight() then
            warmth_group = build_warmth_slider(touch_menu, slider_opts)
        end

        -- ----- Status bar row (reuses status_bar component when that feature is active) -----

        local _zen_shared = zen_plugin._zen_shared
        local status_row  = _zen_shared
            and type(_zen_shared.buildStatusRow) == "function"
            and _zen_shared.buildStatusRow(panel_width, {
                padding   = Screen:scaleBySize(6),
                font_name = "x_smallinfofont",
            })

        -- ----- Assemble panel -----

        local panel = VerticalGroup:new{
            align = "center",
            VerticalSpan:new{ width = Screen:scaleBySize(8) },
        }

        if status_row then
            table.insert(panel, status_row)
            table.insert(panel, VerticalSpan:new{ width = Screen:scaleBySize(8) })
        end

        if num_buttons > 0 then
            table.insert(panel, CenterContainer:new{
                dimen = Geom:new{ w = panel_width, h = top_row:getSize().h },
                top_row,
            })
            table.insert(panel, VerticalSpan:new{ width = Screen:scaleBySize(8) })
        end

        if #fl_group > 0 then
            table.insert(panel, fl_group)
        end
        if #warmth_group > 0 then
            table.insert(panel, warmth_group)
        end
        table.insert(panel, VerticalSpan:new{ width = Screen:scaleBySize(8) })

        -- Store refs on the touch_menu for gesture handlers
        touch_menu._qs_refs = refs

        return panel
    end

    -- ============================================================
    -- Gesture handler for panel taps/pans
    -- ============================================================

    local function handlePanelGesture(touch_menu, ges, is_hold)
        local refs = touch_menu._qs_refs
        if not refs then return false end

        -- Check sliders for taps (not holds)
        if not is_hold then
            for _, sr in ipairs(refs.sliders or {}) do
                if sr.slider:handleTap(ges) then return true end
            end
        end

        -- Check toggles (tap only)
        if not is_hold then
            for _, tr in ipairs(refs.toggles or {}) do
                if tr.toggle.dimen and ges.pos:intersectWith(tr.toggle.dimen) then
                    tr.callback()
                    return true
                end
            end
        end

        -- Check buttons
        for _, btn_ref in ipairs(refs.buttons) do
            if btn_ref.widget.dimen and ges.pos:intersectWith(btn_ref.widget.dimen) then
                if is_hold and btn_ref.hold_callback then
                    btn_ref.hold_callback()
                    return true
                elseif not is_hold then
                    btn_ref.callback()
                    return true
                end
                -- hold with no hold_callback: don't consume, let it fall through
                return false
            end
        end

        return false
    end

    -- ============================================================
    -- Hook TouchMenu to support panel tabs
    -- ============================================================

    local TouchMenu = require("ui/widget/touchmenu")
    local FocusManager = require("ui/widget/focusmanager")
    local datetime = require("datetime")
    local BD = require("ui/bidi")

    -- Hook init to force tab 1 before bar:switchToTab runs when open_on_start
    local GestureRange = require("ui/gesturerange")
    local orig_init = TouchMenu.init
    function TouchMenu:init()
        if is_enabled() and config.open_on_start then
            self.last_index = 1
        end
        orig_init(self)
        -- Register a screen-wide hold gesture for panel button hold_callbacks
        if is_enabled() then
            self.ges_events.HoldCloseAllMenus = {
                GestureRange:new{
                    ges = "hold",
                    range = Geom:new{ x = 0, y = 0, w = self.screen_size.w, h = self.screen_size.h },
                }
            }
            self.ges_events.PanCloseAllMenus = {
                GestureRange:new{
                    ges = "pan",
                    range = Geom:new{ x = 0, y = 0, w = self.screen_size.w, h = self.screen_size.h },
                }
            }
            self.ges_events.PanReleaseCloseAllMenus = {
                GestureRange:new{
                    ges = "pan_release",
                    range = Geom:new{ x = 0, y = 0, w = self.screen_size.w, h = self.screen_size.h },
                }
            }
            self.ges_events.MultiSwipe = {
                GestureRange:new{
                    ges = "multiswipe",
                    range = Geom:new{ x = 0, y = 0, w = self.screen_size.w, h = self.screen_size.h },
                }
            }
        end
    end

    -- Hook updateItems for panel rendering
    local orig_updateItems = TouchMenu.updateItems

    function TouchMenu:updateItems(target_page, target_item_id)
        if not is_enabled() then
            self._qs_refs = nil
            return orig_updateItems(self, target_page, target_item_id)
        end

        if not self.item_table or not self.item_table.panel then
            local _shared = zen_plugin._zen_shared
            if _shared and type(_shared.cancelPanelRefresh) == "function" then
                _shared.cancelPanelRefresh(self)
            end
            self._qs_refs = nil -- clear refs when switching away from panel tab
            return orig_updateItems(self, target_page, target_item_id)
        end

        -- Custom panel mode: render the panel widget instead of menu items
        -- Lock sliders briefly whenever we (re-)enter panel mode so the
        -- southward swipe that opens the menu cannot accidentally move the
        -- slider before the user intentionally touches it.
        if not self._qs_refs then
            self._qs_slider_locked = true
            UIManager:scheduleIn(0.35, function()
                self._qs_slider_locked = false
            end)
        end
        self.item_group:clear()
        self.layout = {}
        table.insert(self.item_group, self.bar)
        table.insert(self.layout, self.bar.icon_widgets)

        -- Build panel (also sets self._qs_refs)
        local panel_fn = self.item_table.panel
        local panel = type(panel_fn) == "function" and panel_fn(self) or panel_fn
        table.insert(self.item_group, panel)

        -- Footer (no pagination)
        table.insert(self.item_group, self.footer_top_margin)
        table.insert(self.item_group, self.footer)
        self.page_info_text:setText("")
        self.page_info_left_chev:showHide(false)
        self.page_info_right_chev:showHide(false)

        -- Schedule 60-second status row refresh (status_bar component owns the clock)
        local _shared = zen_plugin._zen_shared
        if _shared and type(_shared.schedulePanelRefresh) == "function" then
            _shared.schedulePanelRefresh(self)
        end

        -- Recalculate dimen
        local old_dimen = self.dimen:copy()
        self.dimen.w = self.width
        self.dimen.h = self.item_group:getSize().h + self.bordersize * 2 + self.padding
        self:moveFocusTo(self.cur_tab, 1, FocusManager.NOT_FOCUS)

        local keep_bg = old_dimen and self.dimen.h >= old_dimen.h
        UIManager:setDirty((self.is_fresh or keep_bg) and self.show_parent or "all", function()
            local refresh_dimen = old_dimen and old_dimen:combine(self.dimen) or self.dimen
            local refresh_type = "ui"
            if self.is_fresh then
                refresh_type = "flashui"
                self.is_fresh = false
            end
            return refresh_type, refresh_dimen
        end)
    end

    -- Hook onTapCloseAllMenus to intercept taps on panel widgets
    local orig_onTapCloseAllMenus = TouchMenu.onTapCloseAllMenus

    function TouchMenu:onTapCloseAllMenus(arg, ges_ev)
        if not is_enabled() then
            return orig_onTapCloseAllMenus(self, arg, ges_ev)
        end

        if self._qs_refs and self.item_table and self.item_table.panel then
            if handlePanelGesture(self, ges_ev, false) then
                return true
            end
        end
        return orig_onTapCloseAllMenus(self, arg, ges_ev)
    end

    -- Hook onHoldCloseAllMenus to intercept holds on panel buttons
    function TouchMenu:onHoldCloseAllMenus(arg, ges_ev)
        if not is_enabled() then return end

        if self._qs_refs and self.item_table and self.item_table.panel then
            handlePanelGesture(self, ges_ev, true)
        end
        -- Holds outside the menu do nothing (don't close it)
        return true
    end

    -- Delegate all slider gesture types to ZenSlider, which owns the logic.
    ZenSlider.installTouchMenuHooks(TouchMenu, {
        in_panel_mode = function(tm)
            return is_enabled()
                and tm._qs_refs ~= nil
                and tm.item_table ~= nil
                and tm.item_table.panel ~= nil
        end,
        get_sliders = function(tm)
            local refs = tm._qs_refs
            if not refs then return {} end
            local sliders = {}
            for _, sr in ipairs(refs.sliders or {}) do
                table.insert(sliders, sr.slider)
            end
            return sliders
        end,
        is_locked           = function(tm) return tm._qs_slider_locked end,
        swipe_fallback      = function(tm, ges) handlePanelGesture(tm, ges, false) end,
        multiswipe_fallback = function(tm, ges) handlePanelGesture(tm, ges, false) end,
    })

    -- Hook switchMenuTab to force quick settings tab on menu open
    local orig_switchMenuTab = TouchMenu.switchMenuTab

    function TouchMenu:switchMenuTab(tab_num)
        orig_switchMenuTab(self, tab_num)
        if not is_enabled() then
            return
        end
        -- When "open on start" is enabled, always reset last_index to quick settings tab
        if config.open_on_start then
            self.last_index = 1
        end
    end

    -- Cancel status bar refresh timer when the menu is closed
    local orig_onCloseWidget = TouchMenu.onCloseWidget
    function TouchMenu:onCloseWidget()
        local _shared = zen_plugin._zen_shared
        if _shared and type(_shared.cancelPanelRefresh) == "function" then
            _shared.cancelPanelRefresh(self)
        end
        if orig_onCloseWidget then orig_onCloseWidget(self) end
    end

    -- Safety guards: onPrevPage / onNextPage crash when self.page is nil in
    -- panel mode (no pagination).  Consume silently.
    local orig_onPrevPage = TouchMenu.onPrevPage
    if orig_onPrevPage then
        function TouchMenu:onPrevPage()
            if is_enabled() and self.item_table and self.item_table.panel then
                return true
            end
            return orig_onPrevPage(self)
        end
    end

    local orig_onNextPage = TouchMenu.onNextPage
    if orig_onNextPage then
        function TouchMenu:onNextPage()
            if is_enabled() and self.item_table and self.item_table.panel then
                return true
            end
            return orig_onNextPage(self)
        end
    end

    -- ============================================================
    -- Quick Settings tab definition
    -- ============================================================

    local quick_settings_tab = {
        id = "quicksettings",
        icon = "quicksettings",
        remember = false,
        panel = createQuickSettingsPanel,
    }

    -- ============================================================
    -- Inject tab into both FileManager and Reader menus
    -- ============================================================

    local FileManagerMenu = require("apps/filemanager/filemanagermenu")
    local ReaderMenu = require("apps/reader/modules/readermenu")

    local orig_fm_setUpdateItemTable = FileManagerMenu.setUpdateItemTable

    function FileManagerMenu:setUpdateItemTable()
        orig_fm_setUpdateItemTable(self)
        if is_enabled() and self.tab_item_table then
            table.insert(self.tab_item_table, 1, quick_settings_tab)
        end
    end

    local orig_reader_setUpdateItemTable = ReaderMenu.setUpdateItemTable

    function ReaderMenu:setUpdateItemTable()
        orig_reader_setUpdateItemTable(self)
        if is_enabled() and self.tab_item_table then
            table.insert(self.tab_item_table, 1, quick_settings_tab)
        end
    end
end

return apply_quick_settings
