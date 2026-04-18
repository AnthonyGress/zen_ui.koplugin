local function apply_status_bar()
    -- Custom Status Bar patch for KOReader File Manager
    -- Replaces the "KOReader" title text with left/right status info
    -- Moves home/plus buttons to the subtitle (path) row
    -- Settings menu under File Browser > Status bar

    local BD = require("ui/bidi")
    local Device = require("device")
    local FileManager = require("apps/filemanager/filemanager")
    local Font = require("ui/font")
    local Geom = require("ui/geometry")
    local HorizontalGroup = require("ui/widget/horizontalgroup")
    local HorizontalSpan = require("ui/widget/horizontalspan")
    local LeftContainer = require("ui/widget/container/leftcontainer")
    local NetworkMgr = require("ui/network/manager")
    local OverlapGroup = require("ui/widget/overlapgroup")
    local RightContainer = require("ui/widget/container/rightcontainer")
    local TextWidget = require("ui/widget/textwidget")
    local UIManager = require("ui/uimanager")
    local Screen = Device.screen
    local Blitbuffer = require("ffi/blitbuffer")
    local LineWidget = require("ui/widget/linewidget")
    local Size = require("ui/size")
    local VerticalGroup = require("ui/widget/verticalgroup")
    local utils = require("common/utils")
    local _ = require("gettext")

    local zen_plugin = rawget(_G, "__ZEN_UI_PLUGIN")
    if not zen_plugin or type(zen_plugin.config) ~= "table" then
        return
    end

    local function is_enabled()
        local features = zen_plugin.config and zen_plugin.config.features
        return type(features) == "table" and features.status_bar == true
    end

    -- === Persistent config ===

    local separator_presets = {
        { key = "dot",    label = "Middle dot",    value = "  ·  " },
        { key = "bar",    label = "Vertical bar",  value = "  |  " },
        { key = "dash",   label = "Dash",          value = "  -  " },
        { key = "bullet", label = "Bullet",        value = "  •  " },
        { key = "space",  label = "Space only",    value = "   " },
        { key = "small-space",  label = "Space only (small)",    value = " " },
        { key = "none",   label = "No separator",  value = "" },
        { key = "custom", label = "Custom",        value = nil }, -- uses custom_separator
    }

    -- Known item keys; determines what can be placed on either side
    local known_item_keys = { "wifi", "disk", "ram", "frontlight", "battery", "time", "custom_text" }
    local known_item_set = {}
    for _, k in ipairs(known_item_keys) do known_item_set[k] = true end

    local config_default = {
        custom_text = "",  -- shown by the "custom_text" item; empty = device model name
        separator_key = "dot",
        custom_separator = "  ",
        left_order   = { "time" },
        center_order = {},
        right_order  = { "wifi", "battery" },
        time_12h = false,
        show_bottom_border = true,
        colored = false,
        bold_text = false,
        hide_browser_bar = true,
    }

    local function loadConfig()
        local config = zen_plugin.config.status_bar or {}
        -- Migration: convert old show/order/show_time format to left_order/right_order
        if config.left_order == nil and config.right_order == nil then
            local old_order = type(config.order) == "table" and config.order
                              or { "wifi", "disk", "ram", "frontlight", "battery" }
            local old_show  = type(config.show) == "table" and config.show or {}
            local migrated_right = {}
            for _, key in ipairs(old_order) do
                if old_show[key] ~= false then
                    table.insert(migrated_right, key)
                end
            end
            if config.show_time ~= false then
                local tpos = config.time_position or "center"
                if tpos == "right" then
                    config.left_order   = {}
                    config.center_order = {}
                    table.insert(migrated_right, 1, "time")
                    config.right_order  = migrated_right
                elseif tpos == "center" then
                    config.left_order   = {}
                    config.center_order = { "time" }
                    config.right_order  = migrated_right
                else
                    config.left_order   = { "time" }
                    config.center_order = {}
                    config.right_order  = migrated_right
                end
            else
                config.left_order   = {}
                config.center_order = {}
                config.right_order  = migrated_right
            end
        end
        -- Merge scalar defaults
        for k, v in pairs(config_default) do
            if config[k] == nil then
                config[k] = utils.deepcopy(v)
            end
        end
        -- Validate: only known keys, no cross-side duplicates
        local seen = {}
        local function clean_order(list)
            local out = {}
            for _, v in ipairs(type(list) == "table" and list or {}) do
                if known_item_set[v] and not seen[v] then
                    seen[v] = true
                    table.insert(out, v)
                end
            end
            return out
        end
        config.left_order   = clean_order(config.left_order)
        config.center_order = clean_order(config.center_order)
        config.right_order  = clean_order(config.right_order)
        zen_plugin.config.status_bar = config
        return config
    end

    local config = loadConfig()

    local function getSeparator()
        for _, preset in ipairs(separator_presets) do
            if preset.key == config.separator_key then
                return preset.value or config.custom_separator
            end
        end
        return "  ·  "
    end

    -- === Layout constants ===

    local function getBarFont()
        if config.bold_text then
            return Font:getFace("NotoSans-Bold.ttf", Font.sizemap["xx_smallinfofont"])
        end
        return Font:getFace("xx_smallinfofont")
    end
    local h_padding = Screen:scaleBySize(10)

    -- Disk free space cache
    local cached_disk_text = nil
    local cached_disk_time = 0

    -- === Color text support ===
    -- TextWidget uses colorblitFrom which converts RGB to grayscale.
    -- We need colorblitFromRGB32 for actual color rendering.

    local RenderText = require("ui/rendertext")

    local ColorTextWidget = TextWidget:extend{}

    function ColorTextWidget:paintTo(bb, x, y)
        self:updateSize()
        if self._is_empty then return end

        if not self.fgcolor or Blitbuffer.isColor8(self.fgcolor) or not Screen:isColorScreen() then
            TextWidget.paintTo(self, bb, x, y)
            return
        end

        if not self.use_xtext then
            -- Fallback path: render normally (no RGB support here)
            TextWidget.paintTo(self, bb, x, y)
            return
        end

        if not self._xshaping then
            self._xshaping = self._xtext:shapeLine(self._shape_start, self._shape_end,
                                                self._shape_idx_to_substitute_with_ellipsis)
        end

        local text_width = bb:getWidth() - x
        if self.max_width and self.max_width < text_width then
            text_width = self.max_width
        end
        local pen_x = 0
        local baseline = self.forced_baseline or self._baseline_h
        for _, xglyph in ipairs(self._xshaping) do
            if pen_x >= text_width then break end
            local face = self.face.getFallbackFont(xglyph.font_num)
            local glyph = RenderText:getGlyphByIndex(face, xglyph.glyph, self.bold)
            bb:colorblitFromRGB32(
                glyph.bb,
                x + pen_x + glyph.l + xglyph.x_offset,
                y + baseline - glyph.t - xglyph.y_offset,
                0, 0,
                glyph.bb:getWidth(), glyph.bb:getHeight(),
                self.fgcolor)
            pen_x = pen_x + xglyph.x_advance
        end
    end

    -- === Color definitions ===

    local colors = {
        wifi_on = Blitbuffer.ColorRGB32(0x33, 0x99, 0xFF, 0xFF),     -- blue
        wifi_off = Blitbuffer.ColorRGB32(0xDD, 0x33, 0x33, 0xFF),   -- red
        disk = Blitbuffer.ColorRGB32(0x33, 0xAA, 0x55, 0xFF),       -- green
        ram = Blitbuffer.ColorRGB32(0x33, 0xAA, 0x55, 0xFF),        -- green
        frontlight = Blitbuffer.ColorRGB32(0xFF, 0xAA, 0x00, 0xFF), -- amber
        battery_high = Blitbuffer.ColorRGB32(0x33, 0xAA, 0x55, 0xFF),   -- green
        battery_mid = Blitbuffer.ColorRGB32(0xFF, 0xAA, 0x00, 0xFF),    -- yellow/amber
        battery_low = Blitbuffer.ColorRGB32(0xDD, 0x33, 0x33, 0xFF),    -- red
    }

    -- === Data fetching functions (return icon, label, color) ===

    local function getDeviceName()
        if config.custom_text and config.custom_text ~= "" then
            return config.custom_text
        end
        return Device.model or "KOReader"
    end

    local function getWifiInfo()
        if not config.show.wifi then return nil end
        if NetworkMgr:isWifiOn() then
            return "\u{ECA8}", nil, colors.wifi_on
        else
            return "\u{ECA9}", nil, colors.wifi_off
        end
    end

    local function getRamInfo()
        if not config.show.ram then return nil end
        local statm = io.open("/proc/self/statm", "r")
        if statm then
            local _, rss = statm:read("*number", "*number")
            statm:close()
            if rss then
                return "\u{EA5A}", string.format(" %dM", math.floor(rss / 256)), colors.ram
            end
        end
        return "\u{EA5A}", " ?M", colors.ram
    end

    local function getDiskInfo()
        if not config.show.disk then return nil end
        local now = os.time()
        if cached_disk_text and (now - cached_disk_time) < 300 then
            return "\u{F0A0}", " " .. cached_disk_text, colors.disk
        end
        -- Use the home_dir KOReader is actually browsing, then common fallbacks.
        local home_dir = G_reader_settings and G_reader_settings:readSetting("home_dir")
        local search_paths = {}
        if home_dir and home_dir ~= "" then
            table.insert(search_paths, home_dir)
        end
        for _, p in ipairs({ "/mnt/us", "/mnt/onboard", "/sdcard", "/" }) do
            table.insert(search_paths, p)
        end
        for _, spath in ipairs(search_paths) do
            local pipe = io.popen("df -h " .. spath .. " 2>/dev/null")
            if pipe then
                for line in pipe:lines() do
                    local avail = line:match("%S+%s+%S+%s+%S+%s+(%S+)")
                    -- Only accept lines where the available field starts with a digit
                    if avail and avail:match("^%d") then
                        pipe:close()
                        cached_disk_text = avail
                        cached_disk_time = now
                        return "\u{F0A0}", " " .. avail, colors.disk
                    end
                end
                pipe:close()
            end
        end
        return "\u{F0A0}", " ?", colors.disk
    end

    local function getFrontlightInfo()
        if not config.show.frontlight then return nil end
        local powerd = Device:getPowerDevice()
        if powerd:isFrontlightOn() then
            return "☼", string.format(" %d", powerd:frontlightIntensity()), colors.frontlight
        else
            return "☼", " " .. _("Off"), colors.frontlight
        end
    end

    local function getBatteryInfo()
        if not config.show.battery then return nil end
        if Device:hasBattery() then
            local powerd = Device:getPowerDevice()
            local batt_lvl = powerd:getCapacity()
            local batt_symbol = powerd:getBatterySymbol(
                powerd:isCharged(), powerd:isCharging(), batt_lvl)
            local color
            if batt_lvl >= 50 then
                color = colors.battery_high
            elseif batt_lvl >= 20 then
                color = colors.battery_mid
            else
                color = colors.battery_low
            end
            return BD.wrap(batt_symbol), batt_lvl .. "%", color
        end
        return nil
    end

    local function getTimeInfo()
        local fmt = config.time_12h and "%I:%M %p" or "%H:%M"
        local time_str = os.date(fmt)
        if config.time_12h then
            time_str = time_str:gsub("^0(%d:)", "%1")
        end
        return time_str, nil, nil
    end

    local function getCustomTextInfo()
        local text = (config.custom_text ~= nil and config.custom_text ~= "")
                     and config.custom_text or getDeviceName()
        return (text ~= "") and text or nil, nil, nil
    end

    -- === Item registry ===

    local item_fetchers = {
        wifi        = getWifiInfo,
        disk        = getDiskInfo,
        ram         = getRamInfo,
        frontlight  = getFrontlightInfo,
        battery     = getBatteryInfo,
        time        = getTimeInfo,
        custom_text = getCustomTextInfo,
    }

    -- === Build the status row ===

    -- Converts an ordered list of item keys into a HorizontalGroup widget.
    -- Module-level so it can be used by both createStatusRow and buildStatusRow.
    -- face: optional Font face override; falls back to getBarFont().
    local function _buildGroup(order, face)
        local group     = HorizontalGroup:new{}
        local sep       = getSeparator()
        local use_color = config.colored
        local first     = true
        local function f() return face or getBarFont() end
        for _, key in ipairs(order) do
            local fn = item_fetchers[key]
            if fn then
                local icon, label, color = fn()
                if icon ~= nil then
                    if not first and sep ~= "" then
                        table.insert(group, TextWidget:new{ text = sep, face = f() })
                    end
                    if use_color and color then
                        table.insert(group, ColorTextWidget:new{
                            text = icon, face = f(), fgcolor = color,
                        })
                        if label and label ~= "" then
                            table.insert(group, TextWidget:new{ text = label, face = f() })
                        end
                    else
                        local text = label and (icon .. label) or icon
                        table.insert(group, TextWidget:new{ text = text, face = f() })
                    end
                    first = false
                end
            end
        end
        return #group > 0 and group or nil
    end

    local function createStatusRow(path, file_manager)
        local CenterContainer = require("ui/widget/container/centercontainer")

        -- Detect whether we are inside a subfolder of, or at, the home directory
        local in_subfolder = false
        local at_home = false
        local folder_name = nil
        local g_settings = rawget(_G, "G_reader_settings")
        local home_dir = g_settings and g_settings:readSetting("home_dir")
        if home_dir and path then
            local norm_home = home_dir:gsub("/$", "")
            local norm_path = path:gsub("/$", "")
            if norm_path == norm_home then
                at_home = true
            elseif norm_path:sub(1, #norm_home + 1) == norm_home .. "/" then
                in_subfolder = true
                folder_name = path:match("([^/]+)/?$") or path
            end
        end

        -- Respect KOReader's "Lock home folder" setting; zen mode always treats home as locked
        local is_zen_mode = zen_plugin.config
            and type(zen_plugin.config.features) == "table"
            and zen_plugin.config.features.zen_mode == true
        local home_locked = is_zen_mode
            or (g_settings ~= nil and g_settings:isTrue("lock_home_folder"))

        -- Show back chevron in subfolders always; everywhere when home is not locked
        local show_back = in_subfolder or not home_locked

        -- Back chevron is always pinned to the far-left when navigation is available
        local back_widget = nil
        if show_back then
            local Button = require("ui/widget/button")
            local ffiUtil = require("ffi/util")
            local icon_size = Screen:scaleBySize(28)
            back_widget = Button:new{
                icon = "chevron.left",
                icon_width = icon_size,
                icon_height = icon_size,
                bordersize = 0,
                padding = 0,
                callback = function()
                    local parent = ffiUtil.dirname(path)
                    if file_manager and file_manager.file_chooser and parent then
                        -- Defer the path change to avoid button dimen crash during feedback highlight
                        UIManager:scheduleIn(0.1, function()
                            if file_manager.file_chooser then
                                file_manager.file_chooser:changeToPath(parent)
                            end
                        end)
                    end
                end,
            }
        end

        local left_content  = _buildGroup(config.left_order   or {})
        local right_content = _buildGroup(config.right_order  or {})

        -- Center: folder name when in subfolder takes priority over configured center items
        local center_content = nil
        if in_subfolder and folder_name then
            center_content = TextWidget:new{
                text = folder_name,
                face = getBarFont(),
                bold = true,
            }
        else
            center_content = _buildGroup(config.center_order or {})
        end

        -- Row height = max of all present widgets
        local row_height = Screen:scaleBySize(18)
        local function updateRowHeight(w)
            if w then
                local sz = w:getSize()
                if sz and sz.h > row_height then row_height = sz.h end
            end
        end
        updateRowHeight(back_widget)
        updateRowHeight(left_content)
        updateRowHeight(center_content)
        updateRowHeight(right_content)

        local screen_w    = Screen:getWidth()
        local inner_w     = screen_w - h_padding * 2
        local chevron_gap = Screen:scaleBySize(6)

        -- Left zone: h_padding + [chevron] + [gap] + [left_content]
        local left_group = HorizontalGroup:new{}
        table.insert(left_group, HorizontalSpan:new{ width = h_padding })
        if back_widget then
            table.insert(left_group, back_widget)
            if left_content then
                table.insert(left_group, HorizontalSpan:new{ width = chevron_gap })
            end
        end
        if left_content then
            table.insert(left_group, left_content)
        end

        local row = OverlapGroup:new{
            dimen = Geom:new{ w = screen_w, h = row_height },
            LeftContainer:new{
                dimen = Geom:new{ w = screen_w, h = row_height },
                left_group,
            },
        }

        if center_content then
            table.insert(row, CenterContainer:new{
                dimen = Geom:new{ w = screen_w, h = row_height },
                center_content,
            })
        end

        if right_content then
            table.insert(row, RightContainer:new{
                dimen = Geom:new{ w = screen_w, h = row_height },
                HorizontalGroup:new{
                    right_content,
                    HorizontalSpan:new{ width = h_padding },
                },
            })
        end

        if not config.show_bottom_border then
            return row
        end

        local border = LineWidget:new{
            dimen = Geom:new{ w = inner_w, h = Size.line.medium },
            background = Blitbuffer.COLOR_LIGHT_GRAY,
        }

        local vg = VerticalGroup:new{ align = "center", row }
        table.insert(vg, CenterContainer:new{
            dimen = Geom:new{ w = screen_w, h = Size.line.medium },
            border,
        })
        return vg
    end

    -- Builds a pure item row (no file-browser navigation) suitable for embedding in other panels.
    -- width: desired row width in pixels (e.g. the panel's inner_width).
    -- opts:  optional table with:
    --   padding   (number)  edge inset in pixels; defaults to h_padding
    --   font_name (string)  Font sizemap key, e.g. "x_smallinfofont"; defaults to "xx_smallinfofont"
    local function buildStatusRow(width, opts)
        opts = opts or {}
        local edge_pad = opts.padding ~= nil and opts.padding or h_padding
        local face
        if opts.font_name then
            if config.bold_text then
                face = Font:getFace("NotoSans-Bold.ttf", Font.sizemap[opts.font_name])
            else
                face = Font:getFace(opts.font_name)
            end
        end

        local left_content   = _buildGroup(config.left_order   or {}, face)
        local center_content = _buildGroup(config.center_order or {}, face)
        local right_content  = _buildGroup(config.right_order  or {}, face)

        local row_height = Screen:scaleBySize(18)
        local function upd(w)
            if w then local s = w:getSize(); if s and s.h > row_height then row_height = s.h end end
        end
        upd(left_content); upd(center_content); upd(right_content)

        local left_group = HorizontalGroup:new{}
        table.insert(left_group, HorizontalSpan:new{ width = edge_pad })
        if left_content then table.insert(left_group, left_content) end

        local row = OverlapGroup:new{
            dimen = Geom:new{ w = width, h = row_height },
            LeftContainer:new{
                dimen = Geom:new{ w = width, h = row_height },
                left_group,
            },
        }
        if center_content then
            local CenterContainer = require("ui/widget/container/centercontainer")
            table.insert(row, CenterContainer:new{
                dimen = Geom:new{ w = width, h = row_height },
                center_content,
            })
        end
        if right_content then
            table.insert(row, RightContainer:new{
                dimen = Geom:new{ w = width, h = row_height },
                HorizontalGroup:new{
                    right_content,
                    HorizontalSpan:new{ width = edge_pad },
                },
            })
        end
        return row
    end

    -- Schedules a 60-second periodic refresh of a TouchMenu panel that contains a
    -- status row.  The timer function is stored on the menu so it can be unscheduled
    -- and self-cancels when the menu is no longer in panel mode.
    local function schedulePanelRefresh(menu)
        if menu._zen_status_timer then
            UIManager:unschedule(menu._zen_status_timer)
        end
        local function tick()
            if menu.item_table and menu.item_table.panel then
                menu:updateItems()
                UIManager:scheduleIn(60, tick)
            else
                menu._zen_status_timer = nil
            end
        end
        menu._zen_status_timer = tick
        UIManager:scheduleIn(60, tick)
    end

    local function cancelPanelRefresh(menu)
        if menu._zen_status_timer then
            UIManager:unschedule(menu._zen_status_timer)
            menu._zen_status_timer = nil
        end
    end

    -- Expose for cross-patch use. Stored on the plugin table so it is naturally
    -- scoped to when this feature is active and cleaned up on plugin reload.
    if type(zen_plugin) == "table" then
        if not zen_plugin._zen_shared then zen_plugin._zen_shared = {} end
        zen_plugin._zen_shared.createStatusRow    = createStatusRow
        zen_plugin._zen_shared.buildStatusRow     = buildStatusRow
        zen_plugin._zen_shared.schedulePanelRefresh = schedulePanelRefresh
        zen_plugin._zen_shared.cancelPanelRefresh   = cancelPanelRefresh
    end

    -- === Replace title content and reposition buttons ===

    function FileManager:_updateStatusBar()
        if not is_enabled() then
            return
        end

        local tb = self.title_bar
        if not tb or not tb.title_group then return end

        local title_group = tb.title_group
        if #title_group < 2 then return end

        local current_path = self.file_chooser and self.file_chooser.path
        local status_row = createStatusRow(current_path, self)
        title_group[2] = status_row
        title_group:resetLayout()

        -- title_group: [1] VerticalSpan, [2] status_row, [3] VerticalSpan, [4] subtitle
        local subtitle_y = 0
        for i = 1, math.min(3, #title_group) do
            subtitle_y = subtitle_y + title_group[i]:getSize().h
        end

        local subtitle_h = 0
        if #title_group >= 4 then
            subtitle_h = title_group[4]:getSize().h
        end

        local area_h = tb.titlebar_height - subtitle_y
        local subtitle_center_y = subtitle_y + math.floor((area_h - subtitle_h) / 2)

        -- Center button icons with subtitle text
        local btn_padding = tb.button_padding
        local icon_h = tb.left_button and tb.left_button.width or 0
        local target_center = subtitle_center_y + math.floor(subtitle_h / 2)
        local button_y = target_center - btn_padding - math.floor(icon_h / 2)

        if tb.left_button then
            tb.left_button.overlap_align = nil
            tb.left_button.overlap_offset = {0, button_y}
        end
        if tb.right_button then
            local btn_w = tb.right_button:getSize().w
            tb.right_button.overlap_align = nil
            tb.right_button.overlap_offset = {tb.width - btn_w, button_y}
        end

        -- Center subtitle vertically in the area
        if #title_group >= 3 then
            local VerticalSpan = require("ui/widget/verticalspan")
            local status_row_bottom = 0
            for i = 1, 2 do
                status_row_bottom = status_row_bottom + title_group[i]:getSize().h
            end
            local new_padding = subtitle_center_y - status_row_bottom
            if new_padding > 0 then
                title_group[3] = VerticalSpan:new{ width = new_padding }
                title_group:resetLayout()
            end
        end

        UIManager:setDirty(self.show_parent or self, "ui", tb.dimen)
    end

    -- === Hooks ===

    local orig_setupLayout = FileManager.setupLayout

    function FileManager:setupLayout()
        if not is_enabled() then
            return orig_setupLayout(self)
        end

        if config.hide_browser_bar then
            -- Patch TitleBar constructor to suppress only the subtitle row and
            -- icon buttons.  Our custom status row (the title area) is kept so
            -- the height accounts for it and _updateStatusBar can still paint it.
            local TitleBar = require("ui/widget/titlebar")
            local orig_new = TitleBar.new
            TitleBar.new = function(cls, t)
                if type(t) == "table" then
                    t.subtitle            = nil
                    t.subtitle_truncate_left = nil
                    t.subtitle_fullwidth  = nil
                    t.left_icon           = nil
                    t.left_icon_tap_callback  = nil
                    t.left_icon_hold_callback = nil
                    t.right_icon          = nil
                    t.right_icon_tap_callback  = nil
                    t.right_icon_hold_callback = nil
                    t.title_tap_callback  = nil
                    t.title_hold_callback = nil
                    t.bottom_v_padding    = 0
                    -- Replace title text with a space so the slot has correct
                    -- height but shows nothing before _updateStatusBar paints
                    -- our custom row over it.
                    t.title               = " "
                end
                return orig_new(cls, t)
            end
            orig_setupLayout(self)
            TitleBar.new = orig_new
        else
            orig_setupLayout(self)
        end

        -- Apply immediately so the first paint shows our custom row rather
        -- than the placeholder title.  _updateStatusBar is a no-op when the
        -- titlebar isn't ready yet, so this is always safe to call early.
        self:_updateStatusBar()

        -- Defer again after all plugins (coverbrowser etc.) finish init
        local fm = self
        UIManager:nextTick(function()
            fm:_updateStatusBar()
            -- Restore subtitle path only when subtitle widget exists
            if not config.hide_browser_bar and fm.file_chooser and fm.file_chooser.path then
                fm:updateTitleBarPath(fm.file_chooser.path)
            end

            -- Disable page_info_text to prevent ghost search dialog when tapping title area
            if config.hide_browser_bar and fm.file_chooser then
                -- Completely hide page_info by collapsing its dimensions
                if fm.file_chooser.page_info then
                    fm.file_chooser.page_info.dimen = Geom:new{w = 0, h = 0}
                    -- Make it ignore all input
                    fm.file_chooser.page_info.handleEvent = function() return false end
                end
                -- Also disable the text button itself as extra safety
                if fm.file_chooser.page_info_text then
                    fm.file_chooser.page_info_text.readonly = true
                    fm.file_chooser.page_info_text.dimen = Geom:new{w = 0, h = 0}
                end
            end
        end)

        -- Periodic refresh for time/battery/disk.
        -- Always fires at the top of the next minute so the clock stays aligned.
        -- Also refreshes the favorites titlebar when it is open, so the clock
        -- updates there without needing a separate timer.
        local function autoRefresh()
            if FileManager.instance ~= fm then return end
            local stack = UIManager._window_stack
            local top = stack and stack[#stack]
            local top_widget = top and top.widget

            -- Refresh filebrowser titlebar when it is the topmost widget.
            -- Prevents painting into screensaver/lockscreen when inactive.
            if top_widget == fm or top_widget == fm.show_parent then
                fm:_updateStatusBar()
            end

            -- Refresh favorites titlebar when it is open.
            -- BookList is a separate overlay so fm is never "on top" then;
            -- we update it unconditionally whenever the menu exists.
            local fav_menu = fm.collections and fm.collections.booklist_menu
            if fav_menu then
                local fav_tb = fav_menu.title_bar
                if fav_tb and fav_tb.title_group and #fav_tb.title_group >= 2 then
                    fav_tb.title_group[2] = createStatusRow(nil, fm)
                    fav_tb.title_group:resetLayout()
                    UIManager:setDirty(fav_menu, "ui", fav_tb.dimen)
                end
            end

            -- Schedule next tick at the top of the following minute.
            local t = os.date("*t")
            UIManager:scheduleIn(60 - t.sec, autoRefresh)
        end
        -- First tick: align to the top of the next minute.
        local t = os.date("*t")
        UIManager:scheduleIn(60 - t.sec, autoRefresh)
    end

    local orig_onPathChanged = FileManager.onPathChanged

    function FileManager:onPathChanged(path)
        if orig_onPathChanged then
            orig_onPathChanged(self, path)
        end
        if is_enabled() then
            local fm = self
            UIManager:nextTick(function()
                fm:_updateStatusBar()
            end)
        end
    end

    local function chainHook(event_name)
        local orig = FileManager[event_name]
        FileManager[event_name] = function(self)
            if orig then orig(self) end
            if is_enabled() then
                self:_updateStatusBar()
            end
        end
    end

    chainHook("onNetworkConnected")
    chainHook("onNetworkDisconnected")
    chainHook("onCharging")
    chainHook("onNotCharging")

    -- Refresh the filebrowser status bar whenever any TouchMenu closes
    -- (e.g. after changing settings, toggling night mode, etc.)
    local TouchMenu = require("ui/widget/touchmenu")
    local orig_tm_close = TouchMenu.onCloseWidget
    TouchMenu.onCloseWidget = function(self_tm)
        if orig_tm_close then orig_tm_close(self_tm) end
        local fm = FileManager.instance
        if fm and is_enabled() then
            UIManager:nextTick(function()
                if FileManager.instance == fm then
                    fm:_updateStatusBar()
                end
            end)
        end
    end

    -- Refresh on filebrowser page turns (paging through the file list)
    local FileChooser = require("ui/widget/filechooser")
    local function wrapFCPage(method_name)
        local orig = FileChooser[method_name]
        FileChooser[method_name] = function(fc, ...)
            local result = orig and orig(fc, ...) or true
            local fm = FileManager.instance
            if fm and is_enabled() then
                UIManager:nextTick(function()
                    if FileManager.instance == fm then
                        fm:_updateStatusBar()
                    end
                end)
            end
            return result
        end
    end
    wrapFCPage("onNextPage")
    wrapFCPage("onPrevPage")

    -- onResume: defer long enough for the screensaver to finish its full-screen
    -- repaint and for the titlebar layout to be fully established.  nextTick
    -- (one loop pass) is too fast — it races against the screensaver's flashui
    -- flush and can fire before paintTo has set correct layout geometry, which
    -- causes child widgets to render at offset (0,0) i.e. top-left.
    -- scheduleIn(0) ticks once more after all current events and repaints settle.
    -- The topmost-widget guard (same as autoRefresh) prevents painting during
    -- any modal that might still be on top.
    local orig_onResume = FileManager.onResume
    FileManager.onResume = function(self)
        if orig_onResume then orig_onResume(self) end
        if is_enabled() then
            local fm = self
            -- Schedule two attempts: the screensaver may still be the topmost
            -- widget immediately after resume and will block the guard below.
            -- A second attempt at 1.5s reliably fires after it has dismissed.
            local function doResumeRefresh()
                if FileManager.instance ~= fm then return end
                local stack = UIManager._window_stack
                local top = stack and stack[#stack]
                if top and (top.widget == fm or top.widget == fm.show_parent) then
                    fm:_updateStatusBar()
                end
            end
            UIManager:scheduleIn(0.5, doResumeRefresh)
            UIManager:scheduleIn(1.5, doResumeRefresh)
            -- Re-align to the top of the next minute after resume,
            -- since the device clock may have advanced arbitrarily during sleep.
            UIManager:scheduleIn(2, function()
                if FileManager.instance ~= fm then return end
                local t = os.date("*t")
                local secs = 60 - t.sec
                UIManager:scheduleIn(secs, function()
                    if FileManager.instance == fm then
                        fm:_updateStatusBar()
                    end
                end)
            end)
        end
    end
end


return apply_status_bar
