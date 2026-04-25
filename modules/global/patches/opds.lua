-- Zen UI OPDS browser enhancements:
--   - Back chevron on left title button (closes at root, navigates back in catalog)
--   - Hamburger menu on right title button
--   - Footer return arrow hidden (navigation via title buttons)
--   - Cover art in browse list (downloaded async, no coverbrowser dependency)
--   - Left-aligned single-column download dialog (context_menu style)
--   - Default download folder falls back to Device.home_dir

local function apply_opds()
    local ok_opds, OPDSBrowser = pcall(require, "opdsbrowser")
    if not ok_opds or not OPDSBrowser then return end
    if OPDSBrowser._zen_opds_patched then return end
    OPDSBrowser._zen_opds_patched = true

    local Blitbuffer      = require("ffi/blitbuffer")
    local CenterContainer = require("ui/widget/container/centercontainer")
    local Font            = require("ui/font")
    local FrameContainer  = require("ui/widget/container/framecontainer")
    local Geom            = require("ui/geometry")
    local GestureRange    = require("ui/gesturerange")
    local HGroup          = require("ui/widget/horizontalgroup")
    local HSpan           = require("ui/widget/horizontalspan")
    local ImageWidget     = require("ui/widget/imagewidget")
    local InputContainer  = require("ui/widget/container/inputcontainer")
    local LineWidget      = require("ui/widget/linewidget")
    local Menu            = require("ui/widget/menu")
    local Size            = require("ui/size")
    local TextBoxWidget   = require("ui/widget/textboxwidget")
    local TextWidget      = require("ui/widget/textwidget")
    local TopContainer    = require("ui/widget/container/topcontainer")
    local UIManager       = require("ui/uimanager")
    local VGroup          = require("ui/widget/verticalgroup")
    local VSpan           = require("ui/widget/verticalspan")
    local logger          = require("logger")
    local Screen          = require("device").screen

    -- Cover cache: [url] → { bb } | { failed = true }  (session-scoped)
    local _cover_cache = {}

    -- Synchronous HTTP fetch; runs inside a UIManager-scheduled callback.
    local function fetch_bytes(cover_url, creds)
        local ok_h, http        = pcall(require, "socket.http")
        local ok_l, ltn12       = pcall(require, "ltn12")
        local ok_su, socketutil = pcall(require, "socketutil")
        if not ok_h or not ok_l then
            logger.warn("OPDS covers: missing socket.http or ltn12")
            return nil
        end
        logger.dbg("OPDS cover fetch start:", cover_url)
        local chunks = {}
        if ok_su then socketutil:set_timeout(10, 30) end
        local _, code = http.request{
            url      = cover_url,
            sink     = ok_su and socketutil.table_sink(chunks) or ltn12.sink.table(chunks),
            user     = creds and creds.username,
            password = creds and creds.password,
            headers  = { ["Accept-Encoding"] = "identity" },
        }
        if ok_su then socketutil:reset_timeout() end
        local body = code == 200 and table.concat(chunks) or nil
        logger.dbg("OPDS cover fetch done:", cover_url, "code=", code, "bytes=", body and #body or 0)
        return body
    end

    -- Sequential async cover loader. Returns a cancel function.
    local function start_cover_queue(queue, creds)
        if #queue == 0 then return function() end end
        logger.dbg("OPDS cover queue started, items=", #queue)
        local stopped = false
        local idx     = 1
        local next_cover
        next_cover = function()
            if stopped or idx > #queue then return end
            local item = queue[idx]; idx = idx + 1
            local u = item.entry.cover_url
            local cached = _cover_cache[u]
            if cached then
                logger.dbg("OPDS cover cache hit:", u, "has_bb=", cached.bb ~= nil)
                if cached.bb and not item.entry.cover_bb then
                    item.entry.cover_bb = cached.bb
                    if not stopped then item.widget:update() end
                end
                if not stopped then UIManager:nextTick(next_cover) end
                return
            end
            _cover_cache[u] = { loading = true }
            local bytes = fetch_bytes(u, creds)
            if stopped then return end
            if bytes then
                local ok_ri, RI = pcall(require, "ui/renderimage")
                logger.dbg("OPDS cover renderimage require ok=", ok_ri, "size=", item.cover_w, "x", item.cover_h)
                if ok_ri then
                    local ok_bb, bb = pcall(function()
                        return RI:renderImageData(bytes, #bytes, false,
                            item.cover_w, item.cover_h)
                    end)
                    logger.dbg("OPDS cover renderImageData ok=", ok_bb, "bb=", bb ~= nil)
                    if ok_bb and bb then
                        _cover_cache[u] = { bb = bb }
                        item.entry.cover_bb = bb
                        if not stopped then item.widget:update() end
                    else
                        logger.warn("OPDS cover renderImageData failed for:", u, ok_bb, bb)
                        _cover_cache[u] = { failed = true }
                    end
                else
                    logger.warn("OPDS cover: failed to require ui/renderimage")
                    _cover_cache[u] = { failed = true }
                end
            else
                logger.warn("OPDS cover fetch returned nil for:", u)
                _cover_cache[u] = { failed = true }
            end
            if not stopped and idx <= #queue then
                UIManager:scheduleIn(0.15, next_cover)
            end
        end
        UIManager:scheduleIn(0.5, next_cover)
        return function()
            stopped = true
            UIManager:unschedule(next_cover)
            -- Clear stale 'loading' markers so interrupted items are re-queued on page revisit
            for u, v in pairs(_cover_cache) do
                if v.loading then _cover_cache[u] = nil end
            end
        end
    end

    -- Custom list item: cover on left, title/author/mandatory on right.
    local PAD   = Size.padding.small
    local PAD_V = 6

    local _corner_radius = Screen:scaleBySize(8)
    local _plugin = rawget(_G, "__ZEN_UI_PLUGIN")

    local function rounded_corners_enabled()
        local plug = _plugin or rawget(_G, "__ZEN_UI_PLUGIN")
        return plug
            and type(plug.config) == "table"
            and type(plug.config.features) == "table"
            and plug.config.features.browser_cover_rounded_corners == true
    end

    local function paintCornerMasks(bb, tx, ty, tw, th, r)
        local color = Blitbuffer.COLOR_WHITE
        for j = 0, r - 1 do
            local inner = math.sqrt(r * r - (r - j) * (r - j))
            local cut   = math.ceil(r - inner)
            if cut > 0 then
                bb:paintRect(tx,            ty + j,          cut, 1, color)
                bb:paintRect(tx + tw - cut, ty + j,          cut, 1, color)
                bb:paintRect(tx,            ty + th - 1 - j, cut, 1, color)
                bb:paintRect(tx + tw - cut, ty + th - 1 - j, cut, 1, color)
            end
        end
    end

    local function paintCornerBorderArcs(bb, tx, ty, tw, th, r, color)
        for j = 0, r - 1 do
            for c = 0, r - 1 do
                local dx   = r - c - 0.5
                local dy   = r - j - 0.5
                local dist = math.sqrt(dx * dx + dy * dy)
                if dist >= r - 1 and dist <= r then
                    bb:paintRect(tx + c,          ty + j,           1, 1, color)
                    bb:paintRect(tx + tw - 1 - c, ty + j,           1, 1, color)
                    bb:paintRect(tx + c,          ty + th - 1 - j,  1, 1, color)
                    bb:paintRect(tx + tw - 1 - c, ty + th - 1 - j,  1, 1, color)
                end
            end
        end
        -- straight edges connecting the corner arcs
        bb:paintRect(tx + r,      ty,           tw - 2*r, 1, color)  -- top
        bb:paintRect(tx + r,      ty + th - 1,  tw - 2*r, 1, color)  -- bottom
        bb:paintRect(tx,          ty + r,       1, th - 2*r, color)  -- left
        bb:paintRect(tx + tw - 1, ty + r,       1, th - 2*r, color)  -- right
    end

    -- Proportional font size matching browser_list_item_layout's _fontSize formula.
    local function opds_fontSize(nominal, max_size, dimen_h)
        local sf = Screen:scaleBySize(1000000) * (1/1000000)
        local fs = math.floor(nominal * dimen_h * (1/64) / sf)
        if max_size and fs >= max_size then return max_size end
        return fs
    end

    local OPDSItem = InputContainer:extend{
        entry = nil, cover_w = nil, cover_h = nil,
        item_w = nil, item_h = nil,
        show_parent = nil, menu = nil,
    }

    function OPDSItem:init()
        self.dimen = Geom:new{ w = self.item_w, h = self.item_h }
        self.ges_events = {
            TapSelect  = { GestureRange:new{ ges = "tap",  range = self.dimen } },
            HoldSelect = { GestureRange:new{ ges = "hold", range = self.dimen } },
        }
        local entry  = self.entry
        local text_w = self.item_w - self.cover_w - PAD * 3
        local text_h = self.item_h - PAD_V * 2
        local cover_inner
        if entry.cover_bb then
            logger.dbg("OPDSItem: rendering cover image for", entry.title or "?")
            cover_inner = ImageWidget:new{
                image = entry.cover_bb, width = self.cover_w, height = self.cover_h,
                image_disposable = false,
            }
        else
            -- LineWidget has a proper getSize(); bare FrameContainer without a child crashes
            -- when CenterContainer:paintTo calls getSize() on it.
            cover_inner = LineWidget:new{
                dimen = Geom:new{ w = self.cover_w, h = self.cover_h },
                background = Blitbuffer.COLOR_LIGHT_GRAY,
            }
        end
        local text_group = VGroup:new{ align = "left" }
        local title = entry.title or entry.text or ""
        local fs_title = opds_fontSize(18, 21, self.item_h)
        local fs_meta  = opds_fontSize(14, 18, self.item_h)
        table.insert(text_group, TextBoxWidget:new{
            text = title, face = Font:getFace("cfont", fs_title),
            width = text_w, bold = true, alignment = "left",
        })
        if entry.author and entry.author ~= "" then
            table.insert(text_group, VSpan:new{ width = Size.padding.tiny })
            table.insert(text_group, TextBoxWidget:new{
                text = entry.author, face = Font:getFace("cfont", fs_meta),
                width = text_w, alignment = "left",
            })
        end
        if entry.mandatory and tostring(entry.mandatory) ~= "" then
            table.insert(text_group, VSpan:new{ width = Size.padding.tiny })
            table.insert(text_group, TextWidget:new{
                text = tostring(entry.mandatory), face = Font:getFace("cfont", 12),
                max_width = text_w, fgcolor = Blitbuffer.COLOR_DARK_GRAY,
            })
        end
        self[1] = FrameContainer:new{
            width = self.item_w, height = self.item_h,
            bordersize = 0, padding = 0,
            background = Blitbuffer.COLOR_WHITE,
            VGroup:new{
                align = "left",
                VSpan:new{ width = PAD_V },
                HGroup:new{
                    align = "top",
                    HSpan:new{ width = PAD },
                    CenterContainer:new{
                        dimen = Geom:new{ w = self.cover_w, h = self.cover_h },
                        cover_inner,
                    },
                    HSpan:new{ width = PAD },
                    TopContainer:new{
                        dimen = Geom:new{ w = text_w, h = text_h },
                        text_group,
                    },
                    HSpan:new{ width = PAD },
                },
                VSpan:new{ width = PAD_V },
            },
        }
    end

    -- InputContainer.paintTo (inherited from WidgetContainer) never stores x,y back;
    -- record them here so update() can use the real screen position.
    function OPDSItem:paintTo(bb, x, y)
        self._screen_x = x
        self._screen_y = y
        InputContainer.paintTo(self, bb, x, y)
        if not rounded_corners_enabled() then return end
        -- cover is at PAD from left, PAD_V from top
        paintCornerMasks(bb, x + PAD, y + PAD_V, self.cover_w, self.cover_h, _corner_radius)
        paintCornerBorderArcs(bb, x + PAD, y + PAD_V, self.cover_w, self.cover_h, _corner_radius, Blitbuffer.COLOR_BLACK)
    end

    function OPDSItem:update()
        local x = self._screen_x or 0
        local y = self._screen_y or 0
        self:init()
        local dimen = Geom:new{ x = x, y = y, w = self.item_w, h = self.item_h }
        UIManager:setDirty(self.show_parent, function() return "ui", dimen end)
    end

    function OPDSItem:onTapSelect()
        if not self[1].dimen then return end
        self.menu:onMenuSelect(self.entry); return true
    end

    function OPDSItem:onHoldSelect()
        if not self[1].dimen then return end
        self.menu:onMenuHold(self.entry); return true
    end

    -- Mosaic grid cell: portrait cover centered, truncated title below.
    local OPDSMosaicItem = InputContainer:extend{
        entry = nil, cover_w = nil, cover_h = nil,
        cell_w = nil, cell_h = nil,
        show_parent = nil, menu = nil,
    }

    function OPDSMosaicItem:init()
        self.dimen = Geom:new{ w = self.cell_w, h = self.cell_h }
        self.ges_events = {
            TapSelect  = { GestureRange:new{ ges = "tap",  range = self.dimen } },
            HoldSelect = { GestureRange:new{ ges = "hold", range = self.dimen } },
        }
        local entry = self.entry
        local cover_inner
        if entry.cover_bb then
            cover_inner = ImageWidget:new{
                image = entry.cover_bb, width = self.cover_w, height = self.cover_h,
                image_disposable = false,
            }
        else
            cover_inner = LineWidget:new{
                dimen = Geom:new{ w = self.cover_w, h = self.cover_h },
                background = Blitbuffer.COLOR_LIGHT_GRAY,
            }
        end
        self[1] = FrameContainer:new{
            width = self.cell_w, height = self.cell_h,
            bordersize = 0, padding = 0,
            background = Blitbuffer.COLOR_WHITE,
            CenterContainer:new{
                dimen = Geom:new{ w = self.cell_w, h = self.cell_h },
                cover_inner,
            },
        }
    end

    function OPDSMosaicItem:paintTo(bb, x, y)
        self._screen_x = x
        self._screen_y = y
        InputContainer.paintTo(self, bb, x, y)
        if not rounded_corners_enabled() then return end
        -- cover is centered in the cell
        local cx = x + math.floor((self.cell_w - self.cover_w) / 2)
        local cy = y + math.floor((self.cell_h - self.cover_h) / 2)
        paintCornerMasks(bb, cx, cy, self.cover_w, self.cover_h, _corner_radius)
        paintCornerBorderArcs(bb, cx, cy, self.cover_w, self.cover_h, _corner_radius, Blitbuffer.COLOR_BLACK)
    end

    function OPDSMosaicItem:update()
        local x = self._screen_x or 0
        local y = self._screen_y or 0
        self:init()
        local dimen = Geom:new{ x = x, y = y, w = self.cell_w, h = self.cell_h }
        UIManager:setDirty(self.show_parent, function() return "ui", dimen end)
    end

    function OPDSMosaicItem:onTapSelect()
        if not self[1].dimen then return end
        self.menu:onMenuSelect(self.entry); return true
    end

    function OPDSMosaicItem:onHoldSelect()
        if not self[1].dimen then return end
        self.menu:onMenuHold(self.entry); return true
    end

    -- Cover-aware updateItems; supports mosaic grid and list layouts matched to library mode.
    -- The root catalog list (paths empty) always uses a fixed list with placeholder covers.
    function OPDSBrowser:updateItems(select_number, no_recalculate_dimen)
        -- Root screen: always list, 10 per page, grey placeholder covers.
        if #(self.paths or {}) == 0 then
            if self._zen_halt then self._zen_halt(); self._zen_halt = nil end
            local old_dimen = self.dimen and self.dimen:copy()
            self.layout = {}
            self.item_group:clear()
            self.page_info:resetLayout()
            self.return_button:resetLayout()
            self.content_group:resetLayout()

            local avail_h = self.inner_dimen.h
            if not self.no_title and self.title_bar then
                avail_h = avail_h - self.title_bar:getHeight()
            end
            if self.page_return_arrow and self.page_info_text then
                avail_h = avail_h
                    - math.max(self.page_return_arrow:getSize().h,
                               self.page_info_text:getSize().h)
                    - Size.padding.button
            end
            local list_perpage = 8
            self.item_height = math.floor(avail_h / list_perpage)
            local cover_h = math.max(1, self.item_height - PAD_V * 2)
            local cover_w = math.floor(cover_h * 2 / 3)
            self.perpage    = list_perpage
            self.page_num   = math.max(1, math.ceil(#self.item_table / self.perpage))
            if self.page > self.page_num then self.page = self.page_num end
            self.item_width = self.inner_dimen.w
            self.item_dimen = Geom:new{ x = 0, y = 0, w = self.item_width, h = self.item_height }

            local idx_s = (self.page - 1) * self.perpage + 1
            local idx_e = math.min(self.page * self.perpage, #self.item_table)
            for idx = idx_s, idx_e do
                local entry = self.item_table[idx]
                if not entry then break end
                entry.idx = idx
                local w = OPDSItem:new{
                    entry = entry, cover_w = cover_w, cover_h = cover_h,
                    item_w = self.item_width, item_h = self.item_height,
                    show_parent = self.show_parent, menu = self,
                }
                table.insert(self.item_group, w)
                table.insert(self.layout, { w })
                if idx < idx_e then
                    table.insert(self.item_group, LineWidget:new{
                        dimen = Geom:new{ w = self.item_width, h = 1 },
                        background = Blitbuffer.COLOR_LIGHT_GRAY,
                    })
                end
            end

            self:updatePageInfo(select_number)
            self:mergeTitleBarIntoLayout()
            UIManager:setDirty(self.show_parent, function()
                local rd = old_dimen and old_dimen:combine(self.dimen) or self.dimen
                return "ui", rd
            end)
            return
        end

        -- Deeper catalog pages: original cover-aware logic below.
        local has_covers = false
        for _, item in ipairs(self.item_table or {}) do
            if item.cover_url then has_covers = true; break end
        end
        if not has_covers then
            return Menu.updateItems(self, select_number, no_recalculate_dimen)
        end
        if self._zen_halt then self._zen_halt(); self._zen_halt = nil end

        -- Mirror library display mode (mosaic grid vs cover list)
        local display_mode
        local ok_bim, BIM = pcall(require, "bookinfomanager")
        if ok_bim then display_mode = BIM:getSetting("filemanager_display_mode") end
        local mosaic_mode = display_mode and display_mode:sub(1, 6) == "mosaic"
        local Screen = require("device").screen
        local portrait_mode = Screen:getWidth() < Screen:getHeight()
        local nb_cols_setting, nb_rows_setting, perpage_setting
        if ok_bim then
            if portrait_mode then
                nb_cols_setting = BIM:getSetting("nb_cols_portrait") or 3
                nb_rows_setting = BIM:getSetting("nb_rows_portrait") or 3
            else
                nb_cols_setting = BIM:getSetting("nb_cols_landscape") or 4
                nb_rows_setting = BIM:getSetting("nb_rows_landscape") or 2
            end
            perpage_setting = BIM:getSetting("files_per_page")
        else
            nb_cols_setting = portrait_mode and 3 or 4
            nb_rows_setting = portrait_mode and 3 or 2
        end
        logger.dbg("OPDS updateItems: display_mode=", display_mode, "mosaic=", mosaic_mode)

        local old_dimen = self.dimen and self.dimen:copy()
        self.layout = {}
        self.item_group:clear()
        self.page_info:resetLayout()
        self.return_button:resetLayout()
        self.content_group:resetLayout()

        local avail_h = self.inner_dimen.h
        if not self.no_title and self.title_bar then
            avail_h = avail_h - self.title_bar:getHeight()
        end
        if self.page_return_arrow and self.page_info_text then
            avail_h = avail_h
                - math.max(self.page_return_arrow:getSize().h,
                           self.page_info_text:getSize().h)
                - Size.padding.button
        end
        local pending_covers = {}

        if mosaic_mode then
            -- Grid: fill avail_h exactly; clamp rows if cell would be too small.
            local num_cols = nb_cols_setting
            local num_rows = nb_rows_setting
            local cell_w   = math.floor(self.inner_dimen.w / num_cols)
            -- Clamp rows so covers aren't too tiny (min cover_h ~40px).
            local min_cell_h = 40 + PAD_V * 2
            local num_rows_max = math.max(1, math.floor(avail_h / min_cell_h))
            if num_rows > num_rows_max then num_rows = num_rows_max end
            -- Fill avail_h exactly so no gap at bottom.
            local cell_h  = math.floor(avail_h / num_rows)
            local cover_h = math.max(1, cell_h - PAD_V * 2)
            local cover_w = math.floor(cover_h * 2 / 3)
            self.item_height = cell_h
            self.perpage     = num_cols * num_rows
            self.page_num    = math.max(1, math.ceil(#self.item_table / self.perpage))
            if self.page > self.page_num then self.page = self.page_num end
            self.item_width  = self.inner_dimen.w
            self.item_dimen  = Geom:new{ x = 0, y = 0, w = cell_w, h = cell_h }
            logger.dbg("OPDS mosaic: cols=", num_cols, "rows=", num_rows,
                "cell=", cell_w, "x", cell_h, "cover=", cover_w, "x", cover_h)

            local idx_s = (self.page - 1) * self.perpage + 1
            local idx_e = math.min(self.page * self.perpage, #self.item_table)
            local idx   = idx_s
            while idx <= idx_e do
                local row_widgets = {}
                local row_group   = HGroup:new{ align = "top" }
                for col = 1, num_cols do
                    local entry = self.item_table[idx]
                    if entry then
                        entry.idx = idx
                        if entry.cover_url then
                            local cached = _cover_cache[entry.cover_url]
                            if cached and cached.bb then entry.cover_bb = cached.bb end
                        end
                        local w = OPDSMosaicItem:new{
                            entry = entry, cover_w = cover_w, cover_h = cover_h,
                            cell_w = cell_w, cell_h = cell_h,
                            show_parent = self.show_parent, menu = self,
                        }
                        table.insert(row_group, w)
                        table.insert(row_widgets, w)
                        local cv = _cover_cache[entry.cover_url]
                        if entry.cover_url and not entry.cover_bb
                                and not (cv and (cv.bb or cv.failed)) then
                            table.insert(pending_covers, {
                                entry = entry, widget = w,
                                cover_w = cover_w, cover_h = cover_h,
                            })
                        end
                    else
                        table.insert(row_group, HSpan:new{ width = cell_w })
                    end
                    idx = idx + 1
                end
                table.insert(self.item_group, row_group)
                table.insert(self.layout, row_widgets)
            end
        else
            -- Single-column list: cover left, title/author/mandatory right.
            local cover_h, list_perpage
            if perpage_setting and perpage_setting > 0 then
                list_perpage = perpage_setting
            else
                -- estimate cover_h first, then derive perpage
                local est_cover_h = math.max(56, math.min(180, math.floor(avail_h / 6) - PAD_V * 2))
                list_perpage = math.max(1, math.floor(avail_h / (est_cover_h + PAD_V * 2)))
            end
            -- derive item_height to fill avail_h exactly (no gap at bottom)
            self.item_height = math.floor(avail_h / list_perpage)
            cover_h = math.max(1, self.item_height - PAD_V * 2)
            local cover_w = math.floor(cover_h * 2 / 3)
            self.perpage     = list_perpage
            self.page_num    = math.max(1, math.ceil(#self.item_table / self.perpage))
            if self.page > self.page_num then self.page = self.page_num end
            self.item_width  = self.inner_dimen.w
            self.item_dimen  = Geom:new{ x = 0, y = 0, w = self.item_width, h = self.item_height }
            logger.dbg("OPDS list: perpage=", self.perpage,
                "cover_w=", cover_w, "cover_h=", cover_h)

            local idx_s = (self.page - 1) * self.perpage + 1
            local idx_e = math.min(self.page * self.perpage, #self.item_table)
            for idx = idx_s, idx_e do
                local entry = self.item_table[idx]
                if not entry then break end
                entry.idx = idx
                if entry.cover_url then
                    local cached = _cover_cache[entry.cover_url]
                    if cached and cached.bb then entry.cover_bb = cached.bb end
                end
                local w = OPDSItem:new{
                    entry = entry, cover_w = cover_w, cover_h = cover_h,
                    item_w = self.item_width, item_h = self.item_height,
                    show_parent = self.show_parent, menu = self,
                }
                table.insert(self.item_group, w)
                table.insert(self.layout, { w })
                if idx < idx_e then
                    table.insert(self.item_group, LineWidget:new{
                        dimen = Geom:new{ w = self.item_width, h = 1 },
                        background = Blitbuffer.COLOR_LIGHT_GRAY,
                    })
                end
                local cv = _cover_cache[entry.cover_url]
                if entry.cover_url and not entry.cover_bb
                        and not (cv and (cv.bb or cv.failed)) then
                    logger.dbg("OPDS list: queuing cover for", entry.title or "?")
                    table.insert(pending_covers, {
                        entry = entry, widget = w,
                        cover_w = cover_w, cover_h = cover_h,
                    })
                end
            end
        end

        self:updatePageInfo(select_number)
        self:mergeTitleBarIntoLayout()
        UIManager:setDirty(self.show_parent, function()
            local rd = old_dimen and old_dimen:combine(self.dimen) or self.dimen
            return "ui", rd
        end)
        if #pending_covers > 0 then
            self._zen_halt = start_cover_queue(pending_covers, {
                username = self.root_catalog_username,
                password = self.root_catalog_password,
            })
        end
    end

    -- Cancel in-flight cover loads when the widget closes.
    local orig_onCloseWidget = Menu.onCloseWidget
    function OPDSBrowser:onCloseWidget()
        if self._zen_halt then self._zen_halt(); self._zen_halt = nil end
        -- Owned by _cover_cache; free them here since image_disposable=false means widgets didn't.
        for _, v in pairs(_cover_cache) do
            if v.bb then v.bb:free() end
        end
        _cover_cache = {}
        orig_onCloseWidget(self)
    end

    -- ── Navigation buttons ───────────────────────────────────────────────────

    local function fix_buttons(browser)
        if browser.title_bar then
            browser.title_bar:setLeftIcon("chevron.left")
        end
        browser.onLeftButtonTap = function()
            if #browser.paths > 0 then
                browser:onReturn()
            elseif browser.close_callback then
                browser.close_callback()
            end
        end
        if browser.title_bar and browser.title_bar.right_button then
            -- Search icon when inside a searchable catalog; hamburger otherwise.
            local in_catalog = #browser.paths > 0
            local has_search = browser.search_url ~= nil
            local right_icon = (in_catalog and has_search) and "appbar.search" or "appbar.menu"
            browser.title_bar:setRightIcon(right_icon)
            browser.title_bar.right_button.callback = function()
                if in_catalog and browser.search_url then
                    browser:searchCatalog(browser.search_url)
                elseif browser.facet_groups then
                    browser:showFacetMenu()
                else
                    browser:showOPDSMenu()
                end
            end
        end
    end

    local orig_init = OPDSBrowser.init
    function OPDSBrowser:init()
        -- Suppress the empty subtitle Menu.init inserts when title_bar_fm_style=true;
        -- it renders as a blank line adding ~20px of dead space below the title.
        -- false is non-nil (so Menu:init skips overriding it) but falsy (so TitleBar skips it).
        self.subtitle = false
        orig_init(self)
        fix_buttons(self)
        -- Auto-navigate to default catalog (skip when returning to root via onReturn).
        if self._zen_default_navigated then return end
        local default_url = G_reader_settings:readSetting("opds_default_url")
        if default_url then
            self._zen_default_navigated = true
            -- Pre-load credentials from the matching server entry.
            for _, entry in ipairs(self.item_table or {}) do
                if entry.url == default_url then
                    self.root_catalog_title    = entry.text
                    self.root_catalog_username = entry.username
                    self.root_catalog_password = entry.password
                    self.root_catalog_raw_names = entry.raw_names
                    self.catalog_title         = entry.text
                    break
                end
            end
            local NetworkMgr = require("ui/network/manager")
            UIManager:nextTick(function()
                NetworkMgr:runWhenConnected(function()
                    self:updateCatalog(default_url)
                end)
            end)
        end
    end

    -- Hide footer return arrow; back nav is via the left title button.
    local orig_updatePageInfo = Menu.updatePageInfo
    function OPDSBrowser:updatePageInfo(select_number)
        orig_updatePageInfo(self, select_number)
        if self.page_return_arrow then self.page_return_arrow:hide() end
    end

    -- Tag book items with cover_url for async cover loading.
    local orig_genItemTableFromCatalog = OPDSBrowser.genItemTableFromCatalog
    function OPDSBrowser:genItemTableFromCatalog(catalog, item_url)
        local item_table = orig_genItemTableFromCatalog(self, catalog, item_url)
        local with_cover = 0
        for _, item in ipairs(item_table) do
            if item.acquisitions and #item.acquisitions > 0 then
                local thumb = item.thumbnail or item.image
                if thumb then
                    item.cover_url = thumb
                    with_cover = with_cover + 1
                    logger.dbg("OPDS cover_url set:", item.title or "?", "->", thumb)
                end
            end
        end
        logger.dbg("OPDS genItemTableFromCatalog: total=", #item_table, "with_cover=", with_cover)
        return item_table
    end

    -- Re-apply buttons after stock updateCatalog resets them.
    local orig_updateCatalog = OPDSBrowser.updateCatalog
    function OPDSBrowser:updateCatalog(item_url, paths_updated)
        orig_updateCatalog(self, item_url, paths_updated)
        fix_buttons(self)
    end

    -- Override menu dialogs to anchor to the right button (hamburger icon is on the right).
    -- Stock KOReader anchors both to left_button; we replicate the logic with right_button.
    function OPDSBrowser:showOPDSMenu()
        local ButtonDialog = require("ui/widget/buttondialog")
        local NetworkMgr   = require("ui/network/manager")
        local _            = require("gettext")
        local dialog
        dialog = ButtonDialog:new{
            buttons = {
                {{ text = _("Add catalog"), align = "left",
                    callback = function()
                        UIManager:close(dialog); self:addEditCatalog()
                    end }},
                {},
                {{ text = _("Sync all catalogs"), align = "left",
                    callback = function()
                        UIManager:close(dialog)
                        NetworkMgr:runWhenConnected(function()
                            self.sync_force = false; self:checkSyncDownload()
                        end)
                    end }},
                {{ text = _("Force sync all catalogs"), align = "left",
                    callback = function()
                        UIManager:close(dialog)
                        NetworkMgr:runWhenConnected(function()
                            self.sync_force = true; self:checkSyncDownload()
                        end)
                    end }},
                {{ text = _("Set max number of files to sync"), align = "left",
                    callback = function() self:setMaxSyncDownload() end }},
                {{ text = _("Set sync folder"), align = "left",
                    callback = function() self:setSyncDir() end }},
                {{ text = _("Set file types to sync"), align = "left",
                    callback = function() self:setSyncFiletypes() end }},
            },
            shrink_unneeded_width = true,
            anchor = function()
                return self.title_bar.right_button.image.dimen
            end,
        }
        UIManager:show(dialog)
    end

    function OPDSBrowser:showFacetMenu()
        local ButtonDialog = require("ui/widget/buttondialog")
        local ffiUtil      = require("ffi/util")
        local url_mod      = require("socket.url")
        local _            = require("gettext")
        local T            = ffiUtil.template
        local buttons      = {}
        local dialog
        local catalog_url  = self.paths[#self.paths].url

        table.insert(buttons, {{
            text = "\u{f067} " .. _("Add catalog"), align = "left",
            callback = function()
                UIManager:close(dialog); self:addSubCatalog(catalog_url)
            end,
        }})
        table.insert(buttons, {})

        if self.search_url then
            table.insert(buttons, {{
                text = "\u{f002} " .. _("Search"), align = "left",
                callback = function()
                    UIManager:close(dialog); self:searchCatalog(self.search_url)
                end,
            }})
            table.insert(buttons, {})
        end

        if self.facet_groups then
            for group_name, facets in ffiUtil.orderedPairs(self.facet_groups) do
                table.insert(buttons, {
                    { text = "\u{f0b0} " .. group_name, enabled = false, align = "left" }
                })
                for __, link in ipairs(facets) do
                    local facet_text = link.title
                    if link["thr:count"] then
                        facet_text = T(_("%1 (%2)"), facet_text, link["thr:count"])
                    end
                    if link["opds:activeFacet"] == "true" then
                        facet_text = "\u{2713} " .. facet_text
                    end
                    table.insert(buttons, {{
                        text = facet_text, align = "left",
                        callback = function()
                            UIManager:close(dialog)
                            self:updateCatalog(url_mod.absolute(catalog_url, link.href))
                        end,
                    }})
                end
                table.insert(buttons, {})
            end
        end

        dialog = ButtonDialog:new{
            buttons = buttons,
            shrink_unneeded_width = true,
            anchor = function()
                return self.title_bar.right_button.image.dimen
            end,
        }
        UIManager:show(dialog)
    end

    -- Hold on a root-list catalog entry: vertical single-column menu.
    function OPDSBrowser:onMenuHold(item)
        if #self.paths > 0 or item.idx == 1 then return true end
        local ButtonDialog   = require("ui/widget/buttondialog")
        local ConfirmBox     = require("ui/widget/confirmbox")
        local LeftContainer  = require("ui/widget/container/leftcontainer")
        local NetworkMgr     = require("ui/network/manager")
        local _              = require("gettext")
        local default_url    = G_reader_settings:readSetting("opds_default_url")
        local is_default     = default_url == item.url

        -- Build the same cover+title header as showDownloads.
        local border      = Size.border.thin or 1
        local gap         = Screen:scaleBySize(8)
        local dlg_w       = math.floor(math.min(Screen:getWidth(), Screen:getHeight()) * 0.9)
        local avail_w     = dlg_w - 2 * (Size.border.window + Size.padding.button)
                                  - 2 * (Size.padding.default + Size.margin.default)
        local cover_h     = Screen:scaleBySize(120)
        local cover_w     = math.floor(cover_h * 2 / 3)
        local text_w      = math.max(avail_w - cover_w - 2 * border - gap, Screen:scaleBySize(60))
        local framed_h    = cover_h
        local CoverPlaceholder = InputContainer:extend{}
        function CoverPlaceholder:init()
            self.dimen = Geom:new{ w = cover_w, h = cover_h }
            self[1] = FrameContainer:new{
                bordersize = 0, padding = 0,
                LineWidget:new{
                    dimen = Geom:new{ w = cover_w, h = cover_h },
                    background = Blitbuffer.COLOR_LIGHT_GRAY,
                },
            }
        end
        function CoverPlaceholder:paintTo(bb, x, y)
            InputContainer.paintTo(self, bb, x, y)
            if not rounded_corners_enabled() then return end
            paintCornerMasks(bb, x, y, cover_w, cover_h, _corner_radius)
            paintCornerBorderArcs(bb, x, y, cover_w, cover_h, _corner_radius, Blitbuffer.COLOR_BLACK)
        end
        local framed_cover = CoverPlaceholder:new{}
        local vstack = VGroup:new{ align = "left" }
        table.insert(vstack, TextWidget:new{
            text = item.text or "", face = Font:getFace("cfont", 20),
            bold = true, max_width = text_w,
        })
        if item.mandatory and tostring(item.mandatory) ~= "" then
            table.insert(vstack, VSpan:new{ width = Screen:scaleBySize(3) })
            table.insert(vstack, TextWidget:new{
                text = tostring(item.mandatory), face = Font:getFace("cfont", 14),
                fgcolor = Blitbuffer.COLOR_DARK_GRAY, max_width = text_w,
            })
        end
        local header = LeftContainer:new{
            dimen = Geom:new{ w = avail_w, h = framed_h },
            HGroup:new{
                align = "center",
                framed_cover,
                HSpan:new{ width = gap },
                vstack,
            },
        }

        local dialog
        dialog = ButtonDialog:new{
            _added_widgets = { header },
            buttons = {
                {{ text = "\u{F04E6}  " .. _("Sync"), align = "left",
                    callback = function()
                        UIManager:close(dialog)
                        NetworkMgr:runWhenConnected(function()
                            self.sync_force = false
                            self:checkSyncDownload(item.idx)
                        end)
                    end }},
                {{ text = "\u{F04E6}  " .. _("Force sync"), align = "left",
                    callback = function()
                        UIManager:close(dialog)
                        NetworkMgr:runWhenConnected(function()
                            self.sync_force = true
                            self:checkSyncDownload(item.idx)
                        end)
                    end }},
                {},
                {{ text = is_default
                            and ("\u{F04D2}  " .. _("Remove default"))
                            or  ("\u{F04CE}  " .. _("Set as default")),
                    align = "left",
                    callback = function()
                        UIManager:close(dialog)
                        if is_default then
                            G_reader_settings:delSetting("opds_default_url")
                        else
                            G_reader_settings:saveSetting("opds_default_url", item.url)
                        end
                    end }},
                {},
                {{ text = "\u{F090C}  " .. _("Edit"), align = "left",
                    callback = function()
                        UIManager:close(dialog)
                        self:addEditCatalog(item)
                    end }},
                {},
                {{ text = "\u{F0156}  " .. _("Delete"), align = "left",
                    callback = function()
                        UIManager:show(ConfirmBox:new{
                            text     = _("Delete OPDS catalog?"),
                            ok_text  = _("Delete"),
                            ok_callback = function()
                                UIManager:close(dialog)
                                self:deleteCatalog(item)
                            end,
                        })
                    end }},
            },
        }
        UIManager:show(dialog)
        return true
    end

    -- Custom search dialog matching library search.lua style.
    local orig_searchCatalog = OPDSBrowser.searchCatalog
    function OPDSBrowser:searchCatalog(item_url)
        local InputDialog  = require("ui/widget/inputdialog")
        local util         = require("util")
        local _            = require("gettext")
        local catalog_name = self.catalog_title or self.root_catalog_title or ""
        local browser      = self
        local dialog
        local function _doSearch()
            local search_str = util.urlEncode(dialog:getInputText())
            if search_str == "" then return end
            UIManager:close(dialog)
            browser.catalog_title = _("Search results")
            local search_url = item_url:gsub("%%s", function() return search_str end)
            browser:updateCatalog(search_url)
        end
        local orig_onTap = InputDialog.onTap
        dialog = InputDialog:new{
            title                       = _("Search") .. (catalog_name ~= "" and " " .. catalog_name or ""),
            title_bar_left_icon         = "close",
            title_bar_left_icon_tap_callback = function() UIManager:close(dialog) end,
            input_hint                  = _("Alexandre Dumas"),
            buttons = {{
                {
                    text             = "\u{F002} " .. _("Search"),
                    is_enter_default = true,
                    callback         = _doSearch,
                },
            }},
        }
        -- Close keyboard + dialog on outside tap (mirrors library search).
        function dialog:onTap(arg, ges)
            if self.deny_keyboard_hiding then return end
            if self:isKeyboardVisible() then
                local kb = self._input_widget and self._input_widget.keyboard
                if kb and kb.dimen and ges.pos:notIntersectWith(kb.dimen)
                        and ges.pos:notIntersectWith(self.dialog_frame.dimen) then
                    self:onCloseKeyboard()
                    UIManager:close(self)
                    return true
                end
                return orig_onTap(self, arg, ges)
            else
                if ges.pos:notIntersectWith(self.dialog_frame.dimen) then
                    UIManager:close(self)
                    return true
                end
            end
        end
        UIManager:show(dialog)
        dialog:onShowKeyboard()
    end

    function OPDSBrowser:getCurrentDownloadDir()
        if self.sync then return self.settings.sync_dir end
        return G_reader_settings:readSetting("download_dir")
            or G_reader_settings:readSetting("lastdir")
            or require("device").home_dir
            or "/"
    end

    -- Left-aligned context-style download dialog with cover/title/author header.
    function OPDSBrowser:showDownloads(item)
        local acquisitions = item.acquisitions
        local filename     = self:getFileName(item)

        local ButtonDialog   = require("ui/widget/buttondialog")
        local ConfirmBox     = require("ui/widget/confirmbox")
        local Font           = require("ui/font")
        local FrameContainer = require("ui/widget/container/framecontainer")
        local Geom           = require("ui/geometry")
        local HGroup         = require("ui/widget/horizontalgroup")
        local HSpan          = require("ui/widget/horizontalspan")
        local ImageWidget    = require("ui/widget/imagewidget")
        local LeftContainer  = require("ui/widget/container/leftcontainer")
        local LineWidget     = require("ui/widget/linewidget")
        local Notification   = require("ui/widget/notification")
        local OPDSPSE        = require("opdspse")
        local Screen         = require("device").screen
        local TextViewer     = require("ui/widget/textviewer")
        local TextWidget     = require("ui/widget/textwidget")
        local VGroup         = require("ui/widget/verticalgroup")
        local VSpan          = require("ui/widget/verticalspan")
        local url_mod        = require("socket.url")
        local util           = require("util")
        local _              = require("gettext")

        local current_dir = self:getCurrentDownloadDir()

        -- Header geometry: exact inner-content width formula matching context_menu.lua.
        local border  = Size.border.thin or 1
        local gap     = Screen:scaleBySize(8)
        local dlg_w   = math.floor(math.min(Screen:getWidth(), Screen:getHeight()) * 0.9)
        local avail_w = dlg_w - 2 * (Size.border.window + Size.padding.button)
                               - 2 * (Size.padding.default + Size.margin.default)
        local cover_h        = Screen:scaleBySize(120)
        local cover_w        = math.floor(cover_h * 2 / 3)
        local framed_cover_w = cover_w + 2 * border
        local text_w         = math.max(avail_w - framed_cover_w - gap, Screen:scaleBySize(60))
        local framed_h       = cover_h + 2 * border

        local cover_inner
        if item.cover_bb then
            cover_inner = ImageWidget:new{
                image = item.cover_bb, width = cover_w, height = cover_h,
                image_disposable = false,
            }
        else
            cover_inner = LineWidget:new{
                dimen = Geom:new{ w = cover_w, h = cover_h },
                background = Blitbuffer.COLOR_LIGHT_GRAY,
            }
        end
        local framed_cover = FrameContainer:new{
            bordersize = border, padding = 0,
            cover_inner,
        }

        -- Text stack: sizes/spacing match context_menu.lua (cfont 20/17/14).
        local vstack = VGroup:new{ align = "left" }
        table.insert(vstack, TextWidget:new{
            text = item.title or item.text or "", face = Font:getFace("cfont", 20),
            bold = true, max_width = text_w,
        })
        local author = item.author
        if type(author) == "table" then
            author = (author.name or (author[1] and author[1].name)) or nil
        end
        if author and author ~= "" then
            table.insert(vstack, VSpan:new{ width = Screen:scaleBySize(2) })
            table.insert(vstack, TextWidget:new{
                text = author, face = Font:getFace("cfont", 17),
                max_width = text_w,
            })
        end
        local mandatory = item.mandatory and tostring(item.mandatory) or nil
        if mandatory and mandatory ~= "" then
            table.insert(vstack, VSpan:new{ width = Screen:scaleBySize(3) })
            table.insert(vstack, TextWidget:new{
                text = mandatory, face = Font:getFace("cfont", 14),
                fgcolor = Blitbuffer.COLOR_DARK_GRAY, max_width = text_w,
            })
        end

        local header = LeftContainer:new{
            dimen = Geom:new{ w = avail_w, h = framed_h },
            HGroup:new{
                align = "center",
                framed_cover,
                HSpan:new{ width = gap },
                vstack,
            },
        }

        local buttons = {}

        -- Custom post-download dialog: title + Read Now / Done.
        local _item_title = item.title or item.text or ""
        local _browser = self
        local function zen_download_cb(file)
            local dlg = ConfirmBox:new{
                icon         = "notice-info",
                text         = _("Downloaded") .. "\n" .. _item_title,
                -- cancel = Read now (left), ok = Done (right)
                cancel_text  = "\u{F0B63}  " .. _("Read now"),
                cancel_callback = function()
                    local mgr = _browser._manager
                    if mgr then mgr.last_downloaded_file = nil end
                    _browser.close_callback()
                    local ui = mgr and mgr.ui
                    if ui then
                        if ui.document then
                            ui:switchDocument(file)
                        else
                            ui:openFile(file)
                        end
                    end
                end,
                ok_text      = "\u{F012C}  " .. _("Done"),
                ok_callback  = function() end,
                dismissable  = false,
            }
            UIManager:nextTick(function() UIManager:show(dlg) end)
        end

        -- Description first (when available), matching context_menu.lua order.
        if type(item.content) == "string" then
            local content_ref = item.content
            local title_ref   = item.title or item.text
            table.insert(buttons, {{ text = "\u{F02FD}  " .. _("Description"), align = "left", bold = true,
                callback = function()
                    UIManager:show(TextViewer:new{
                        title = title_ref, title_multilines = true,
                        text  = util.htmlToPlainTextIfHtml(content_ref),
                        text_type = "book_info",
                    })
                end,
            }})
        end

        for _i, acq in ipairs(acquisitions) do
            if acq.count then
                local a = acq
                table.insert(buttons, {{ text = "\u{F01B}  " .. _("Page stream"), align = "left", bold = true,
                    callback = function()
                        UIManager:close(self.download_dialog)
                        OPDSPSE:streamPages(a.href, a.count, false,
                            self.root_catalog_username, self.root_catalog_password)
                    end,
                }})
                table.insert(buttons, {{ text = _("Stream from page") .. "  \u{23E9}", align = "left", bold = true,
                    callback = function()
                        UIManager:close(self.download_dialog)
                        OPDSPSE:streamPages(a.href, a.count, true,
                            self.root_catalog_username, self.root_catalog_password)
                    end,
                }})
                if acq.last_read then
                    table.insert(buttons, {{ text = "\u{25B6}  " .. _("Resume from page") .. " " .. acq.last_read, align = "left", bold = true,
                        callback = function()
                            UIManager:close(self.download_dialog)
                            OPDSPSE:streamPages(a.href, a.count, false,
                                self.root_catalog_username, self.root_catalog_password, a.last_read)
                        end,
                    }})
                end
            elseif acq.type ~= "borrow" then
                local filetype = OPDSBrowser.getFiletype(acq)
                if filetype then
                    local a  = acq
                    local fn = filename
                    table.insert(buttons, {{ text = "\u{F01DA}  " .. _( "Download") .. " " .. url_mod.unescape(a.title or string.upper(filetype)), align = "left", bold = true,
                        callback = function()
                            UIManager:close(self.download_dialog)
                            local p = self:getLocalDownloadPath(fn, filetype, a.href)
                            self:checkDownloadFile(p, a.href,
                                self.root_catalog_username, self.root_catalog_password,
                                zen_download_cb)
                        end,
                        hold_callback = function()
                            UIManager:close(self.download_dialog)
                            local p = self:getLocalDownloadPath(fn, filetype, a.href)
                            table.insert(self.downloads, {
                                file     = p, url = a.href,
                                info     = type(item.content) == "string"
                                           and util.htmlToPlainTextIfHtml(item.content) or "",
                                catalog  = self.root_catalog_title,
                                username = self.root_catalog_username,
                                password = self.root_catalog_password,
                            })
                            self._manager.updated = true
                            Notification:notify(_("Book added to download list"),
                                Notification.SOURCE_OTHER)
                        end,
                    }})
                end
            end
        end

        local item_ref = item
        table.insert(buttons, {{ text = "\u{F07C}  " .. _("Change folder"), align = "left", bold = true,
            callback = function()
                UIManager:close(self.download_dialog)
                require("ui/downloadmgr"):new{
                    onConfirm = function(path)
                        G_reader_settings:saveSetting("download_dir", path)
                        self:showDownloads(item_ref)
                    end,
                }:chooseDir(current_dir)
            end,
        }})

        self.download_dialog = ButtonDialog:new{
            _added_widgets = { header },
            buttons        = buttons,
        }
        UIManager:show(self.download_dialog)
    end
end

return apply_opds
