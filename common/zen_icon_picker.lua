-- common/zen_icon_picker.lua
-- Horizontally-paginating icon grid picker dialog.
-- Swipe west/east to change pages; pill bar mirrors zen_scroll_bar style.
--
-- Usage:
--   local showIconPickerDialog = require("common/zen_icon_picker")
--   showIconPickerDialog(icons_list, current_icon, function(name) ... end)
--   Each item in icons_list is {name=string, file=string_or_nil}.
--   file=nil means render via KOReader icon name; otherwise use the absolute path.

local function showIconPickerDialog(icons_list, current_icon, on_select)
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
    local VS         = require("ui/widget/verticalspan")
    local IW         = require("ui/widget/iconwidget")
    local TW         = require("ui/widget/textwidget")
    local pager      = require("common/zen_pager")

    local sw, sh   = Screen:getWidth(), Screen:getHeight()
    local icon_sz  = Screen:scaleBySize(48)
    local label_h  = Screen:scaleBySize(18)
    local cell_pad = Screen:scaleBySize(6)
    local pad      = Size.padding.default
    local brd      = Size.border.window
    local span     = Size.span.vertical_default

    -- Always reserve the tallest bar style height so the frame never resizes on style changes.
    local bar_area_h = pager.PN_FOOTER_H

    -- Close button.
    local close_sz  = Screen:scaleBySize(24)
    local close_gap = Screen:scaleBySize(6)
    local close_iw  = IW:new{ icon = "close", width = close_sz, height = close_sz }

    -- frame_w is the outer frame width (border included).
    -- content_w is the actual drawable area inside (after border + padding).
    -- All cell/bar sizing uses content_w to prevent overflow.
    local frame_w   = math.floor(sw * 0.90)
    local content_w = frame_w - 2*pad - 2*brd
    local cols      = math.max(3, math.floor(content_w / Screen:scaleBySize(96)))
    local cell_w    = math.floor(content_w / cols)
    local cell_h    = icon_sz + label_h + cell_pad * 2

    -- Title: close icon on the left, label to its right.
    local title_text_w = content_w - close_sz - close_gap
    local title_tw = TW:new{
        text  = _("Select icon"),
        face  = Font:getFace("smallinfofont"),
        width = title_text_w,
    }
    local title_text_h = title_tw:getSize().h
    local title_h      = math.max(close_sz, title_text_h)

    -- Fit as many rows as possible within the available vertical space.
    local overhead      = 2*pad + 2*brd + title_h + span + span + bar_area_h
    local max_grid_h    = math.max(cell_h, sh - overhead - Screen:scaleBySize(40))
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
                            face      = Font:getFace("xx_smallinfofont"),
                            max_width = cell_w - cell_pad * 2,
                        },
                    },
                },
            })
        end
        page_vgs[p] = pv
    end

    -- Frame geometry: frame_w already set; derive height and positions.
    local frame_h = 2*pad + 2*brd + title_h + span + grid_h + span + bar_area_h
    local frame_x = math.floor((sw - frame_w) / 2)
    local frame_y = math.floor((sh - frame_h) / 2)
    if frame_y < 0 then frame_y = 0 end

    local content_x = frame_x + brd + pad
    local content_y = frame_y + brd + pad
    local grid_x    = content_x
    local grid_y    = content_y + title_h + span
    local bar_y     = grid_y + grid_h + span

    -- Frame widget: renders border + background only.
    -- All inner content (title, close icon, grid, bar) is overprinted in paintTo.
    local inner_frame = FC:new{
        width      = frame_w,
        height     = frame_h,
        background = Blitbuffer.COLOR_WHITE,
        bordersize = brd,
        padding    = pad,
        VS:new{ height = 0 },
    }

    local function paintBar(bb)
        pager.paint(bb, content_x, bar_y, content_w, bar_area_h, cur_page, total_pages)
    end

    -- forward ref so gesture handlers can close the dialog before it's assigned.
    local dialog

    local function goToPage(p)
        if p < 1 or p > total_pages then return end
        cur_page = p
        UIManager:setDirty(dialog, function() return "ui", dialog.dimen end)
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
                    local fd = inner_frame.dimen
                    if not fd or not ges.pos:intersectWith(fd) then
                        UIManager:close(dialog)
                        return true
                    end
                    local gx, gy = ges.pos.x, ges.pos.y
                    -- Close button (top-left of content area).
                    if gx >= content_x and gx < content_x + close_sz
                       and gy >= content_y and gy < content_y + title_h then
                        UIManager:close(dialog)
                        return true
                    end
                    -- Page-number chevron taps.
                    if gy >= bar_y and gy < bar_y + bar_area_h and pager.getStyle() == "page_number" then
                        if gx < content_x + pager.CHEV_W then
                            goToPage(cur_page - 1)
                        elseif gx > content_x + content_w - pager.CHEV_W then
                            goToPage(cur_page + 1)
                        end
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
                            UIManager:close(dialog)
                            on_select(icons_list[idx].name)
                        end
                    end
                    return true
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
                        UIManager:close(dialog)
                    end
                    return true
                end,
            },
        })
    end

    function PickerDlg:paintTo(bb, x, y)
        self.dimen.x = x
        self.dimen.y = y
        -- Ensure inner_frame.dimen has correct size for tap intersection checks.
        inner_frame.dimen = Geom:new{ x = frame_x, y = frame_y, w = frame_w, h = frame_h }
        inner_frame:paintTo(bb, frame_x, frame_y)
        -- Close icon (vertically centred in title row).
        close_iw:paintTo(bb, content_x, content_y + math.floor((title_h - close_sz) / 2))
        -- Title text (offset right of close icon, vertically centred).
        title_tw:paintTo(bb, content_x + close_sz + close_gap,
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
