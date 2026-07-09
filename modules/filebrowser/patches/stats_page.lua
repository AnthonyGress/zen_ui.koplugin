-- Zen UI Stats Page
-- Fullscreen reading stats dashboard with long-press block customization.

local Blitbuffer = require("ffi/blitbuffer")
local ButtonDialog = require("ui/widget/buttondialog")
local CenterContainer = require("ui/widget/container/centercontainer")
local BD = require("ui/bidi")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local LeftContainer = require("ui/widget/container/leftcontainer")
local LineWidget = require("ui/widget/linewidget")
local PluginLoader = require("pluginloader")
local ScrollableContainer = require("ui/widget/container/scrollablecontainer")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local TitleBar = require("ui/widget/titlebar")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local Background = require("common/ui/background")
local StandalonePage = require("modules/filebrowser/patches/standalone_page")
local SharedState = require("common/shared_state")
local StatsDB = require("common/db_stats")
local LibraryDB = require("common/db_library")
local BookInfoDB = require("common/db_bookinfo")
local ConfigManager = require("config/manager")
local LineGraph = require("common/ui/zen_line_graph")
local Screen = Device.screen
local _ = require("gettext")

local StatsPage = {}
local active_stats_menus = {}

local MAX_BLOCK_SLOTS = 6

local DEFAULT_BLOCKS = {
    { id = "today" },
    { id = "trend_graph", metric = "pages", range_days = 14 },
    { id = "goal_progress" },
    { id = "calendar" },
    { id = "library" },
}

local ALL_BLOCK_TYPES = {
    "today", "this_week", "this_month", "this_year", "all_time",
    "personal_records", "library", "current_book", "trend_graph", "goal_progress", "calendar",
}

local function copyBlock(block)
    local out = {}
    for key, value in pairs(block or {}) do
        out[key] = value
    end
    return out
end

local function defaultBlock(type_id)
    if type_id == "trend_graph" then
        return { id = type_id, metric = "pages", range_days = 14 }
    end
    return { id = type_id }
end

local function blockSlots(block)
    local type_id = type(block) == "table" and block.id or block
    return type_id == "calendar" and 2 or 1
end

local function validBlockTypes()
    local valid = {}
    for _i, type_id in ipairs(ALL_BLOCK_TYPES) do
        valid[type_id] = true
    end
    return valid
end

local function sanitizeBlock(block)
    local valid = validBlockTypes()
    local type_id = type(block) == "table" and block.id or block
    if not valid[type_id] then return nil end
    local out = defaultBlock(type_id)
    if type(block) == "table" then
        if type_id == "trend_graph" then
            out.metric = (block.metric == "time" or block.metric == "duration") and "time" or "pages"
            local range = tonumber(block.range_days) or 14
            if range ~= 7 and range ~= 14 and range ~= 30 and range ~= 90 then
                range = 14
            end
            out.range_days = range
        end
    end
    return out
end

local function blockTitle(block)
    local titles = {
        today            = _("Today"),
        this_week        = _("This Week"),
        this_month       = _("This Month"),
        this_year        = _("This Year"),
        all_time         = _("All Time"),
        personal_records = _("Personal Records"),
        library          = _("Library"),
        current_book     = _("Current Book"),
        trend_graph      = _("Reading Trend"),
        goal_progress    = _("Goal Progress"),
        calendar         = _("Reading Calendar"),
    }
    return titles[block.id] or tostring(block.id)
end

local function metricLabel(metric)
    return metric == "time" and _("Minutes") or _("Pages")
end

local function normalizeStatStyle(style)
    if style == "outline" then return style end
    if style == "none" then return style end
    return "divider"
end

local function statsFrameBg()
    return Background.tile_bg(Blitbuffer.COLOR_WHITE)
end

local function useLibraryBgScrollBuffer(scroll_widget)
    if not scroll_widget or scroll_widget._zen_library_scroll_bg then return end
    scroll_widget._zen_library_scroll_bg = true
    local orig_paintTo = scroll_widget.paintTo
    function scroll_widget:paintTo(bb, x, y)
        local bg_path = Background.library_path()
        if bg_path == "" then
            return orig_paintTo(self, bb, x, y)
        end
        if self[1] == nil then return end
        self.dimen.x = x
        self.dimen.y = y
        if self._is_scrollable == nil then
            self:initState()
        end
        local mirrored = BD.mirroredUILayout()
        if not self._is_scrollable then
            if mirrored then
                x = x + (self.dimen.w - self[1]:getSize().w)
            end
            self[1]:paintTo(bb, x, y)
            return
        end

        local screen_size = Screen:getSize()
        if not self._bb or self._bb:getWidth() ~= screen_size.w or self._bb:getHeight() ~= screen_size.h then
            if self._bb then self._bb:free() end
            self._bb = Blitbuffer.new(screen_size.w, screen_size.h, bb:getType())
        end
        if not Background.paint(self._bb, 0, 0, screen_size.w, screen_size.h, bg_path) then
            self._bb:fill(Blitbuffer.COLOR_WHITE)
        end

        local dx
        if mirrored then
            dx = self._max_scroll_offset_x - self._scroll_offset_x - self._crop_dx
        else
            dx = self._scroll_offset_x
        end
        self[1]:paintTo(self._bb, x - dx, y - self._scroll_offset_y)
        bb:blitFrom(self._bb, x + self._crop_dx, y, x + self._crop_dx, y,
            self._crop_w, self._crop_h_limited or self._crop_h)
        if self._h_scroll_bar then
            if mirrored then
                self._h_scroll_bar:paintTo(bb, x + self._h_scroll_bar_shift,
                    y + self.dimen.h - 2 * self.scroll_bar_width)
            else
                self._h_scroll_bar:paintTo(bb, x, y + self.dimen.h - 2 * self.scroll_bar_width)
            end
        end
        if self._v_scroll_bar then
            if mirrored then
                self._v_scroll_bar:paintTo(bb, x + self.scroll_bar_width, y)
            else
                self._v_scroll_bar:paintTo(bb, x + self.dimen.w - 2 * self.scroll_bar_width, y)
            end
        end
    end
end

local function blockHasStatSeparators(block)
    local id = type(block) == "table" and block.id or block
    return id ~= "trend_graph" and id ~= "goal_progress" and id ~= "calendar"
end

local function displayBlockTitle(block)
    local title = blockTitle(block)
    if block.id == "trend_graph" then
        title = title .. " " .. metricLabel(block.metric) .. ", "
            .. tostring(block.range_days or 14) .. _(" days")
    elseif block.id == "calendar" then
        title = ""
    end
    return title
end

