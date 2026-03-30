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
    local Math = require("optmath")
    local NetworkMgr = require("ui/network/manager")
    local Button = require("ui/widget/button")
    local ConfirmBox = require("ui/widget/confirmbox")
    local ButtonProgressWidget = require("ui/widget/buttonprogresswidget")
    local ProgressWidget = require("ui/widget/progresswidget")
    local TextWidget = require("ui/widget/textwidget")
    local UIManager = require("ui/uimanager")
    local VerticalGroup = require("ui/widget/verticalgroup")
    local VerticalSpan = require("ui/widget/verticalspan")
    local utils = require("common/utils")
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

    -- ============================================================
    -- Copy plugin icons into KOReader's user icons directory
    -- ============================================================
    -- TouchMenuBar only accepts icon *names* (no file= path support).
    -- KOReader's IconWidget checks DataStorage:getDataDir()..'/icons' first.
    -- We copy our two SVGs there once on startup (skip if already present)
    -- so names like 'zen_ui' resolve to our local files after a restart.
    if _icons_dir then
        pcall(function()
            local DataStorage = require("datastorage")
            local lfs = require("libs/libkoreader-lfs")
            local ffiutil = require("ffi/util")
            local user_icons_dir = DataStorage:getDataDir() .. "/icons"
            if lfs.attributes(user_icons_dir, "mode") ~= "directory" then
                lfs.mkdir(user_icons_dir)
            end
            for _, name in ipairs({ "zen_ui.svg", "zen_ui_light.svg" }) do
                local dst = user_icons_dir .. "/" .. name
                if lfs.attributes(dst, "mode") ~= "file" then
                    local src = _icons_dir .. name
                    if lfs.attributes(src, "mode") == "file" then
                        ffiutil.copyFile(src, dst)
                    end
                end
            end
        end)
    end

    -- ============================================================
    -- Inject icon paths into IconWidget's runtime name→path cache
    -- ============================================================
    -- The file copy above only helps after a restart (KOReader scans dirs
    -- at first use of each name and caches the result in the module-local
    -- ICONS_PATH table).  To make the icon work immediately on first install
    -- we pre-populate that cache directly via debug.getupvalue.
    -- This is wrapped in pcall so any failure is silent.
    if _icons_dir then
        pcall(function()
            local lfs = require("libs/libkoreader-lfs")
            local iw = require("ui/widget/iconwidget")
            local iw_init = rawget(iw, "init")
            if type(iw_init) ~= "function" then return end
            local icons_path
            for i = 1, 64 do
                local uname, uval = debug.getupvalue(iw_init, i)
                if uname == nil then break end
                if uname == "ICONS_PATH" and type(uval) == "table" then
                    icons_path = uval
                    break
                end
            end
            if not icons_path then return end
            for _, stem in ipairs({ "zen_ui", "zen_ui_light" }) do
                if not icons_path[stem] then
                    for _, ext in ipairs({ ".svg", ".png" }) do
                        local p = _icons_dir .. stem .. ext
                        if lfs.attributes(p, "mode") == "file" then
                            icons_path[stem] = p
                            break
                        end
                    end
                end
            end
        end)
    end

    local function is_enabled()
        local features = zen_plugin.config and zen_plugin.config.features
        return type(features) == "table" and features.quick_settings == true
    end

    -- ============================================================
    -- Configuration
    -- ============================================================

    local config_default = {
        button_order = { "wifi", "night", "rotate", "usb", "search", "quickrss", "cloud", "zlibrary", "calibre", "notion", "streak", "opds", "filebrowser", "restart", "exit", "sleep" },
        show_buttons = {
            wifi = true,
            night = true,
            rotate = true,
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
            label = "Wi-Fi",
            label_func = function()
                if NetworkMgr:isWifiOn() then
                    local net = NetworkMgr:getCurrentNetwork()
                    if net and net.ssid then
                        return net.ssid
                    end
                end
                return "Wi-Fi"
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
        },
        night = {
            icon = "quick_nightmode",
            label = "Night",
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
            label = "Rotate",
            callback = function()
                UIManager:broadcastEvent(Event:new("SwapRotation"))
            end,
        },
        usb = {
            icon = "quick_usb",
            label = "USB",
            callback = function()
                if Device:canToggleMassStorage() then
                    UIManager:broadcastEvent(Event:new("RequestUSBMS"))
                end
            end,
        },
        restart = {
            icon = "quick_restart",
            label = "Restart",
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
            label = "Exit",
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
            label = "Sleep",
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
            label = "Search",
            callback = function()
                UIManager:broadcastEvent(Event:new("ShowFileSearch"))
            end,
        },
        quickrss = {
            icon = "quick_quickrss",
            label = "QuickRSS",
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
            label = "Cloud",
            callback = function()
                UIManager:broadcastEvent(Event:new("ShowCloudStorage"))
            end,
        },
        zlibrary = {
            icon = "quick_zlib",
            label = "Z-Lib",
            callback = function()
                UIManager:broadcastEvent(Event:new("ZlibrarySearch"))
            end,
        },
        calibre = {
            icon = "quick_calibre",
            label = "Calibre",
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
            label = "NotionSync",
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
            label = "Streak",
            callback = function()
                UIManager:broadcastEvent(Event:new("ShowReadingStreakCalendar"))
            end,
        },
        opds = {
            icon = "quick_opds",
            label = "OPDS",
            callback = function()
                UIManager:broadcastEvent(Event:new("ShowOPDSCatalog"))
            end,
        },
        filebrowser = {
            icon = "quick_opds",
            label = "FileBrowser",
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
        local refs = { buttons = {} }

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
                file = icon_path or nil,
                icon = icon_path and nil or icon_name,
                width = icon_size,
                height = icon_size,
                alpha = true,
            }
            local circle = FrameContainer:new{
                width = action_btn_size,
                height = action_btn_size,
                radius = math.floor(action_btn_size / 2),
                bordersize = normal_border,
                background = active and Blitbuffer.COLOR_LIGHT_GRAY or Blitbuffer.COLOR_WHITE,
                padding = 0,
                CenterContainer:new{
                    dimen = Geom:new{
                        w = action_btn_size - normal_border * 2,
                        h = action_btn_size - normal_border * 2,
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
                })

                table.insert(top_row, btn_widget)
                if i < num_buttons then
                    table.insert(top_row, HorizontalSpan:new{ width = btn_gap })
                end
            end
        end

        -- ----- Frontlight section -----

        local medium_font = Font:getFace("ffont")
        local small_btn_width = Screen:scaleBySize(40)
        local max_btn_width = Screen:scaleBySize(85)
        local slider_gap = Screen:scaleBySize(4)
        local slider_width = inner_width - 2 * small_btn_width - 2 * slider_gap
        local section_span = VerticalSpan:new{ width = Screen:scaleBySize(8) }

        local fl_group = VerticalGroup:new{ align = "center" }

        if config.show_frontlight then
            -- Frontlight state
            local fl = {
                min = powerd.fl_min,
                max = powerd.fl_max,
                cur = powerd:frontlightIntensity(),
            }
            local fl_steps = fl.max - fl.min + 1
            local fl_stride = math.ceil(fl_steps * (1/25))

            -- Ticks for the progress bar
            local fl_ticks = {}
            local fl_num_ticks = math.ceil(fl_steps / fl_stride)
            if (fl_num_ticks - 1) * fl_stride < fl.max - fl.min then
                fl_num_ticks = fl_num_ticks + 1
            end
            fl_num_ticks = math.min(fl_num_ticks, fl_steps)
            for i = 1, fl_num_ticks - 2 do
                table.insert(fl_ticks, i * fl_stride)
            end

            local fl_label = TextWidget:new{
                text = _("Frontlight") .. ": " .. tostring(fl.cur),
                face = medium_font,
                max_width = inner_width,
            }

            -- Create buttons first to measure height
            local fl_minus = Button:new{
                text = "−",
                width = small_btn_width,
                show_parent = touch_menu.show_parent,
                callback = function() end, -- placeholder, set below
            }
            local btn_height = fl_minus:getSize().h

            local fl_progress = ProgressWidget:new{
                width = slider_width,
                height = btn_height,
                percentage = fl.cur / fl.max,
                ticks = fl_ticks,
                tick_width = Screen:scaleBySize(0.5),
                last = fl.max,
                margin_h = 0,
            }

            local function updateBrightnessWidgets()
                fl_progress:setPercentage(fl.cur / fl.max)
                fl_label:setText(_("Frontlight") .. ": " .. tostring(fl.cur))
                UIManager:setDirty(touch_menu.show_parent, "ui")
            end

            local function setBrightness(intensity)
                if intensity ~= fl.min and intensity == fl.cur then return end
                intensity = math.max(fl.min, math.min(fl.max, intensity))
                powerd:setIntensity(intensity)
                fl.cur = powerd:frontlightIntensity()
                if fl.cur > fl.min then
                    fl.prev_non_min = fl.cur
                end
                updateBrightnessWidgets()
            end

            fl.prev_non_min = fl.cur > fl.min and fl.cur or math.min(fl.max, fl.min + 1)

            -- Now wire up the real callback
            fl_minus.callback = function() setBrightness(fl.cur - 1) end
            local fl_plus = Button:new{
                text = "＋",
                width = small_btn_width,
                show_parent = touch_menu.show_parent,
                callback = function() setBrightness(fl.cur + 1) end,
            }
            local fl_off_btn = Button:new{
                text = _("Toggle"),
                width = max_btn_width,
                face = medium_font,
                show_parent = touch_menu.show_parent,
                callback = function()
                    if fl.cur > fl.min then
                        fl.prev_non_min = fl.cur
                        setBrightness(fl.min)
                    else
                        setBrightness(fl.prev_non_min or math.min(fl.max, fl.min + 1))
                    end
                end,
            }
            local fl_max_btn = Button:new{
                text = _("Max"),
                width = max_btn_width,
                face = medium_font,
                show_parent = touch_menu.show_parent,
                callback = function() setBrightness(fl.max) end,
            }

            local row_gap = VerticalSpan:new{ width = Screen:scaleBySize(10) }
            local label_width = inner_width - 2 * max_btn_width

            -- Cap row: [Off]  [Frontlight: N]  [Max]
            local fl_cap_row = HorizontalGroup:new{
                align = "center",
                fl_off_btn,
                CenterContainer:new{
                    dimen = Geom:new{ w = label_width, h = fl_off_btn:getSize().h },
                    fl_label,
                },
                fl_max_btn,
            }
            -- Slider row: [−] [slider] [+]
            local fl_row = HorizontalGroup:new{
                align = "center",
                fl_minus,
                HorizontalSpan:new{ width = slider_gap },
                fl_progress,
                HorizontalSpan:new{ width = slider_gap },
                fl_plus,
            }

            -- Store progress ref for tap/pan handling
            refs.fl_progress = fl_progress
            refs.fl_state = fl
            refs.setBrightness = setBrightness

            local section_pad = VerticalSpan:new{ width = Screen:scaleBySize(10) }

            table.insert(fl_group, section_pad)
            table.insert(fl_group, fl_cap_row)
            table.insert(fl_group, row_gap)
            table.insert(fl_group, fl_row)
            table.insert(fl_group, section_pad)
        end

        -- ----- Warmth section (conditional) -----

        local warmth_group = VerticalGroup:new{ align = "center" }
        if config.show_warmth and Device:hasNaturalLight() then
            local btn_height_warmth
            if not config.show_frontlight then
                local tmp = Button:new{ text = "−", width = small_btn_width, show_parent = touch_menu.show_parent, callback = function() end }
                btn_height_warmth = tmp:getSize().h
            else
                btn_height_warmth = Button:new{ text = "−", width = small_btn_width, show_parent = touch_menu.show_parent, callback = function() end }:getSize().h
            end

            local nl = {
                min = powerd.fl_warmth_min,
                max = powerd.fl_warmth_max,
                cur = powerd:toNativeWarmth(powerd:frontlightWarmth()),
            }
            local nl_steps = nl.max - nl.min + 1
            local nl_stride = math.ceil(nl_steps * (1/25))
            local nl_num_buttons = math.ceil(nl_steps / nl_stride)
            if (nl_num_buttons - 1) * nl_stride < nl.max - nl.min then
                nl_num_buttons = nl_num_buttons + 1
            end
            nl_num_buttons = math.min(nl_num_buttons, nl_steps)

            local warmth_slider_width = inner_width - 2 * small_btn_width - 2 * slider_gap

            local nl_label = TextWidget:new{
                text = _("Warmth") .. ": " .. tostring(nl.cur),
                face = medium_font,
                max_width = inner_width,
            }

            local nl_progress = ButtonProgressWidget:new{
                width = warmth_slider_width,
                height = btn_height_warmth,
                font_size = 20,
                padding = 0,
                thin_grey_style = false,
                num_buttons = nl_num_buttons - 1,
                position = math.floor(nl.cur / nl_stride),
                default_position = math.floor(nl.cur / nl_stride),
                callback = function(i)
                    local new_native = Math.round(i * nl_stride)
                    new_native = math.min(new_native, nl.max)
                    powerd:setWarmth(powerd:fromNativeWarmth(new_native))
                    nl.cur = powerd:toNativeWarmth(powerd:frontlightWarmth())
                    if nl.cur > nl.min then
                        nl.prev_non_min = nl.cur
                    end
                    nl_label:setText(_("Warmth") .. ": " .. tostring(nl.cur))
                    UIManager:setDirty(touch_menu.show_parent, "ui")
                end,
                show_parent = touch_menu.show_parent,
                enabled = true,
            }

            local function setWarmth(warmth)
                if warmth == nl.cur then return end
                warmth = math.max(nl.min, math.min(nl.max, warmth))
                powerd:setWarmth(powerd:fromNativeWarmth(warmth))
                nl.cur = powerd:toNativeWarmth(powerd:frontlightWarmth())
                if nl.cur > nl.min then
                    nl.prev_non_min = nl.cur
                end
                nl_progress:setPosition(math.floor(nl.cur / nl_stride), nl_progress.default_position)
                nl_label:setText(_("Warmth") .. ": " .. tostring(nl.cur))
                UIManager:setDirty(touch_menu.show_parent, "ui")
            end

            nl.prev_non_min = nl.cur > nl.min and nl.cur or math.min(nl.max, nl.min + 1)

            local nl_minus = Button:new{
                text = "−",
                width = small_btn_width,
                show_parent = touch_menu.show_parent,
                callback = function() setWarmth(nl.cur - 1) end,
            }
            local nl_plus = Button:new{
                text = "＋",
                width = small_btn_width,
                show_parent = touch_menu.show_parent,
                callback = function() setWarmth(nl.cur + 1) end,
            }
            local nl_off_btn = Button:new{
                text = _("Toggle"),
                width = max_btn_width,
                face = medium_font,
                show_parent = touch_menu.show_parent,
                callback = function()
                    if nl.cur > nl.min then
                        nl.prev_non_min = nl.cur
                        setWarmth(nl.min)
                    else
                        setWarmth(nl.prev_non_min or math.min(nl.max, nl.min + 1))
                    end
                end,
            }
            local nl_max_btn = Button:new{
                text = _("Max"),
                width = max_btn_width,
                face = medium_font,
                show_parent = touch_menu.show_parent,
                callback = function() setWarmth(nl.max) end,
            }

            local nl_row_gap = VerticalSpan:new{ width = Screen:scaleBySize(10) }
            local nl_label_width = inner_width - 2 * max_btn_width

            -- Cap row: [Off]  [Warmth: N]  [Max]
            local nl_cap_row = HorizontalGroup:new{
                align = "center",
                nl_off_btn,
                CenterContainer:new{
                    dimen = Geom:new{ w = nl_label_width, h = nl_off_btn:getSize().h },
                    nl_label,
                },
                nl_max_btn,
            }
            -- Slider row: [−] [slider] [+]
            local nl_row = HorizontalGroup:new{
                align = "center",
                nl_minus,
                HorizontalSpan:new{ width = slider_gap },
                nl_progress,
                HorizontalSpan:new{ width = slider_gap },
                nl_plus,
            }

            table.insert(warmth_group, VerticalSpan:new{ width = Screen:scaleBySize(14) })
            table.insert(warmth_group, nl_cap_row)
            table.insert(warmth_group, nl_row_gap)
            table.insert(warmth_group, nl_row)
        end

        -- ----- Assemble panel -----

        local panel = VerticalGroup:new{
            align = "center",
            VerticalSpan:new{ width = Screen:scaleBySize(12) },
        }

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

    local function handlePanelGesture(touch_menu, ges)
        local refs = touch_menu._qs_refs
        if not refs then return false end

        -- Check frontlight progress bar (ProgressWidget doesn't handle its own taps)
        if refs.fl_progress and refs.fl_progress.dimen
           and ges.pos:intersectWith(refs.fl_progress.dimen) then
            local perc = refs.fl_progress:getPercentageFromPosition(ges.pos)
            if perc and refs.setBrightness then
                local fl = refs.fl_state
                local new_val = Math.round(perc * fl.max)
                refs.setBrightness(new_val)
                return true
            end
        end

        -- Check buttons
        for _, btn_ref in ipairs(refs.buttons) do
            if btn_ref.widget.dimen and ges.pos:intersectWith(btn_ref.widget.dimen) then
                btn_ref.callback()
                return true
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

    -- Hook updateItems for panel rendering
    local orig_updateItems = TouchMenu.updateItems

    function TouchMenu:updateItems(target_page, target_item_id)
        if not is_enabled() then
            self._qs_refs = nil
            return orig_updateItems(self, target_page, target_item_id)
        end

        if not self.item_table or not self.item_table.panel then
            self._qs_refs = nil -- clear refs when switching away from panel tab
            return orig_updateItems(self, target_page, target_item_id)
        end

        -- Custom panel mode: render the panel widget instead of menu items
        self.item_group:clear()
        self.layout = {}
        table.insert(self.item_group, self.bar)
        table.insert(self.layout, self.bar.icon_widgets)

        -- Build panel (also sets self._qs_refs)
        local panel_fn = self.item_table.panel
        local panel = type(panel_fn) == "function" and panel_fn(self) or panel_fn
        table.insert(self.item_group, panel)

        -- Footer (no pagination, just time/battery)
        table.insert(self.item_group, self.footer_top_margin)
        table.insert(self.item_group, self.footer)
        self.page_info_text:setText("")
        self.page_info_left_chev:showHide(false)
        self.page_info_right_chev:showHide(false)

        -- Update time/battery in footer
        local time_info_txt = datetime.secondsToHour(os.time(), G_reader_settings:isTrue("twelve_hour_clock"))
        local powerd = Device:getPowerDevice()
        if Device:hasBattery() then
            local batt_lvl = powerd:getCapacity()
            local batt_symbol = powerd:getBatterySymbol(powerd:isCharged(), powerd:isCharging(), batt_lvl)
            time_info_txt = BD.wrap(time_info_txt) .. " " .. BD.wrap("⌁") .. BD.wrap(batt_symbol) ..  BD.wrap(batt_lvl .. "%")
        end
        self.time_info:setText(time_info_txt)

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
            if handlePanelGesture(self, ges_ev) then
                return true
            end
        end
        return orig_onTapCloseAllMenus(self, arg, ges_ev)
    end

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

    -- Hook onSwipe to intercept pan/swipe on sliders
    local orig_onSwipe = TouchMenu.onSwipe

    function TouchMenu:onSwipe(arg, ges_ev)
        if not is_enabled() then
            if orig_onSwipe then
                return orig_onSwipe(self, arg, ges_ev)
            end
            return
        end

        if self._qs_refs and self.item_table and self.item_table.panel then
            if handlePanelGesture(self, ges_ev) then
                return true
            end
        end
        if orig_onSwipe then
            return orig_onSwipe(self, arg, ges_ev)
        end
    end

    -- ============================================================
    -- Quick Settings tab definition
    -- ============================================================

    local quick_settings_tab = {
        id = "quicksettings",
        icon = "zen_ui",
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
