-- common/zen_icon_picker.lua
-- Full-screen horizontally-paginating icon grid picker.
-- Swipe west/east to change pages; footer mirrors the shared pages scrollbar.
--
-- Usage:
--   local showIconPickerDialog = require("common/ui/zen_icon_picker")
--   showIconPickerDialog(icons_list, current_icon, function(name) ... end)
--   Each item in icons_list is {name=string, file=string_or_nil}.
--   file=nil means render via KOReader icon name; otherwise use the absolute path.

local function showIconPickerDialog(icons_list, current_icon, on_select)
    local function displayName(item)
        return (item.name:gsub("^quick_", ""):gsub("^tab_", ""):gsub("^lookup_", ""))
    end
    table.sort(icons_list, function(a, b)
        return displayName(a):lower() < displayName(b):lower()
    end)

    local _          = require("gettext")
    local Screen     = require("device").screen
    local Geom       = require("ui/geometry")
    local Blitbuffer = require("ffi/blitbuffer")
    local Font       = require("ui/font")
    local Size       = require("ui/size")
    local UIManager  = require("ui/uimanager")
    local IC         = require("ui/widget/container/inputcontainer")
    local CC         = require("ui/widget/container/centercontainer")
    local FC         = require("ui/widget/container/framecontainer")
    local VG         = require("ui/widget/verticalgroup")
    local HG         = require("ui/widget/horizontalgroup")
    local IW         = require("ui/widget/iconwidget")
    local TW         = require("ui/widget/textwidget")
    local pager      = require("common/ui/zen_pager")

    local sw, sh   = Screen:getWidth(), Screen:getHeight()
    local icon_sz  = Screen:scaleBySize(42)
    local label_size = math.max(Screen:scaleBySize(8),
        (Font.sizemap and Font.sizemap["xx_smallinfofont"] or Screen:scaleBySize(18))
        - Screen:scaleBySize(2))
    local label_face = Font:getFace("smallinfofont", label_size)
    local label_probe = TW:new{ text = "Wg", face = label_face, padding = 0 }
    local label_h  = label_probe:getSize().h
    label_probe:free()
    local cell_pad = Screen:scaleBySize(4)
    local max_cell_brd = Screen:scaleBySize(2)
    local pad      = Size.padding.default
    local span     = Size.span.vertical_default

    -- Always reserve the tallest bar style height so the layout never resizes on style changes.
    local bar_area_h = pager.PN_FOOTER_H

    -- Back button.
    local back_sz  = Screen:scaleBySize(24)
    local back_gap = Screen:scaleBySize(6)
    local back_iw  = IW:new{ icon = "chevron.left", width = back_sz, height = back_sz }

    local content_w = sw - 2 * pad
    local cols      = math.max(4, math.floor(content_w / Screen:scaleBySize(78)))
    local cell_w    = math.floor(content_w / cols)
    local cell_h    = icon_sz + label_h + cell_pad * 2 + max_cell_brd * 2
    local label_max_w = cell_w - cell_pad * 2 - max_cell_brd * 2

    -- Title: back icon on the left, label to its right.
    local title_text_w = content_w - back_sz - back_gap
    local title_tw = TW:new{
        text  = _("Select icon"),
        face  = Font:getFace("smallinfofont"),
        bold  = true,
        width = title_text_w,
    }
    local title_text_h = title_tw:getSize().h
    local title_h      = math.max(back_sz, title_text_h)

    -- Fit as many rows as possible within the available vertical space.
    local overhead      = 2 * pad + title_h + span + span + bar_area_h
    local max_grid_h    = math.max(cell_h, sh - overhead)
    local rows_per_page = math.max(1, math.floor(max_grid_h / cell_h))
    local grid_h        = rows_per_page * cell_h
    local per_page      = cols * rows_per_page
    local total_pages   = math.max(1, math.ceil(math.max(#icons_list, 1) / per_page))

    local cur_page = 1

    -- Pre-build one VG per page (painted directly; no ScrollableContainer needed).
    local page_vgs = {}
    for p = 1, total_pages do
        local pv      = VG:new{ align = "left" }
        local start_i = (p - 1) * per_page + 1
        local row_g
        for offset = 0, per_page - 1 do
            local i = start_i + offset
            if i > #icons_list then break end
            if offset % cols == 0 then
                row_g = HG:new{ align = "top" }
                table.insert(pv, row_g)
            end
            local item      = icons_list[i]
            local name      = item.name
            local is_sel    = (current_icon == name)
            local short     = name:gsub("^quick_", ""):gsub("^tab_", ""):gsub("^lookup_", "")
            -- bordersize is added on top of content by FC.getSize(), so subtract it
            -- from the CC inner dimen so each FC reports exactly cell_w to HG.
            local cell_brd = is_sel and Screen:scaleBySize(2) or Screen:scaleBySize(1)
            table.insert(row_g, FC:new{
                width      = cell_w,
                height     = cell_h,
                bordersize = cell_brd,
                color      = is_sel and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_LIGHT_GRAY,
                background = is_sel and Blitbuffer.COLOR_LIGHT_GRAY or Blitbuffer.COLOR_WHITE,
                padding    = cell_pad,
                CC:new{
                    dimen = Geom:new{ w = cell_w - cell_pad*2 - 2*cell_brd, h = cell_h - cell_pad*2 - 2*cell_brd },
                    VG:new{
                        align = "center",
                        IW:new{ file = item.file or nil, icon = item.file and nil or name, width = icon_sz, height = icon_sz, alpha = true },
                        TW:new{
                            text      = short,
                            face      = label_face,
                            max_width = label_max_w,
                            padding   = 0,
                        },
                    },
                },
            })
        end
        page_vgs[p] = pv
    end

    local content_x = pad
    local content_y = pad
    local grid_x    = content_x
    local grid_y    = content_y + title_h + span
    local bar_y     = grid_y + grid_h + span

    local function paintBar(bb)
        pager.paint(bb, content_x, bar_y, content_w, bar_area_h, cur_page, total_pages, "page_number")
    end

    -- forward ref so gesture handlers can close the dialog before it's assigned.
    local dialog
    local closed = false

    local function closeDialog()
        if closed then return end
        closed = true
        UIManager:close(dialog, "ui")
        UIManager:forceRePaint()
    end

    local function goToPage(p)
        if p < 1 or p > total_pages then return end
        cur_page = p
        UIManager:setDirty(dialog, function() return "ui", dialog.dimen end)
    end

    local function canUsePageNumber()
        return total_pages > 1
    end

    local function inPageNumberBar(gx, gy)
        return canUsePageNumber()
            and gy >= bar_y and gy < bar_y + bar_area_h
            and gx >= content_x and gx < content_x + content_w
    end

    local function pageNumberZone(gx)
        if gx < content_x + pager.CHEV_W then return "left" end
        if gx >= content_x + content_w - pager.CHEV_W then return "right" end
        return "center"
    end

    local function handlePageNumberTap(gx, gy)
        if not inPageNumberBar(gx, gy) then return false end
        local zone = pageNumberZone(gx)
        if zone == "left" then
            goToPage(cur_page > 1 and cur_page - 1 or total_pages)
        elseif zone == "right" then
            goToPage(cur_page < total_pages and cur_page + 1 or 1)
        end
        return true
    end

    local function handlePageNumberHold(gx, gy)
        if not inPageNumberBar(gx, gy) then return false end
        local zone = pageNumberZone(gx)
        if zone == "left" then
            local skip = pager.getHoldSkip()
            goToPage(skip == "ends" and 1 or math.max(1, cur_page - (tonumber(skip) or 10)))
            return true
        elseif zone == "right" then
            local skip = pager.getHoldSkip()
            goToPage(skip == "ends" and total_pages or math.min(total_pages, cur_page + (tonumber(skip) or 10)))
            return true
        end
        return true
    end

    local PickerDlg = IC:extend{}

    function PickerDlg:init()
        self:_init()
        self.dimen = Geom:new{ x = 0, y = 0, w = sw, h = sh }
        self:registerTouchZones({
            {
                id          = "picker_tap",
                ges         = "tap",
                screen_zone = { ratio_x = 0, ratio_y = 0, ratio_w = 1, ratio_h = 1 },
                handler     = function(ges)
                    local gx, gy = ges.pos.x, ges.pos.y
                    if gx >= content_x and gx < content_x + back_sz
                       and gy >= content_y and gy < content_y + title_h then
                        closeDialog()
                        return true
                    end
                    if handlePageNumberTap(gx, gy) then
                        return true
                    end
                    -- Grid cells.
                    local grid_geom = Geom:new{
                        x = grid_x, y = grid_y,
                        w = cols * cell_w, h = rows_per_page * cell_h,
                    }
                    if ges.pos:intersectWith(grid_geom) then
                        local col_i = math.floor((gx - grid_x) / cell_w)
                        local row_i = math.floor((gy - grid_y) / cell_h)
                        local idx   = (cur_page - 1) * per_page + row_i * cols + col_i + 1
                        if idx >= 1 and idx <= #icons_list then
                            local selected_name = icons_list[idx].name
                            closeDialog()
                            UIManager:nextTick(function()
                                local ok_select, err = xpcall(function()
                                    on_select(selected_name)
                                end, debug.traceback)
                                if not ok_select then
                                    require("common/zen_logger").new("zen_icon_picker").warn("Selection failed:", err)
                                end
                            end)
                        end
                    end
                    return true
                end,
            },
            {
                id          = "picker_page_number_hold",
                ges         = "hold",
                screen_zone = { ratio_x = 0, ratio_y = 0, ratio_w = 1, ratio_h = 1 },
                handler     = function(ges)
                    if handlePageNumberHold(ges.pos.x, ges.pos.y) then
                        return true
                    end
                    return false
                end,
            },
            {
                id          = "picker_swipe",
                ges         = "swipe",
                screen_zone = { ratio_x = 0, ratio_y = 0, ratio_w = 1, ratio_h = 1 },
                handler     = function(ges)
                    local dir = ges.direction
                    if dir == "west" then
                        goToPage(cur_page + 1)
                    elseif dir == "east" then
                        goToPage(cur_page - 1)
                    else
                        closeDialog()
                    end
                    return true
                end,
            },
        })
    end

    function PickerDlg:paintTo(bb, x, y)
        self.dimen.x = x
        self.dimen.y = y
        bb:paintRect(0, 0, sw, sh, Blitbuffer.COLOR_WHITE)
        back_iw:paintTo(bb, content_x, content_y + math.floor((title_h - back_sz) / 2))
        -- Title text (offset right of back icon, vertically centred).
        title_tw:paintTo(bb, content_x + back_sz + back_gap,
                         content_y + math.floor((title_h - title_text_h) / 2))
        -- Current page grid.
        page_vgs[cur_page]:paintTo(bb, grid_x, grid_y)
        -- Page indicator bar.
        paintBar(bb)
    end

    dialog = PickerDlg:new{}
    UIManager:show(dialog, "full")
end

return showIconPickerDialog
