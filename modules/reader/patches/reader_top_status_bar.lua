local function apply_reader_top_status_bar()
    --[[
        Paints a configurable three-zone header at the top of the reader screen (reflowable docs).
        Left / center / right slots each hold an ordered list of item keys.
        Items: time, battery, wifi, frontlight, ram, disk, custom_text,
               book_title, author, chapter
        Wraps ReaderView.paintTo. Config via config.reader_top_status_bar.
    --]]

    local Blitbuffer    = require("ffi/blitbuffer")
    local TextWidget    = require("ui/widget/textwidget")
    local CenterContainer = require("ui/widget/container/centercontainer")
    local LeftContainer   = require("ui/widget/container/leftcontainer")
    local RightContainer  = require("ui/widget/container/rightcontainer")

    local VerticalGroup = require("ui/widget/verticalgroup")
    local VerticalSpan  = require("ui/widget/verticalspan")
    local HorizontalGroup = require("ui/widget/horizontalgroup")
    local HorizontalSpan  = require("ui/widget/horizontalspan")
    local BD       = require("ui/bidi")
    local Size     = require("ui/size")
    local Geom     = require("ui/geometry")
    local Device   = require("device")
    local Font     = require("ui/font")
    local datetime = require("datetime")
    local UIManager = require("ui/uimanager")
    local _ = require("gettext")
    local Screen = Device.screen
    local ReaderView = require("apps/reader/modules/readerview")
    local _ReaderView_paintTo_orig = ReaderView.paintTo
    local zen_plugin = rawget(_G, "__ZEN_UI_PLUGIN")

    local logger = require("logger")
    local DBG = function(...) logger.dbg("ZenHeader:", ...) end

    local function is_enabled()
        local plugin = zen_plugin or rawget(_G, "__ZEN_UI_PLUGIN")
        local features = plugin and plugin.config and plugin.config.features
        return type(features) == "table" and features.reader_top_status_bar == true
    end

    local function is_view_active_top(view)
        if not (view and view.ui) then return false end
        local stack = UIManager._window_stack
        local top = stack and stack[#stack]
        local top_widget = top and top.widget
        if not top_widget then return false end
        if top_widget == view.ui or top_widget == view.ui.show_parent then
            return true
        end
        local parent = top_widget.show_parent
        return parent == view.ui or parent == view.ui.show_parent
    end

    -- Stable reference so suspend/resume can cancel/restart the timer.
    local _autoRefresh

    -- === Separator value map (bar-specific spacing; labels live in common/constants.lua) ===

    local SEP_VALUES = {
        dot             = " \xC2\xB7 ", -- middle dot
        bar             = " | ",
        dash            = " - ",
        bullet          = " \xE2\x80\xA2 ", -- bullet
        space           = "  ",
        ["small-space"] = " ",
        none            = "",
    }

    -- === Caches for slow item fetchers ===

    local cached_disk_text, cached_disk_time = nil, 0
    local cached_ram_text,  cached_ram_time  = nil, 0

    -- === Item fetchers: return (primary_text, suffix_or_nil) ===

    local function getWifiItem()
        local ok, NetworkMgr = pcall(require, "ui/network/manager")
        if not ok then return nil end
        return NetworkMgr:isWifiOn() and "\u{ECA8}" or "\u{ECA9}", nil
    end

    local function getRamItem()
        local now = os.time()
        if cached_ram_text and (now - cached_ram_time) < 30 then
            return "\u{EA5A}", " " .. cached_ram_text
        end
        local statm = io.open("/proc/self/statm", "r")
        if statm then
            local rss_pages = select(2, statm:read("*number", "*number"))
            statm:close()
            if rss_pages then
                cached_ram_text = string.format("%dM", math.floor(rss_pages / 256))
                cached_ram_time = now
                return "\u{EA5A}", " " .. cached_ram_text
            end
        end
        return "\u{EA5A}", " ?M"
    end

    local function getDiskItem()
        local now = os.time()
        if cached_disk_text and (now - cached_disk_time) < 300 then
            return "\u{F0A0}", " " .. cached_disk_text
        end
        local paths = require("common/paths")
        local home_dir = paths.getHomeDir()
        local dirs = {}
        if home_dir and home_dir ~= "" then table.insert(dirs, home_dir) end
        for _i, p in ipairs({ "/mnt/us", "/mnt/onboard", "/sdcard", "/" }) do
            table.insert(dirs, p)
        end
        for _i, dir in ipairs(dirs) do
            local pipe = io.popen("df -h " .. dir .. " 2>/dev/null")
            if pipe then
                for line in pipe:lines() do
                    local avail = line:match("%S+%s+%S+%s+%S+%s+(%S+)")
                    if avail and avail:match("^%d") then
                        pipe:close()
                        cached_disk_text = avail
                        cached_disk_time = now
                        return "\u{F0A0}", " " .. avail
                    end
                end
                pipe:close()
            end
        end
        return "\u{F0A0}", " ?"
    end

    local function getFrontlightItem()
        local powerd = Device:getPowerDevice()
        if not powerd then return nil end
        if powerd:isFrontlightOn() then
            return "\xe2\x98\xbc", string.format(" %d", powerd:frontlightIntensity())
        end
        return "\xe2\x98\xbc", " " .. _("Off")
    end

    local function getBatteryItem()
        if not Device:hasBattery() then return nil end
        local powerd = Device:getPowerDevice()
        local batt_lvl = powerd:getCapacity()
        local batt_symbol = powerd:getBatterySymbol(
            powerd:isCharged(), powerd:isCharging(), batt_lvl)
        return BD.wrap(batt_symbol), batt_lvl .. "%"
    end

    local function getTimeItem()
        local use_12h = G_reader_settings:isTrue("twelve_hour_clock")
        return datetime.secondsToHour(os.time(), use_12h) or "", nil
    end

    local function getCustomTextItem()
        local cfg = zen_plugin and zen_plugin.config and zen_plugin.config.reader_top_status_bar
        local text = type(cfg) == "table" and cfg.custom_text
        if not text or text == "" then text = Device.model or "Zen UI" end
        return text ~= "" and text or nil, nil
    end

    -- doc_ctx is the ReaderView; its .ui.doc_props has title/authors, .ui.toc has chapter.
    local function getBookTitleItem(doc_ctx)
        if not doc_ctx or not doc_ctx.ui then return nil end
        local props = doc_ctx.ui.doc_props
        local title = props and props.title
        if not title or title == "" then return nil end
        if #title > 40 then title = title:sub(1, 37) .. "..." end
        return title, nil
    end

    local function getAuthorItem(doc_ctx)
        if not doc_ctx or not doc_ctx.ui then return nil end
        local props = doc_ctx.ui.doc_props
        local authors = props and props.authors
        if not authors or authors == "" then return nil end
        if #authors > 30 then authors = authors:sub(1, 27) .. "..." end
        return authors, nil
    end

    local function getChapterItem(doc_ctx)
        if not doc_ctx or not doc_ctx.ui then return nil end
        local toc = doc_ctx.ui.toc
        if not toc then return nil end
        local chapter = toc:getTocTitleOfCurrentPage()
        if not chapter or chapter == "" then return nil end
        if #chapter > 35 then chapter = chapter:sub(1, 32) .. "..." end
        return chapter, nil
    end

    local item_fetchers = {
        wifi        = getWifiItem,
        disk        = getDiskItem,
        ram         = getRamItem,
        frontlight  = getFrontlightItem,
        battery     = getBatteryItem,
        time        = getTimeItem,
        custom_text = getCustomTextItem,
        book_title  = getBookTitleItem,
        author      = getAuthorItem,
        chapter     = getChapterItem,
    }

    local function collectItemTexts(order, doc_ctx)
        if type(order) ~= "table" or #order == 0 then return {} end
        local texts = {}
        for _i, key in ipairs(order) do
            local fn = item_fetchers[key]
            if fn then
                local icon, label = fn(doc_ctx)
                if icon ~= nil then
                    local text = label and (icon .. label) or icon
                    table.insert(texts, text)
                end
            end
        end
        return texts
    end

    local function measureTextsWidth(texts, face, sep)
        if type(texts) ~= "table" or #texts == 0 then return 0 end
        local total = 0
        for i = 1, #texts do
            if i > 1 and sep ~= "" then
                local sep_w = TextWidget:new{
                    text = sep,
                    face = face,
                    padding = 0,
                }
                total = total + sep_w:getSize().w
                sep_w:free()
            end
            local tw = TextWidget:new{
                text = texts[i],
                face = face,
                fgcolor = Blitbuffer.COLOR_BLACK,
                padding = 0,
            }
            total = total + tw:getSize().w
            tw:free()
        end
        return total
    end

    -- Builds a HorizontalGroup from pre-collected texts.
    -- If max_width is set and content overflows, rebuilds as a single ellipsis-truncated TextWidget.
    -- Returns (group_or_nil, widgets_list, natural_width).
    local function buildGroupFromTexts(texts, face, sep, max_width)
        if type(texts) ~= "table" or #texts == 0 then return nil, {}, 0 end
        if max_width and max_width <= 0 then return nil, {}, measureTextsWidth(texts, face, sep) end
        local group = HorizontalGroup:new{}
        local widgets = {}
        local natural_w = measureTextsWidth(texts, face, sep)
        for i = 1, #texts do
            if i > 1 and sep ~= "" then
                local sep_w = TextWidget:new{
                    text = sep,
                    face = face,
                    padding = 0,
                }
                table.insert(group, sep_w)
                table.insert(widgets, sep_w)
            end
            local tw = TextWidget:new{
                text = texts[i],
                face = face,
                fgcolor = Blitbuffer.COLOR_BLACK,
                padding = 0,
            }
            table.insert(group, tw)
            table.insert(widgets, tw)
        end

        if max_width and natural_w > max_width then
            for _i, w in ipairs(widgets) do if w.free then w:free() end end
            local joined = texts[1] or ""
            for i = 2, #texts do joined = joined .. sep .. texts[i] end
            local tw = TextWidget:new{
                text      = joined,
                face      = face,
                fgcolor   = Blitbuffer.COLOR_BLACK,
                padding   = 0,
                max_width = max_width,
            }
            return HorizontalGroup:new{ tw }, { tw }, natural_w
        end
        return group, widgets, natural_w
    end

    -- Builds the header widget from current config.
    -- doc_ctx: ReaderView (or nil); needed for book_title, author, chapter items.
    -- Returns header, all_widgets, header_h, screen_width; or nil if nothing to paint.
    local function buildHeader(doc_ctx)
        local screen_width = Screen:getWidth()
        local cfg = zen_plugin and zen_plugin.config and zen_plugin.config.reader_top_status_bar
        local footer_settings = G_reader_settings:readSetting("footer")

        local face_cfg = type(cfg) == "table" and cfg.font_face or "default"
        local font_name
        if face_cfg == "default" then
            font_name = (footer_settings and footer_settings.text_font_face) or "NotoSans-Regular.ttf"
        else
            font_name = face_cfg
        end
        local font_size = (type(cfg) == "table" and cfg.font_size) or 14
        local face = Font:getFace(font_name, font_size)

        local top_pad = Size.padding.small
        local h_pad   = Screen:scaleBySize(10)

        -- Slot orders (with backward compat for old position = "left/center/right" key)
        local left_order   = (type(cfg) == "table" and cfg.left_order)   or {}
        local center_order = (type(cfg) == "table" and cfg.center_order)
        local right_order  = (type(cfg) == "table" and cfg.right_order)  or {}
        if center_order == nil then
            local pos = type(cfg) == "table" and cfg.position
            if pos == "left" then
                left_order, center_order, right_order = { "time" }, {}, {}
            elseif pos == "right" then
                left_order, center_order, right_order = {}, {}, { "time" }
            else
                center_order = { "time" }
            end
        end

        local sep_key = (type(cfg) == "table" and cfg.separator_key) or "small-space"
        local sep_val = sep_key == "custom"
            and ((type(cfg) == "table" and cfg.custom_separator) or "  ")
            or (SEP_VALUES[sep_key] or " ")

        -- Per-slot separator: only active when *_show_separator == true (default off).
        local function slot_sep(slot)
            if type(cfg) == "table" and cfg[slot .. "_show_separator"] == true then
                return sep_val
            end
            return SEP_VALUES["small-space"]
        end

        local all_widgets = {}

        local left_sep = slot_sep("left")
        local center_sep = slot_sep("center")
        local right_sep = slot_sep("right")

        local left_texts = collectItemTexts(left_order, doc_ctx)
        local center_texts = collectItemTexts(center_order, doc_ctx)
        local right_texts = collectItemTexts(right_order, doc_ctx)

        local left_has = #left_texts > 0
        local center_has = #center_texts > 0
        local right_has = #right_texts > 0

        local left_nat = measureTextsWidth(left_texts, face, left_sep)
        local center_nat = measureTextsWidth(center_texts, face, center_sep)
        local right_nat = measureTextsWidth(right_texts, face, right_sep)

        local left_pad = left_has and h_pad or 0
        local right_pad = right_has and h_pad or 0

        local left_cap = 0
        local center_cap = 0
        local right_cap = 0
        local left_w = 0
        local center_w = 0
        local right_w = 0
        local middle_w = 0

        if center_has then
            local max_center = math.max(0, screen_width - left_pad - right_pad)
            center_cap = math.min(center_nat, max_center)
            center_w = center_cap

            local side_total = screen_width - center_w
            left_w = math.floor(side_total / 2)
            right_w = side_total - left_w

            left_cap = left_has and math.max(0, left_w - left_pad) or 0
            right_cap = right_has and math.max(0, right_w - right_pad) or 0
        else
            local side_content_space = math.max(0, screen_width - left_pad - right_pad)
            if left_has and right_has then
                if left_nat + right_nat <= side_content_space then
                    left_cap = left_nat
                    right_cap = right_nat
                else
                    left_cap = math.floor(side_content_space / 2)
                    right_cap = side_content_space - left_cap
                end
                left_w = left_pad + left_cap
                right_w = right_pad + right_cap
                middle_w = math.max(0, screen_width - left_w - right_w)
            elseif left_has then
                left_cap = math.max(0, screen_width - left_pad)
                left_w = screen_width
            elseif right_has then
                right_cap = math.max(0, screen_width - right_pad)
                right_w = screen_width
            end
        end

        local left_grp, left_ws = buildGroupFromTexts(left_texts, face, left_sep, left_cap)
        local center_grp, center_ws = buildGroupFromTexts(center_texts, face, center_sep, center_cap)
        local right_grp, right_ws = buildGroupFromTexts(right_texts, face, right_sep, right_cap)

        for _i, w in ipairs(left_ws)   do table.insert(all_widgets, w) end
        for _i, w in ipairs(center_ws) do table.insert(all_widgets, w) end
        for _i, w in ipairs(right_ws)  do table.insert(all_widgets, w) end

        if not left_grp and not center_grp and not right_grp then
            DBG("buildHeader: all groups nil, doc_ctx=", doc_ctx and "present" or "nil",
                "left_order=", #left_order, "center_order=", #(center_order or {}), "right_order=", #right_order)
            return nil, {}, 0, screen_width
        end

        local row_h = 0
        local function upd(w)
            if w then local s = w:getSize(); if s and s.h > row_h then row_h = s.h end end
        end
        upd(left_grp); upd(center_grp); upd(right_grp)
        local header_h = row_h + top_pad

        local function padded(grp)
            if not grp then return nil end
            local vg = VerticalGroup:new{}
            table.insert(vg, VerticalSpan:new{ width = top_pad })
            table.insert(vg, grp)
            return vg
        end

        local header = HorizontalGroup:new{}

        if center_grp then
            -- 3-zone layout: left | center | right
            if left_grp then
                table.insert(header, LeftContainer:new{
                    dimen = Geom:new{ w = left_w, h = header_h },
                    HorizontalGroup:new{
                        HorizontalSpan:new{ width = h_pad },
                        padded(left_grp),
                    },
                })
            else
                table.insert(header, HorizontalSpan:new{ width = left_w })
            end
            table.insert(header, CenterContainer:new{
                dimen = Geom:new{ w = center_w, h = header_h },
                padded(center_grp),
            })
            if right_grp then
                table.insert(header, RightContainer:new{
                    dimen = Geom:new{ w = right_w, h = header_h },
                    HorizontalGroup:new{
                        padded(right_grp),
                        HorizontalSpan:new{ width = h_pad },
                    },
                })
            else
                table.insert(header, HorizontalSpan:new{ width = right_w })
            end
        else
            -- 2-zone layout: left | right with adaptive middle gap.
            if left_grp then
                table.insert(header, LeftContainer:new{
                    dimen = Geom:new{ w = left_w, h = header_h },
                    HorizontalGroup:new{
                        HorizontalSpan:new{ width = h_pad },
                        padded(left_grp),
                    },
                })
            else
                table.insert(header, HorizontalSpan:new{ width = left_w })
            end
            if middle_w > 0 then
                table.insert(header, HorizontalSpan:new{ width = middle_w })
            end
            if right_grp then
                table.insert(header, RightContainer:new{
                    dimen = Geom:new{ w = right_w, h = header_h },
                    HorizontalGroup:new{
                        padded(right_grp),
                        HorizontalSpan:new{ width = h_pad },
                    },
                })
            else
                table.insert(header, HorizontalSpan:new{ width = right_w })
            end
        end

        return header, all_widgets, header_h, screen_width
    end

    -- Partial repaint: clears only the header strip in Screen.bb, repaints it,
    -- then flushes just that region to the display.  Avoids triggering a full
    -- ReaderView:paintTo (full page repaint) on every clock tick -- critical on
    -- color e-ink devices (e.g. Kobo Libre Color).
    local function repaintHeader(view)
        -- Strict guard: only repaint if the reader itself is the top window.
        -- is_view_active_top() allows child overlays (e.g. quick settings), which
        -- would cause repaintHeader to paint over them. Check the stack directly.
        do
            local stack = UIManager._window_stack
            local top = stack and stack[#stack]
            local top_widget = top and top.widget
            if not (top_widget == view.ui or top_widget == (view.ui and view.ui.show_parent)) then
                return
            end
        end
        if not view._zen_header_dimen then
            DBG("repaintHeader SKIP: no _zen_header_dimen (paintTo never ran?)")
            return
        end
        if not view.ui then
            DBG("repaintHeader SKIP: view.ui is nil")
            return
        end
        local header, all_widgets, header_h, screen_width = buildHeader(view)
        if not header then
            DBG("repaintHeader SKIP: buildHeader returned nil")
            return
        end
        local dimen = view._zen_header_dimen
        dimen.h = header_h
        dimen.w = screen_width
        local bb = Screen.bb
        if bb then
            bb:paintRect(dimen.x, dimen.y, dimen.w, dimen.h, Blitbuffer.COLOR_WHITE)
        end
        UIManager:widgetRepaint(header, dimen.x, dimen.y)
        UIManager:setDirty(nil, "ui", dimen)
        for _i, w in ipairs(all_widgets) do
            if w.free then w:free() end
        end
    end

    ReaderView.paintTo = function(self, bb, x, y)
        _ReaderView_paintTo_orig(self, bb, x, y)
        if not is_enabled() then return end
        if self.render_mode ~= nil then return end -- pdf-like; skip
        if not self.document then return end
        -- Guard: don't paint when reader is not active (allow overlays that
        -- belong to this ReaderUI via show_parent, e.g., AutoDim on resume).
        if not is_view_active_top(self) then
            return
        end

        local header, all_widgets, header_h, screen_width = buildHeader(self)
        if not header then
            DBG("paintTo: buildHeader returned nil, skipping header paint")
            return
        end

        header:paintTo(bb, x, y)
        -- Store geometry so repaintHeader can flush only this strip on clock ticks.
        self._zen_header_dimen = Geom:new{ x = x, y = y, w = screen_width, h = header_h }

        -- Free FFI-backed TextWidget memory immediately after paint.
        for _i, w in ipairs(all_widgets) do
            if w.free then w:free() end
        end

        -- Periodic refresh aligned to the top of each minute.
        -- Armed once per ReaderView instance; cancelled on suspend, restarted on resume.
        if not self._header_clock_refresh then
            self._header_clock_refresh = true
            local view = self
            local _autoRefreshFn
            _autoRefreshFn = function()
                if not (view.ui and view.ui.document) then
                    _autoRefresh = nil
                    return
                end
                if is_view_active_top(view) then
                    repaintHeader(view)
                end
                local t = os.date("*t")
                UIManager:scheduleIn(60 - t.sec, _autoRefreshFn)
            end
            _autoRefresh = _autoRefreshFn
            local t = os.date("*t")
            UIManager:scheduleIn(60 - t.sec, _autoRefreshFn)

            -- Cancel timer on suspend so it does not fire during sleep.
            local ReaderUI = require("apps/reader/readerui")
            -- Shared upvalue between onSuspend and the charging hooks below.
            local _charging_refresh_timer = nil
            local _resume_refresh_timer_1 = nil
            local _resume_refresh_timer_2 = nil
            local orig_onSuspend = ReaderUI.onSuspend
            ReaderUI.onSuspend = function(rui, ...)
                if orig_onSuspend then orig_onSuspend(rui, ...) end
                if _autoRefresh then
                    UIManager:unschedule(_autoRefresh)
                end
                if _charging_refresh_timer then
                    UIManager:unschedule(_charging_refresh_timer)
                    _charging_refresh_timer = nil
                end
                if _resume_refresh_timer_1 then
                    UIManager:unschedule(_resume_refresh_timer_1)
                    _resume_refresh_timer_1 = nil
                end
                if _resume_refresh_timer_2 then
                    UIManager:unschedule(_resume_refresh_timer_2)
                    _resume_refresh_timer_2 = nil
                end
            end
            local orig_onResume = ReaderUI.onResume
            ReaderUI.onResume = function(rui, ...)
                if orig_onResume then orig_onResume(rui, ...) end
                DBG("onResume fired, _autoRefresh=", _autoRefresh and "armed" or "nil",
                    "view._zen_header_dimen=", view._zen_header_dimen and "present" or "nil",
                    "view.ui=", view.ui and "present" or "nil")
                if _autoRefresh then
                    UIManager:unschedule(_autoRefresh)
                    -- Repaint immediately on wakeup only if no overlay is active.
                    if is_view_active_top(view) then
                        repaintHeader(view)
                    end
                    -- Retry after wake overlays settle; first repaint can race
                    -- with screensaver/AutoDim transitions.
                    if _resume_refresh_timer_1 then UIManager:unschedule(_resume_refresh_timer_1) end
                    if _resume_refresh_timer_2 then UIManager:unschedule(_resume_refresh_timer_2) end
                    _resume_refresh_timer_1 = function()
                        _resume_refresh_timer_1 = nil
                        if is_view_active_top(view) then
                            repaintHeader(view)
                        end
                    end
                    _resume_refresh_timer_2 = function()
                        _resume_refresh_timer_2 = nil
                        if is_view_active_top(view) then
                            repaintHeader(view)
                        end
                    end
                    UIManager:scheduleIn(0.6, _resume_refresh_timer_1)
                    UIManager:scheduleIn(1.8, _resume_refresh_timer_2)
                    local now_t = os.date("*t")
                    UIManager:scheduleIn(60 - now_t.sec, _autoRefresh)
                end
            end

            -- Debounce charging events: USB negotiation fires NotCharging then
            -- Charging within seconds; coalesce into one repaint after 1.5 s.
            local function scheduleChargingRefresh()
                if _charging_refresh_timer then
                    UIManager:unschedule(_charging_refresh_timer)
                end
                _charging_refresh_timer = function()
                    _charging_refresh_timer = nil
                    if not (view.ui and view.ui.document) then return end
                    if is_view_active_top(view) then
                        repaintHeader(view)
                    end
                end
                UIManager:scheduleIn(1.5, _charging_refresh_timer)
            end
            local orig_onCharging    = ReaderUI.onCharging
            local orig_onNotCharging = ReaderUI.onNotCharging
            ReaderUI.onCharging = function(rui, ...)
                if orig_onCharging then orig_onCharging(rui, ...) end
                scheduleChargingRefresh()
            end
            ReaderUI.onNotCharging = function(rui, ...)
                if orig_onNotCharging then orig_onNotCharging(rui, ...) end
                scheduleChargingRefresh()
            end
        end
    end
end

return apply_reader_top_status_bar