local function cloneDefaultBlocks()
    local blocks = {}
    for _i, block in ipairs(DEFAULT_BLOCKS) do
        blocks[#blocks + 1] = copyBlock(block)
    end
    return blocks
end

local function saveBlocksConfig(blocks)
    local ok, cfg = pcall(ConfigManager.load)
    if not ok or type(cfg) ~= "table" then return end
    cfg.stats_page = cfg.stats_page or {}
    cfg.stats_page.blocks = blocks
    cfg.stats_page.rows = nil
    pcall(ConfigManager.save, cfg)
end

local function saveStatStyleConfig(style)
    local ok, cfg = pcall(ConfigManager.load)
    if not ok or type(cfg) ~= "table" then return end
    cfg.stats_page = cfg.stats_page or {}
    cfg.stats_page.stat_style = normalizeStatStyle(style)
    pcall(ConfigManager.save, cfg)
end

local function isCalendarMonth(month)
    local year, month_num = tostring(month or ""):match("^(%d%d%d%d)%-(%d%d)$")
    month_num = tonumber(month_num)
    return year ~= nil and month_num ~= nil and month_num >= 1 and month_num <= 12
end

local function saveCalendarMonthConfig(month)
    month = tostring(month or "")
    if not isCalendarMonth(month) then return end
    local ok, cfg = pcall(ConfigManager.load)
    if not ok or type(cfg) ~= "table" then return end
    cfg.stats_page = cfg.stats_page or {}
    cfg.stats_page.calendar_month = month
    pcall(ConfigManager.save, cfg)
end

local function loadCalendarMonthConfig()
    local ok, cfg = pcall(ConfigManager.load)
    if ok and type(cfg) == "table" and type(cfg.stats_page) == "table" then
        local month = tostring(cfg.stats_page.calendar_month or "")
        if isCalendarMonth(month) then return month end
    end
end

local function loadStatStyleConfig()
    local ok, cfg = pcall(ConfigManager.load)
    if ok and type(cfg) == "table" and type(cfg.stats_page) == "table" then
        return normalizeStatStyle(cfg.stats_page.stat_style)
    end
    return "divider"
end

local function loadBlocksConfig()
    local ok, cfg = pcall(ConfigManager.load)
    if ok and type(cfg) == "table" and type(cfg.stats_page) == "table" then
        local source = cfg.stats_page.blocks
        local migrated = false
        if type(source) ~= "table" or #source == 0 then
            source = cfg.stats_page.rows
            migrated = type(source) == "table" and #source > 0
        end
        if type(source) == "table" then
            local blocks = {}
            local changed = false
            local slots = 0
            for _i, block in ipairs(source) do
                local clean = sanitizeBlock(block)
                if clean then
                    local weight = blockSlots(clean)
                    if slots + weight > MAX_BLOCK_SLOTS and #blocks > 0 then
                        changed = true
                        break
                    end
                    if type(block) ~= "table"
                            or block.id ~= clean.id
                            or block.metric ~= clean.metric
                            or block.range_days ~= clean.range_days
                            or block.intensity ~= nil then
                        changed = true
                    end
                    blocks[#blocks + 1] = clean
                    slots = slots + weight
                    if slots >= MAX_BLOCK_SLOTS then break end
                end
            end
            if #blocks > 0 then
                local default_idx = #blocks + 1
                while slots < MAX_BLOCK_SLOTS and default_idx <= #DEFAULT_BLOCKS do
                    local block = copyBlock(DEFAULT_BLOCKS[default_idx])
                    local weight = blockSlots(block)
                    if slots + weight <= MAX_BLOCK_SLOTS then
                        blocks[#blocks + 1] = block
                        slots = slots + weight
                    end
                    changed = true
                    default_idx = default_idx + 1
                end
                if migrated or changed or cfg.stats_page.rows ~= nil then
                    saveBlocksConfig(blocks)
                end
                return blocks
            end
        end
    end
    return cloneDefaultBlocks()
end

local function formatTime(secs)
    secs = math.floor(secs or 0)
    if secs <= 0 then return "0m" end
    local h = math.floor(secs / 3600)
    local m = math.floor((secs % 3600) / 60)
    if h > 0 then
        return h .. "h " .. m .. "m"
    end
    return m .. "m"
end

local function formatLongTime(secs)
    secs = math.floor(secs or 0)
    if secs <= 0 then return "0m" end
    local d = math.floor(secs / 86400)
    local h = math.floor((secs % 86400) / 3600)
    local m = math.floor((secs % 3600) / 60)
    if d > 0 then
        return h > 0 and (d .. "d " .. h .. "h") or (d .. "d")
    elseif h > 0 then
        return h .. "h " .. m .. "m"
    end
    return m .. "m"
end

local function minuteCount(secs)
    return tostring(math.floor((tonumber(secs) or 0) / 60 + 0.5))
end

local function fmtPeakDay(ts)
    if not ts then return "" end
    return os.date("%b %d", ts):gsub(" 0(%d)", " %1")
end

local function fmtPeakWeek(ts)
    if not ts then return "" end
    local t = os.date("*t", ts)
    local days_to_mon = (t.wday - 2) % 7
    local mon_ts = ts - days_to_mon * 86400
    local sun_ts = mon_ts + 6 * 86400
    local mon_str = os.date("%b %d", mon_ts):gsub(" 0(%d)", " %1")
    if os.date("%m", mon_ts) == os.date("%m", sun_ts) then
        return mon_str .. "-" .. os.date("%d", sun_ts):gsub("^0", "")
    end
    return mon_str .. "-" .. os.date("%b %d", sun_ts):gsub(" 0(%d)", " %1")
end

local function fmtPeakMonth(ts)
    if not ts then return "" end
    return os.date("%b %Y", ts)
end

local function shortDate(date)
    local m, d = tostring(date or ""):match("^%d+%-(%d+)%-(%d+)$")
    if not m or not d then return "" end
    return tostring(tonumber(m)) .. "/" .. tostring(tonumber(d))
end

local function monthShift(month_s, delta)
    local year, month = tostring(month_s or ""):match("^(%d%d%d%d)%-(%d%d)$")
    year = tonumber(year)
    month = tonumber(month)
    if not year or not month then return os.date("%Y-%m", os.time()) end
    return os.date("%Y-%m", os.time{
        year = year,
        month = month + (delta or 0),
        day = 15,
        hour = 12,
        min = 0,
        sec = 0,
    })
end

local function monthLabel(month_s)
    local year, month = tostring(month_s or ""):match("^(%d%d%d%d)%-(%d%d)$")
    year = tonumber(year)
    month = tonumber(month)
    if not year or not month then return tostring(month_s or "") end
    return os.date("%B %Y", os.time{
        year = year,
        month = month,
        day = 15,
        hour = 12,
        min = 0,
        sec = 0,
    })
end

local function graphDateLabels(series, max_labels)
    local labels = {}
    local count = type(series) == "table" and #series or 0
    if count == 0 then return labels end
    local wanted = math.min(max_labels or 5, count)
    if wanted <= 1 then
        labels[#labels + 1] = { text = shortDate(series[count].date), ratio = 0.5 }
        return labels
    end
    local used = {}
    for i = 1, wanted do
        local idx = math.floor((i - 1) * (count - 1) / (wanted - 1) + 1.5)
        if not used[idx] then
            used[idx] = true
            labels[#labels + 1] = {
                text = shortDate(series[idx].date),
                ratio = count > 1 and ((idx - 1) / (count - 1)) or 0.5,
            }
        end
    end
    return labels
end

local function queryStats()
    local stats = StatsDB.queryStats()
    local book_counts = LibraryDB.getBookCounts()
    stats.books_finished = book_counts.finished
    stats.books_reading = book_counts.reading
    stats.total_books = BookInfoDB.getTotalBookCount()
    return stats
end

local function queryCurrentBookStats()
    local out = {
        title = _("Current Book"),
        total_time = 0,
        pages_read = 0,
        avg_time_per_page = 0,
        session_time = 0,
        session_pages = 0,
        total_pages = 0,
    }
    local stats_plugin = PluginLoader:getPluginInstance("statistics")
    if type(stats_plugin) ~= "table" or not stats_plugin.id_curr_book then
        return out
    end
    if type(stats_plugin.insertDB) == "function" then
        pcall(stats_plugin.insertDB, stats_plugin)
    end
    if type(stats_plugin.data) == "table" and type(stats_plugin.data.title) == "string" then
        out.title = stats_plugin.data.title
    end
    if type(stats_plugin.getPageTimeTotalStats) == "function" then
        local ok, pages, duration = pcall(stats_plugin.getPageTimeTotalStats, stats_plugin, stats_plugin.id_curr_book)
        if ok then
            out.pages_read = tonumber(pages) or 0
            out.total_time = tonumber(duration) or 0
        end
    end
    if type(stats_plugin.getCurrentBookStats) == "function" then
        local ok, duration, pages = pcall(stats_plugin.getCurrentBookStats, stats_plugin)
        if ok then
            out.session_time = tonumber(duration) or 0
            out.session_pages = tonumber(pages) or 0
        end
    end
    if type(stats_plugin.document) == "table" and type(stats_plugin.document.getPageCount) == "function" then
        local ok, pages = pcall(stats_plugin.document.getPageCount, stats_plugin.document)
        if ok then out.total_pages = tonumber(pages) or 0 end
    end
    if out.pages_read > 0 and out.total_time > 0 then
        out.avg_time_per_page = math.floor(out.total_time / out.pages_read + 0.5)
    end
    return out
end

local function queryDashboardData(blocks)
    local data = {
        stats = queryStats(),
        current_book = nil,
        series = {},
    }
    for _i, block in ipairs(blocks) do
        if block.id == "trend_graph" then
            local range = tonumber(block.range_days) or 14
            if not data.series[range] then
                data.series[range] = StatsDB.queryDailySeries(range)
            end
        elseif block.id == "current_book" then
            data.current_book = queryCurrentBookStats()
        end
    end
    return data
end

local function paintPill(bb, x, y, w, h, color)
    if w <= 0 or h <= 0 then return end
    local r = math.floor(h / 2)
    for row = 0, h - 1 do
        local dy = row - r + 0.5
        local inset = math.floor(r - math.sqrt(math.max(0, r * r - dy * dy)) + 0.5)
        local rw = w - inset * 2
        if rw > 0 then bb:paintRect(x + inset, y + row, rw, 1, color) end
    end
end

local function createProgressBar(width, height, current, target)
    local pct = 0
    if target > 0 then pct = math.min(1, math.max(0, current / target)) end
    return {
        dimen = Geom:new{ w = width, h = height },
        getSize = function(self) return self.dimen end,
        handleEvent = function() return false end,
        paintTo = function(_self, bb, x, y)
            paintPill(bb, x, y, width, height, Blitbuffer.COLOR_LIGHT_GRAY)
            local fill_w = math.floor(width * pct)
            if fill_w > 0 then
                paintPill(bb, x, y, math.max(fill_w, height), height, Blitbuffer.COLOR_BLACK)
            end
        end,
    }, math.floor(pct * 100 + 0.5)
end

local function createCard(opts)
    local card_w = opts.width
    local card_h = opts.height
    local stat_style = normalizeStatStyle(opts.stat_style)
    local value_font = Font:getFace("infofont", opts.value_size or 28)
    local label_font = Font:getFace("smallinfofont", opts.label_size or 16)
    local hdr_font = Font:getFace("smallinfofont", opts.header_size or 16)
    local padding = Screen:scaleBySize(stat_style == "outline" and 7 or 4)
    local border = stat_style == "outline" and Screen:scaleBySize(1) or 0
    local inner_w = math.max(1, card_w - (padding + border) * 2)
    local content_items = { align = "center" }

    if (opts.header or "") ~= "" then
        content_items[#content_items + 1] = TextWidget:new{
            text = opts.header,
            face = hdr_font,
            fgcolor = Blitbuffer.COLOR_BLACK,
            max_width = inner_w,
        }
        content_items[#content_items + 1] = VerticalSpan:new{ width = Screen:scaleBySize(2) }
    end
    content_items[#content_items + 1] = TextWidget:new{
        text = opts.value or "",
        face = value_font,
        max_width = inner_w,
    }
    content_items[#content_items + 1] = VerticalSpan:new{ width = Screen:scaleBySize(3) }
    content_items[#content_items + 1] = TextWidget:new{
        text = opts.label or "",
        face = label_font,
        fgcolor = Blitbuffer.COLOR_BLACK,
        max_width = inner_w,
    }

    local content = VerticalGroup:new(content_items)
    local chrome_h = (padding + border) * 2
    local actual_h = math.max(card_h, content:getSize().h + chrome_h)
    return FrameContainer:new{
        width = card_w,
        height = actual_h,
        padding = padding,
        bordersize = border,
        radius = stat_style == "outline" and Screen:scaleBySize(6) or 0,
        color = Blitbuffer.COLOR_BLACK,
        background = statsFrameBg(),
        CenterContainer:new{
            dimen = Geom:new{ w = inner_w, h = actual_h - chrome_h },
            content,
        },
    }
end

local function createCardRow(page_w, cards, stat_style, gap_w)
    stat_style = normalizeStatStyle(stat_style)
    gap_w = gap_w or Screen:scaleBySize(stat_style == "divider" and 8 or 6)
    local row_h = 0
    for _i, card in ipairs(cards) do
        local h = card:getSize().h
        if h > row_h then row_h = h end
    end
    local row = HorizontalGroup:new{ align = "center" }
    for i, card in ipairs(cards) do
        row[#row + 1] = card
        if i < #cards then
            if stat_style == "divider" then
                row[#row + 1] = CenterContainer:new{
                    dimen = Geom:new{ w = gap_w, h = row_h },
                    LineWidget:new{
                        dimen = Geom:new{
                            w = Screen:scaleBySize(1),
                            h = math.max(1, row_h - Screen:scaleBySize(12)),
                        },
                        background = Blitbuffer.COLOR_BLACK,
                    },
                }
            else
                row[#row + 1] = HorizontalSpan:new{ width = gap_w }
            end
        end
    end
    return CenterContainer:new{
        dimen = Geom:new{ w = page_w, h = row_h },
        row,
    }
end

local function createDayBookCard(width, title_text, minutes, pages, stat_style)
    width = math.max(Screen:scaleBySize(120), tonumber(width) or 0)
    local padding = Screen:scaleBySize(8)
    local inner_w = math.max(1, width - padding * 2)
    stat_style = normalizeStatStyle(stat_style)
    local title = TextWidget:new{
        text = tostring(title_text or ""),
        face = Font:getFace("smallinfofontbold", Screen:scaleBySize(10)),
        max_width = inner_w,
    }
    local gap = Screen:scaleBySize(stat_style == "divider" and 8 or stat_style == "outline" and 9 or 6)
    local pill_w = math.max(Screen:scaleBySize(48), math.floor((inner_w - gap) / 2))
    local card_h = Screen:scaleBySize(74)
    local stats = HorizontalGroup:new{
        align = "center",
        createCardRow(inner_w, {
            createCard{
                width = pill_w, height = card_h, stat_style = stat_style,
                value = minuteCount(minutes), label = _("minutes"),
            },
            createCard{
                width = pill_w, height = card_h, stat_style = stat_style,
                value = tostring(pages or 0), label = _("pages"),
            },
        }, stat_style, gap),
    }
    local content = VerticalGroup:new{
        align = "center",
        LeftContainer:new{
            dimen = Geom:new{ w = inner_w, h = title:getSize().h },
            title,
        },
        VerticalSpan:new{ width = Screen:scaleBySize(5) },
        stats,
    }
    local height = content:getSize().h + padding * 2
    return FrameContainer:new{
        width = width,
        height = height,
        padding = padding,
        bordersize = 0,
        radius = 0,
        color = Blitbuffer.COLOR_BLACK,
        background = statsFrameBg(),
        content,
    }
end

local function makeBlockPanel(page_w, content_w, title, body, extra_h)
    local padding = Screen:scaleBySize(8)
    local title_h = title ~= "" and Screen:scaleBySize(15) or 0
    local title_gap = title ~= "" and Screen:scaleBySize(5) or 0
    local body_h = body:getSize().h
    local panel_h = title_h + title_gap + body_h + padding * 2 + (extra_h or 0)
    local inner_w = content_w - padding * 2
    local panel_items = {}
    if title_h > 0 then
        panel_items[#panel_items + 1] = LeftContainer:new{
            dimen = Geom:new{ w = inner_w, h = title_h },
            TextWidget:new{
                text = title,
                face = Font:getFace("smallinfofontbold", Screen:scaleBySize(10)),
                max_width = inner_w,
            },
        }
        panel_items[#panel_items + 1] = VerticalSpan:new{ width = title_gap }
    end
    panel_items[#panel_items + 1] = body
    local panel = FrameContainer:new{
        width = content_w,
        height = panel_h,
        padding = padding,
        bordersize = 0,
        radius = 0,
        color = Blitbuffer.COLOR_BLACK,
        background = statsFrameBg(),
        VerticalGroup:new(panel_items),
    }
    return CenterContainer:new{
        dimen = Geom:new{ w = page_w, h = panel_h },
        panel,
    }, padding
end

local function createFallbackCalendarWidget(width, height)
    local text = TextWidget:new{
        text = _("Statistics calendar is unavailable"),
        face = Font:getFace("smallinfofont", Screen:scaleBySize(14)),
        fgcolor = Blitbuffer.COLOR_DARK_GRAY,
        max_width = width - Screen:scaleBySize(16),
    }
    return CenterContainer:new{
        dimen = Geom:new{ w = width, h = height },
        text,
    }
end

local function loadNativeCalendarView()
    local ok, CalendarView = pcall(require, "calendarview")
    if ok and CalendarView then return CalendarView end

    local old_path = package.path
    package.path = "plugins/statistics.koplugin/?.lua;" .. old_path
    ok, CalendarView = pcall(require, "calendarview")
    package.path = old_path
    if ok and CalendarView then return CalendarView end
end

local function calendarDayShift(stats_plugin)
    local settings = stats_plugin and stats_plugin.settings or {}
    if not settings.calendar_use_day_time_shift then return 0 end
    return (tonumber(settings.calendar_day_start_hour) or 0) * 3600
        + (tonumber(settings.calendar_day_start_minute) or 0) * 60
end

local function showCalendarDaySummary(stats_plugin, visible_day_ts, stat_style)
    stat_style = normalizeStatStyle(stat_style)
    local shift = calendarDayShift(stats_plugin)
    local period_begin = visible_day_ts + shift
    local books = StatsDB.queryBooksForPeriod(period_begin, period_begin + 86400)
    local total_duration = 0
    local total_pages = 0
    for _i, book in ipairs(books) do
        total_duration = total_duration + (book.duration or 0)
        total_pages = total_pages + (book.pages or 0)
    end

    local dialog
    local dialog_w = math.floor(math.min(Screen:getWidth(), Screen:getHeight()) * 0.9)
    dialog = ButtonDialog:new{
        width = dialog_w,
        buttons = {},
    }
    local width = math.max(Screen:scaleBySize(160), dialog_w - Screen:scaleBySize(28))
    local scroll_w = math.max(
        Screen:scaleBySize(120),
        width - ScrollableContainer:getScrollbarWidth() - Screen:scaleBySize(4)
    )
    local title_text = os.date("%B %d, %Y", visible_day_ts):gsub(" 0(%d)", " %1")
    dialog:addWidget(TitleBar:new{
        width = width,
        align = "left",
        title = title_text,
        title_face = Font:getFace("smallinfofontbold", Screen:scaleBySize(10)),
        left_icon = "close",
        left_icon_allow_flash = false,
        left_icon_tap_callback = function() UIManager:close(dialog) end,
        show_parent = dialog,
    })
    dialog:addWidget(VerticalSpan:new{ width = Screen:scaleBySize(6) })
    local items = { align = "center" }
    items[#items + 1] = createDayBookCard(scroll_w, _("Total"), total_duration, total_pages, stat_style)
    if #books == 0 then
        items[#items + 1] = VerticalSpan:new{ width = Screen:scaleBySize(8) }
        items[#items + 1] = TextWidget:new{
            text = _("No reading data"),
            face = Font:getFace("smallinfofont", Screen:scaleBySize(14)),
            fgcolor = Blitbuffer.COLOR_DARK_GRAY,
            max_width = scroll_w,
        }
    else
        for _i, book in ipairs(books) do
            items[#items + 1] = VerticalSpan:new{ width = Screen:scaleBySize(8) }
            items[#items + 1] = createDayBookCard(scroll_w, book.title, book.duration, book.pages, stat_style)
        end
    end

    local content = VerticalGroup:new(items)
    local content_h = math.min(content:getSize().h, math.floor(Screen:getHeight() * 0.58))
    local scroll_widget = ScrollableContainer:new{
        dimen = Geom:new{ w = width, h = content_h },
        show_parent = dialog,
        content,
    }
    dialog:addWidget(scroll_widget)
    dialog.ges_events.ZenDayPopupTouch = {
        GestureRange:new{ ges = "touch", range = Geom:new{ x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() } },
    }
    dialog.ges_events.ZenDayPopupSwipe = {
        GestureRange:new{ ges = "swipe", range = Geom:new{ x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() } },
    }
    dialog.ges_events.ZenDayPopupPan = {
        GestureRange:new{ ges = "pan", range = Geom:new{ x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() } },
    }
    dialog.ges_events.ZenDayPopupPanRelease = {
        GestureRange:new{ ges = "pan_release", range = Geom:new{ x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() } },
    }
    function dialog:onZenDayPopupTouch(_arg, ges)
        return scroll_widget:onScrollableTouch(nil, ges)
    end
    function dialog:onZenDayPopupSwipe(_arg, ges)
        return scroll_widget:onScrollableSwipe(nil, ges)
    end
    function dialog:onZenDayPopupPan(_arg, ges)
        return scroll_widget:onScrollablePan(nil, ges)
    end
    function dialog:onZenDayPopupPanRelease(_arg, ges)
        return scroll_widget:onScrollablePanRelease(nil, ges)
    end
    UIManager:show(dialog)
end

local function installCalendarDaySummary(calendar, stats_plugin, stat_style)
    if not (calendar and type(calendar.layout) == "table") then return end
    local year, month = tostring(calendar.cur_month or ""):match("^(%d%d%d%d)%-(%d%d)$")
    year = tonumber(year)
    month = tonumber(month)
    if not year or not month then return end
    local today_s = os.date("%Y-%m-%d", os.time())
    for _i, row in ipairs(calendar.layout) do
        for _j, day_widget in ipairs(row) do
            if day_widget and not day_widget.filler and day_widget.daynum then
                local day_ts = os.time({
                    year = year,
                    month = month,
                    day = day_widget.daynum,
                    hour = 0, min = 0, sec = 0,
                })
                local day_s = os.date("%Y-%m-%d", day_ts)
                if day_s <= today_s then
                    day_widget.callback = function()
                        showCalendarDaySummary(stats_plugin, day_ts, stat_style)
                    end
                    day_widget.onHold = function()
                        return false
                    end
                else
                    day_widget.callback = nil
                    day_widget.onHold = function()
                        return false
                    end
                end
            end
        end
    end
end

local function tuneEmbeddedCalendar(calendar)
    if not calendar or not calendar.dimen then return end

    if calendar.title_bar then
        calendar.title_bar.close_callback = nil
        calendar.title_bar.right_icon = nil
        calendar.title_bar.has_right_icon = false
        calendar.title_bar.right_button = nil
        calendar.title_bar.title_face = Font:getFace("smallinfofontbold", Screen:scaleBySize(10))
        calendar.title_bar:clear()
        calendar.title_bar:init()
    end

    if calendar.page_info then
        calendar.page_info:clear()
        calendar.page_info:resetLayout()
        calendar.page_info.dimen = Geom:new{ w = 0, h = 0 }
        calendar.page_info.getSize = function(self) return self.dimen end
    end
    if calendar.page_info_text then
        calendar.page_info_text.hold_input = nil
        calendar.page_info_text.call_hold_input_on_tap = false
    end

    if calendar.title_bar and calendar.day_names then
        local available_height = calendar.dimen.h - calendar.title_bar:getHeight()
            - calendar.day_names:getSize().h
        calendar.week_height = math.floor((available_height - 6 * calendar.inner_padding) * (1 / 6))
        calendar.week_height = math.max(Screen:scaleBySize(38), calendar.week_height)
        calendar.day_border = calendar.day_border or Screen:scaleBySize(1)
        if calendar.show_hourly_histogram then
            calendar.span_height = math.ceil((calendar.week_height - 2 * calendar.day_border)
                / (calendar.nb_book_spans + 2))
        else
            calendar.span_height = math.floor((calendar.week_height - 2 * calendar.day_border)
                / (calendar.nb_book_spans + 1))
        end
        local text_height = math.min(calendar.span_height, calendar.week_height / 3)
        calendar.span_font_size = TextBoxWidget:getFontSizeToFitHeight(text_height, 1, 0.2)
        local day_inner_width = calendar.day_width - 2 * calendar.day_border - 2 * calendar.inner_padding
        while calendar.span_font_size > 7 do
            local test_w = TextWidget:new{
                text = " 30 + 99 ",
                face = Font:getFace(calendar.font_face, calendar.span_font_size),
                bold = true,
            }
            local fits = test_w:getWidth() <= day_inner_width
            test_w:free()
            if fits then break end
            calendar.span_font_size = calendar.span_font_size - 1
        end
        calendar:_populateItems()
    end
end

local function buildContent(sc, blocks_config, data, page_w, h_padding, calendar_widgets, stat_style)
    local function sz(x) return math.floor(Screen:scaleBySize(x) * sc) end
    local function fsz(base) return math.max(8, math.floor(base * sc)) end
    stat_style = normalizeStatStyle(stat_style)
    local content_w = page_w - h_padding * 2
    local body_w = content_w - sz(16)
    local card_gap = stat_style == "divider" and sz(8) or stat_style == "outline" and sz(9) or sz(6)
    local c3_w = math.floor((body_w - card_gap * 2) / 3)
    local c4_w = math.floor((body_w - card_gap * 3) / 4)
    local card_h = sz(74)
    local stats = data.stats or {}
    local now_t = os.date("*t")
    local days_this_month = math.max(1, now_t.day)
    local days_this_year = math.max(1, now_t.yday)
    local block_hits = {}

    local function card(opts)
        opts.value_size = fsz(opts.value_size or 24)
        opts.label_size = fsz(opts.label_size or 14)
        opts.header_size = fsz(opts.header_size or 14)
        opts.stat_style = stat_style
        return createCard(opts)
    end

    local function periodCards(block)
        if block.id == "today" then
            return createCardRow(body_w, {
                card{ width = c3_w, height = card_h, value = tostring(stats.today_pages or 0), label = _("pages today") },
                card{ width = c3_w, height = card_h, value = formatTime(stats.today_duration), label = _("read today") },
                card{ width = c3_w, height = card_h, value = tostring(stats.streak or 0), label = _("day streak") },
            }, stat_style, card_gap)
        elseif block.id == "this_week" then
            local avg_p = (stats.week_pages or 0) > 0 and math.floor((stats.week_pages or 0) / 7) or 0
            local avg_t = (stats.week_duration or 0) > 0 and math.floor((stats.week_duration or 0) / 7) or 0
            return createCardRow(body_w, {
                card{ width = c4_w, height = card_h, value_size = 22, value = tostring(stats.week_pages or 0), label = _("pages") },
                card{ width = c4_w, height = card_h, value_size = 22, value = tostring(avg_p), label = _("avg pages/day") },
                card{ width = c4_w, height = card_h, value_size = 22, value = formatTime(avg_t), label = _("avg time/day") },
                card{ width = c4_w, height = card_h, value_size = 22, value = formatTime(stats.week_duration), label = _("total time") },
            }, stat_style, card_gap)
        elseif block.id == "this_month" then
            local avg_p = math.floor((stats.month_pages or 0) / days_this_month)
            local avg_t = math.floor((stats.month_duration or 0) / days_this_month)
            return createCardRow(body_w, {
                card{ width = c4_w, height = card_h, value_size = 22, value = tostring(stats.month_pages or 0), label = _("pages") },
                card{ width = c4_w, height = card_h, value_size = 22, value = tostring(avg_p), label = _("avg pages/day") },
                card{ width = c4_w, height = card_h, value_size = 22, value = formatTime(avg_t), label = _("avg time/day") },
                card{ width = c4_w, height = card_h, value_size = 22, value = formatTime(stats.month_duration), label = _("total time") },
            }, stat_style, card_gap)
        elseif block.id == "this_year" then
            local avg_t = math.floor((stats.year_duration or 0) / days_this_year)
            return createCardRow(body_w, {
                card{ width = c4_w, height = card_h, value_size = 22, value = tostring(stats.year_pages or 0), label = _("pages") },
                card{ width = c4_w, height = card_h, value_size = 22, value = formatTime(avg_t), label = _("avg time/day") },
                card{ width = c4_w, height = card_h, value_size = 22, value = formatTime(stats.year_duration), label = _("total time") },
                card{ width = c4_w, height = card_h, value_size = 22, value = tostring(stats.books_this_year or 0), label = _("books read") },
            }, stat_style, card_gap)
        elseif block.id == "all_time" then
            return createCardRow(body_w, {
                card{ width = c4_w, height = card_h, value_size = 22, value = tostring(stats.lifetime_pages or 0), label = _("total pages") },
                card{ width = c4_w, height = card_h, value_size = 22, value = formatTime(stats.avg_time_per_book), label = _("avg time/book") },
                card{ width = c4_w, height = card_h, value_size = 22, value = formatLongTime(stats.lifetime_read_time), label = _("read time") },
                card{ width = c4_w, height = card_h, value_size = 22, value = tostring(stats.books_finished or 0), label = _("finished") },
            }, stat_style, card_gap)
        elseif block.id == "personal_records" then
            return createCardRow(body_w, {
                card{ width = c3_w, height = card_h, value_size = 22, header = _("best day"), value = formatTime(stats.peak_day_duration), label = fmtPeakDay(stats.peak_day_ts) },
                card{ width = c3_w, height = card_h, value_size = 22, header = _("best week"), value = formatTime(stats.peak_week_duration), label = fmtPeakWeek(stats.peak_week_ts) },
                card{ width = c3_w, height = card_h, value_size = 22, header = _("best month"), value = formatLongTime(stats.peak_month_duration), label = fmtPeakMonth(stats.peak_month_ts) },
            }, stat_style, card_gap)
        elseif block.id == "library" then
            return createCardRow(body_w, {
                card{ width = c3_w, height = card_h, value = tostring(stats.total_books or 0), label = _("total books") },
                card{ width = c3_w, height = card_h, value = tostring(stats.books_reading or 0), label = _("reading") },
                card{ width = c3_w, height = card_h, value = tostring(stats.books_finished or 0), label = _("finished") },
            }, stat_style, card_gap)
        elseif block.id == "current_book" then
            local book = data.current_book or {}
            local avg = book.avg_time_per_page or 0
            return createCardRow(body_w, {
                card{ width = c4_w, height = card_h, value_size = 22, value = formatLongTime(book.total_time), label = _("total time") },
                card{ width = c4_w, height = card_h, value_size = 22, value = tostring(book.pages_read or 0), label = _("pages read") },
                card{ width = c4_w, height = card_h, value_size = 22, value = formatTime(avg), label = _("time/page") },
                card{ width = c4_w, height = card_h, value_size = 22, value = tostring(book.session_pages or 0), label = _("session pages") },
            }, stat_style, card_gap)
        end
    end

    local function graphBlock(block)
        local series = data.series[block.range_days or 14] or {}
        local graph = LineGraph:new{
            width = body_w,
            height = sz(116),
            series = series,
            metric = block.metric,
            empty_text = _("No reading data"),
            label_left = shortDate(series[1] and series[1].date),
            label_right = shortDate(series[#series] and series[#series].date),
            x_labels = graphDateLabels(series, 5),
            axis_color = Blitbuffer.COLOR_BLACK,
            dot_radius = block.range_days == 90 and math.max(1, sz(1)) or math.max(1, sz(3)),
        }
        return VerticalGroup:new{
            CenterContainer:new{ dimen = Geom:new{ w = body_w, h = graph:getSize().h }, graph },
        }
    end

    local function goalBlock()
        local metric = "pages"
        local current = stats.today_pages or 0
        local target = 30
        local unit = _("pages")
        local bar, pct = createProgressBar(body_w - sz(20), sz(9), current, target)
        local title = tostring(current) .. " / " .. tostring(target) .. " " .. unit
        local summary = TextWidget:new{
            text = title .. " (" .. tostring(pct) .. "%)",
            face = Font:getFace("infofont", fsz(18)),
        }
        local note = TextWidget:new{
            text = metric == "time" and _("Daily time goal") or _("Daily pages goal"),
            face = Font:getFace("smallinfofont", fsz(13)),
            fgcolor = Blitbuffer.COLOR_DARK_GRAY,
        }
        return VerticalGroup:new{
            CenterContainer:new{ dimen = Geom:new{ w = body_w, h = sz(24) }, summary },
            CenterContainer:new{ dimen = Geom:new{ w = body_w, h = sz(20) }, bar },
            CenterContainer:new{ dimen = Geom:new{ w = body_w, h = sz(20) }, note },
        }
    end

    local function calendarBlock()
        local stats_plugin = PluginLoader:getPluginInstance("statistics")
        if type(stats_plugin) ~= "table" then
            return createFallbackCalendarWidget(body_w, sz(470))
        end
        if type(stats_plugin.insertDB) == "function" then
            pcall(stats_plugin.insertDB, stats_plugin)
        end
        local CalendarView = loadNativeCalendarView()
        if not CalendarView then
            return createFallbackCalendarWidget(body_w, sz(470))
        end
        local settings = stats_plugin.settings or {}
        local calendar_h = sz(470)
        local calendar = CalendarView:new{
            reader_statistics = stats_plugin,
            width = body_w,
            height = calendar_h,
            cur_month = loadCalendarMonthConfig(),
            start_day_of_week = settings.calendar_start_day_of_week,
            nb_book_spans = math.max(3, tonumber(settings.calendar_nb_book_spans) or 3),
            show_hourly_histogram = false,
            browse_future_months = settings.calendar_browse_future_months,
        }
        tuneEmbeddedCalendar(calendar)
        Background.clearWhiteBackgrounds(calendar, 40)
        local orig_go_to_month = calendar.goToMonth
        calendar.goToMonth = function(self_cal, month, ...)
            local result = orig_go_to_month(self_cal, month, ...)
            saveCalendarMonthConfig(self_cal.cur_month)
            return result
        end
        local orig_next_month = calendar.nextMonth
        calendar.nextMonth = function(self_cal, ...)
            local result = orig_next_month(self_cal, ...)
            saveCalendarMonthConfig(self_cal.cur_month)
            return result
        end
        local orig_prev_month = calendar.prevMonth
        calendar.prevMonth = function(self_cal, ...)
            local result = orig_prev_month(self_cal, ...)
            saveCalendarMonthConfig(self_cal.cur_month)
            return result
        end
        local orig_populate_items = calendar._populateItems
        calendar._populateItems = function(self_cal, ...)
            local result = orig_populate_items(self_cal, ...)
            installCalendarDaySummary(self_cal, stats_plugin, stat_style)
            Background.clearWhiteBackgrounds(self_cal, 40)
            return result
        end
        installCalendarDaySummary(calendar, stats_plugin, stat_style)
        calendar.show_parent = nil
        calendar.covers_fullscreen = false
        calendar.close_callback = nil
        calendar.onClose = function() return true end
        calendar.onMultiSwipe = function() return false end
        local orig_calendar_paintTo = calendar.paintTo
        calendar.paintTo = function(self_cal, bb, x, y)
            Background.clearWhiteBackgrounds(self_cal, 40)
            return orig_calendar_paintTo(self_cal, bb, x, y)
        end
        calendar.onSwipe = function(_self, _arg, ges_ev)
            if not ges_ev then return false end
            local direction = ges_ev.direction
            if direction == "west" then
                calendar:nextMonth()
                return true
            elseif direction == "east" then
                calendar:prevMonth()
                return true
            end
            return false
        end
        return CenterContainer:new{
            dimen = Geom:new{ w = content_w - sz(16), h = calendar:getSize().h },
            calendar,
        }, calendar
    end

    local items = { align = "center" }
    local y_acc = sz(8)
    items[#items + 1] = VerticalSpan:new{ width = sz(8) }

    for i, block in ipairs(blocks_config) do
        local body
        if block.id == "trend_graph" then
            body = graphBlock(block)
        elseif block.id == "goal_progress" then
            body = goalBlock(block)
        elseif block.id == "calendar" then
            local calendar
            body, calendar = calendarBlock()
            if calendar_widgets then
                calendar_widgets[i] = calendar or body
            end
        else
            body = periodCards(block)
        end

        if body then
            local panel = makeBlockPanel(page_w, content_w, displayBlockTitle(block), body)
            local panel_h = panel:getSize().h
            items[#items + 1] = panel
            block_hits[#block_hits + 1] = {
                block_idx = i,
                y_start = y_acc,
                y_end = y_acc + panel_h,
            }
            y_acc = y_acc + panel_h
            if i < #blocks_config then
                local gap = sz(8)
                items[#items + 1] = VerticalSpan:new{ width = gap }
                y_acc = y_acc + gap
            end
        end
    end

    return VerticalGroup:new(items), block_hits
end

function StatsPage.create(createStatusRow, repaintTitleBar)
    local blocks_config = loadBlocksConfig()
    local stat_style = loadStatStyleConfig()
    local data = queryDashboardData(blocks_config)
    local menu = StandalonePage.create_menu{
        name = "stats",
        title = " ",
    }
    StandalonePage.prepare_shell(menu)
    StandalonePage.apply_status_row(menu, {
        createStatusRow = createStatusRow,
        repaintTitleBar = repaintTitleBar,
    })

    local tb = menu.title_bar
    local tb_h = tb and tb:getSize().h or 0
    local body_h = (menu.inner_dimen and menu.inner_dimen.h or menu.dimen.h) - tb_h
    local page_w = menu.inner_dimen and menu.inner_dimen.w or Screen:getWidth()
    local h_padding = 0
    local scrollbar_w = ScrollableContainer:getScrollbarWidth()
    local content_page_w = math.max(Screen:scaleBySize(120), page_w - scrollbar_w)
    local block_hits
    local calendar_widgets = {}
    local scroll_container

    local function buildScrollable()
        calendar_widgets = {}
        local content, hits = buildContent(1.0, blocks_config, data, content_page_w, h_padding, calendar_widgets, stat_style)
        local bottom_pad = Screen:scaleBySize(18)
        content[#content + 1] = VerticalSpan:new{ width = bottom_pad }
        content:resetLayout()
        local content_h = content:getSize().h
        local remaining = body_h - content_h
        if remaining > 0 then
            content[#content + 1] = VerticalSpan:new{ width = remaining }
            content:resetLayout()
        end
        scroll_container = ScrollableContainer:new{
            dimen = Geom:new{ w = page_w, h = body_h },
            show_parent = menu,
            ignore_events = { "hold", "hold_pan", "hold_release" },
            content,
        }
        useLibraryBgScrollBuffer(scroll_container)
        menu.cropping_widget = scroll_container
        return scroll_container, hits
    end

    local content
    content, block_hits = buildScrollable()

    local function rebuildStats()
        data = queryDashboardData(blocks_config)
        local new_content
        new_content, block_hits = buildScrollable()
        StandalonePage.mount_body(menu, new_content)
        UIManager:setDirty(menu, "ui")
    end

    local function closeConfigDialog()
        if menu._zen_block_dlg then
            UIManager:close(menu._zen_block_dlg)
            menu._zen_block_dlg = nil
        end
    end

    local function showRangeMenu(block_idx)
        closeConfigDialog()
        local buttons = {}
        for _i, range in ipairs({ 7, 14, 30, 90 }) do
            local selected = blocks_config[block_idx].range_days == range
            buttons[#buttons + 1] = {{
                text = tostring(range) .. _(" days") .. (selected and "  \u{2713}" or ""),
                enabled = not selected,
                callback = function()
                    UIManager:close(menu._zen_block_dlg)
                    menu._zen_block_dlg = nil
                    blocks_config[block_idx].range_days = range
                    saveBlocksConfig(blocks_config)
                    rebuildStats()
                end,
            }}
        end
        menu._zen_block_dlg = ButtonDialog:new{
            title = _("Graph range"),
            title_align = "center",
            buttons = buttons,
        }
        UIManager:show(menu._zen_block_dlg)
    end

    local function showMetricMenu(block_idx)
        closeConfigDialog()
        local buttons = {}
        for _i, item in ipairs({
            { id = "pages", text = _("Pages") },
            { id = "time", text = _("Time") },
        }) do
            local current_metric = blocks_config[block_idx].metric
            if current_metric == "duration" then current_metric = "time" end
            local selected = current_metric == item.id
            buttons[#buttons + 1] = {{
                text = item.text .. (selected and "  \u{2713}" or ""),
                enabled = not selected,
                callback = function()
                    UIManager:close(menu._zen_block_dlg)
                    menu._zen_block_dlg = nil
                    blocks_config[block_idx].metric = item.id
                    saveBlocksConfig(blocks_config)
                    rebuildStats()
                end,
            }}
        end
        menu._zen_block_dlg = ButtonDialog:new{
            title = _("Graph metric"),
            title_align = "center",
            buttons = buttons,
        }
        UIManager:show(menu._zen_block_dlg)
    end

    local function showCalendarMonthMenu(block_idx)
        closeConfigDialog()
        local calendar = calendar_widgets[block_idx]
        if not calendar then return end

        local min_month = calendar.min_month or calendar.cur_month or os.date("%Y-%m", os.time())
        local max_month = calendar.max_month or calendar.cur_month or os.date("%Y-%m", os.time())
        local selected_month = calendar.cur_month or max_month
        if calendar.browse_future_months then
            max_month = monthShift(max_month, 12)
        end
        if selected_month > max_month then max_month = selected_month end
        if selected_month < min_month then min_month = selected_month end

        local buttons = {}
        local month = max_month
        local guard = 0
        while month >= min_month and guard < 240 do
            local item_month = month
            local selected = item_month == selected_month
            buttons[#buttons + 1] = {{
                text = monthLabel(item_month) .. (selected and "  \u{2713}" or ""),
                enabled = not selected,
                callback = function()
                    UIManager:close(menu._zen_block_dlg)
                    menu._zen_block_dlg = nil
                    if type(calendar.goToMonth) == "function" then
                        calendar:goToMonth(item_month)
                    else
                        calendar.cur_month = item_month
                        if type(calendar._populateItems) == "function" then
                            calendar:_populateItems()
                        end
                    end
                    UIManager:setDirty(menu, "ui")
                end,
            }}
            month = monthShift(month, -1)
            guard = guard + 1
        end

        menu._zen_block_dlg = ButtonDialog:new{
            title = _("Date"),
            title_align = "center",
            buttons = buttons,
        }
        UIManager:show(menu._zen_block_dlg)
    end

    local function statStyleLabel(style)
        style = normalizeStatStyle(style)
        if style == "outline" then return _("Outline") end
        if style == "none" then return _("None") end
        return _("Divider")
    end

    local function showStatStyleMenu()
        closeConfigDialog()
        local buttons = {}
        for _i, item in ipairs({
            { id = "divider", text = _("Divider") },
            { id = "outline", text = _("Outline") },
            { id = "none", text = _("None") },
        }) do
            local selected = stat_style == item.id
            buttons[#buttons + 1] = {{
                text = item.text .. (selected and "  \u{2713}" or ""),
                enabled = not selected,
                callback = function()
                    UIManager:close(menu._zen_block_dlg)
                    menu._zen_block_dlg = nil
                    stat_style = item.id
                    saveStatStyleConfig(stat_style)
                    rebuildStats()
                end,
            }}
        end
        menu._zen_block_dlg = ButtonDialog:new{
            title = _("Stat separators"),
            title_align = "center",
            buttons = buttons,
        }
        UIManager:show(menu._zen_block_dlg)
    end

    local function showWidgetsMenu(block_idx)
        closeConfigDialog()
        local current = blocks_config[block_idx]
        local buttons = {}
        for _i, type_id in ipairs(ALL_BLOCK_TYPES) do
            local selected = type_id == current.id
            buttons[#buttons + 1] = {{
                text = blockTitle({ id = type_id }) .. (selected and "  \u{2713}" or ""),
                enabled = not selected,
                callback = function()
                    UIManager:close(menu._zen_block_dlg)
                    menu._zen_block_dlg = nil
                    blocks_config[block_idx] = defaultBlock(type_id)
                    saveBlocksConfig(blocks_config)
                    rebuildStats()
                end,
            }}
        end

        menu._zen_block_dlg = ButtonDialog:new{
            title = _("Widgets"),
            title_align = "center",
            buttons = buttons,
        }
        UIManager:show(menu._zen_block_dlg)
    end

    local function showBlockMenu(block_idx)
        closeConfigDialog()
        local current = blocks_config[block_idx]
        local buttons = {}
        if current.id == "trend_graph" then
            buttons[#buttons + 1] = {{
                text = _("Metric") .. ": " .. (current.metric == "time" and _("Time") or _("Pages")),
                callback = function() showMetricMenu(block_idx) end,
            }}
            buttons[#buttons + 1] = {{
                text = _("Range") .. ": " .. tostring(current.range_days or 14) .. _(" days"),
                callback = function() showRangeMenu(block_idx) end,
            }}
        end
        if current.id == "calendar" then
            local calendar = calendar_widgets[block_idx]
            buttons[#buttons + 1] = {{
                text = _("Date") .. ": " .. tostring(calendar and calendar.cur_month or ""),
                callback = function() showCalendarMonthMenu(block_idx) end,
            }}
        end
        if blockHasStatSeparators(current) then
            buttons[#buttons + 1] = {{
                text = _("Stat separators") .. ": " .. statStyleLabel(stat_style),
                callback = function() showStatStyleMenu() end,
            }}
        end

        buttons[#buttons + 1] = {{
            text = _("Widgets"),
            callback = function() showWidgetsMenu(block_idx) end,
        }}

        menu._zen_block_dlg = ButtonDialog:new{
            title = _("Customize block"),
            title_align = "center",
            buttons = buttons,
        }
        UIManager:show(menu._zen_block_dlg)
    end

    if not menu.ges_events then menu.ges_events = {} end
    menu.ges_events.ZenStatsHold = {
        GestureRange:new{
            ges = "hold",
            range = Geom:new{ x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() },
        },
    }
    local top_tap_zone_h = math.max(1, math.floor(Screen:getHeight() * 0.05))
    menu.ges_events.ZenStatsTopTap = {
        GestureRange:new{
            ges = "tap",
            range = Geom:new{ x = 0, y = 0, w = Screen:getWidth(), h = top_tap_zone_h },
        },
    }
    local function openTopMenuFromTap(ges)
        if not (ges and ges.pos and ges.pos.y < top_tap_zone_h) then return false end
        local ok_fm, FileManager = pcall(require, "apps/filemanager/filemanager")
        local fm_menu = ok_fm and FileManager.instance and FileManager.instance.menu
        if fm_menu and fm_menu.activation_menu ~= "swipe" then
            fm_menu:onShowMenu(fm_menu:_getTabIndexFromLocation(ges))
            return true
        end
        local ok_rui, RUI = pcall(require, "apps/reader/readerui")
        local reader_menu = ok_rui and RUI.instance and RUI.instance.menu
        if reader_menu and reader_menu.activation_menu ~= "swipe" then
            reader_menu:onShowMenu(reader_menu:_getTabIndexFromLocation(ges))
            return true
        end
        return false
    end
    function menu:onZenStatsTopTap(_arg, ges)
        return openTopMenuFromTap(ges)
    end
    if tb then
        tb.ges_events = tb.ges_events or {}
        tb.ges_events.ZenStatsTopTap = {
            GestureRange:new{
                ges = "tap",
                range = Geom:new{ x = 0, y = 0, w = Screen:getWidth(), h = top_tap_zone_h },
            },
        }
        function tb:onZenStatsTopTap(_arg, ges)
            return openTopMenuFromTap(ges)
        end
    end
    local orig_onGesture = menu.onGesture
    function menu:onGesture(ges)
        if ges and ges.ges == "tap" and openTopMenuFromTap(ges) then
            return true
        end
        if orig_onGesture then return orig_onGesture(self, ges) end
    end
    function menu:onZenStatsHold(_ges_event, ges)
        local offset_y = self.dimen and self.dimen.y or 0
        local scroll_y = scroll_container and scroll_container.getScrolledOffset
            and scroll_container:getScrolledOffset().y or 0
        local content_y = ges.pos.y - offset_y - tb_h + scroll_y
        if content_y < 0 then return false end
        for _i, hit in ipairs(block_hits) do
            if content_y >= hit.y_start and content_y < hit.y_end then
                showBlockMenu(hit.block_idx)
                return true
            end
        end
        return false
    end

    StandalonePage.mount_body(menu, content)

    if menu.page_info then
        while #menu.page_info > 0 do table.remove(menu.page_info) end
        menu.page_info:resetLayout()
    end

    menu.close_callback = function()
        UIManager:close(menu)
    end

    active_stats_menus[#active_stats_menus + 1] = menu
    local orig_onCloseWidget = menu.onCloseWidget
    function menu:onCloseWidget(...)
        for i = #active_stats_menus, 1, -1 do
            if rawequal(active_stats_menus[i], self) then
                table.remove(active_stats_menus, i)
                break
            end
        end
        if self._zen_block_dlg then
            UIManager:close(self._zen_block_dlg)
            self._zen_block_dlg = nil
        end
        if orig_onCloseWidget then
            return orig_onCloseWidget(self, ...)
        end
    end

    UIManager:scheduleIn(0, function()
        UIManager:setDirty(menu, "flashui")
    end)

    return menu
end

function StatsPage.closeAll()
    for i = #active_stats_menus, 1, -1 do
        local menu = active_stats_menus[i]
        if menu then
            if menu._zen_block_dlg then
                UIManager:close(menu._zen_block_dlg)
                menu._zen_block_dlg = nil
            end
            UIManager:close(menu)
        end
        active_stats_menus[i] = nil
    end
end

local function register_stats_api(zen_plugin)
    if not zen_plugin or type(zen_plugin.config) ~= "table" then return end
    SharedState.register(zen_plugin, { stats = StatsPage })
end

SharedState.registerLoader("stats", register_stats_api)

return StatsPage
