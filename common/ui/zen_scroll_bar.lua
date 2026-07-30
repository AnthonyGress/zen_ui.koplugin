local function apply_zen_scroll_bar()
    -- Replaces the pagination footer with a pill-bar, dot-style, or page-number
    -- scroll indicator. Style is read live from config; no restart needed to toggle.
    local _       = require("gettext")
    local Blitbuffer = require("ffi/blitbuffer")
    local Device  = require("device")
    local Geom    = require("ui/geometry")
    local Menu    = require("ui/widget/menu")
    local Screen  = Device.screen
    local Size    = require("ui/size")
    local UIManager = require("ui/uimanager")
    local pager   = require("common/ui/zen_pager")
    pager.setPlugin(rawget(_G, "__ZEN_UI_PLUGIN"))
    local target_menus = {
        filemanager = true,
        history = true,
        collections = true,
        filesearcher = true,
        zen_settings = true,
    }

    local function getRakuyomi()
        return rawget(_G, "__ZEN_UI_RAKUYOMI") or {}
    end

    local orig_menu_init = Menu.init

    function Menu:init()
        orig_menu_init(self)

        -- Check if this is a target menu:
        -- 1. Named menus (filemanager, history, collections, search results)
        -- 2. File browser style menus (covers_fullscreen + is_borderless + title_bar_fm_style)
        -- 3. Bookmarks menu (is_borderless + title_bar_fm_style + title_bar_left_icon == "appbar.menu")
        local is_bookmarks_menu = self.is_borderless
            and self.title_bar_fm_style
            and self.title_bar_left_icon == "appbar.menu"
        local Rakuyomi = getRakuyomi()
        local is_rakuyomi = type(Rakuyomi.isScrollBarMenu) == "function"
            and Rakuyomi.isScrollBarMenu(self)

        if not target_menus[self.name]
           and not is_rakuyomi
           and not (self.covers_fullscreen and self.is_borderless and self.title_bar_fm_style)
           and not is_bookmarks_menu then
            return
        end

        if not self.page_info or not self.page_info_text or not self.page_return_arrow then
            return
        end

        if self.name == "zen_settings" then
            self.page_info_text.tap_input = nil
            self.page_info_text.hold_input = nil
        end

        local menu   = self
        local is_search = self.name == "filesearcher"
        local scr_w  = Screen:getWidth()
        local bar_x, bar_w = pager.getFooterGeometry(0, scr_w)
        -- Decide footer height once at init; page_number gets the taller strip.
        local page_number_style = pager.getStyle() == "page_number"
        local foot_h = page_number_style and pager.PN_FOOTER_H or pager.FOOTER_H
        local foot   = Geom:new{ w = scr_w, h = foot_h }

        -- _recalculateDimen uses getSize().h on these two widgets to compute
        -- bottom_height.  Returning foot reserves exactly that strip.
        self.page_info_text.getSize    = function() return foot end
        if not (is_rakuyomi and type(Rakuyomi.configureScrollBarFooter) == "function"
                and Rakuyomi.configureScrollBarFooter(self)) then
            self.page_return_arrow.getSize = function() return foot end
        end

        -- BottomContainer positions page_info at y = inner_dimen.h - h.
        self.page_info.getSize = function() return foot end
        if is_search then
            self.page_info:resetLayout()
        end

        local scr_h    = Screen:getHeight()
        local footer_y = is_search
            and (scr_h - foot_h)
            or  (self.dimen.y + self.dimen.h - foot_h)
        local menu_x = is_search and 0 or self.dimen.x

        local function menuContentBottom()
            local perpage = tonumber(menu.perpage) or 0
            local row_height = menu.item_dimen and tonumber(menu.item_dimen.h) or 0
            if perpage <= 0 or row_height <= 0 then return end
            local title_height = menu.title_bar and menu.title_bar:getHeight() or 0
            local content_height = perpage * row_height
            local rows = tonumber(menu.nb_rows)
            local item_height = tonumber(menu.item_height)
            local item_margin = tonumber(menu.item_margin) or 0
            if rows and rows > 0 and item_height and item_height > 0 then
                content_height = rows * item_height + (rows + 1) * item_margin
            elseif menu.files_per_page and item_height and item_height > 0 then
                content_height = Size.line.thin
                    + perpage * (item_height + Size.line.thin)
            end
            return menu.dimen.y + title_height + content_height
        end

        local function updateTouchZoneY(paint_y)
            for _i, zone in ipairs(menu._zen_page_number_zones or {}) do
                zone.screen_zone.ratio_y = paint_y / scr_h
                local registered = menu._zones and menu._zones[zone.id]
                local range = registered and registered.gs_range and registered.gs_range.range
                if range then
                    range.y = paint_y
                    range.h = foot_h
                end
            end
        end

        -- Replace the chevron rendering with the configured scroll indicator.
        -- x, y: absolute screen position supplied by BottomContainer.
        self.page_info.paintTo = function(_, bb, x, y)
            local paint_y = is_search and (scr_h - foot_h) or y
            local content_bottom = menuContentBottom()
            paint_y = pager.getCenteredFooterY(
                content_bottom,
                paint_y,
                foot_h,
                content_bottom ~= nil
            )
            updateTouchZoneY(paint_y)
            if is_search then
                bb:paintRect(0, paint_y, scr_w, foot_h, Blitbuffer.COLOR_WHITE)
                pager.paint(bb, bar_x, paint_y, bar_w, foot_h, menu.page or 1, menu.page_num or 1)
                return
            end
            pager.paint(bb, x + bar_x, paint_y, bar_w, foot_h, menu.page or 1, menu.page_num or 1)
        end

        -- Register touch zones for the page-number footer.
        -- screen_zone uses ratio_x/y/w/h (fractions of screen dimensions),
        -- as required by InputContainer:registerTouchZones.
        -- Pre-compute ratios shared across zones.
        local rz_left_x   = (menu_x + bar_x) / scr_w
        local rz_right_x  = (menu_x + bar_x + bar_w - pager.CHEV_W) / scr_w
        local rz_center_x = (menu_x + bar_x + pager.CHEV_W) / scr_w
        local rz_chev_w   = pager.CHEV_W / scr_w
        local rz_center_w = math.max(0, bar_w - pager.CHEV_W * 2) / scr_w
        local rz_y        = footer_y / scr_h
        local rz_h        = foot_h / scr_h

        local function canUsePageNumber()
            return pager.getStyle() == "page_number" and (menu.page_num or 0) > 1
        end

        self._zen_page_number_zones = {
            -- Left chevron — tap: prev page.
            {
                id = "zen_pn_left_tap",
                ges = "tap",
                screen_zone = { ratio_x = rz_left_x,   ratio_y = rz_y, ratio_w = rz_chev_w,   ratio_h = rz_h },
                handler = function()
                    if not canUsePageNumber() then return end
                    local page = menu.page or 1
                    local target = page > 1 and (page - 1) or menu.page_num
                    menu:onGotoPage(target)
                    return true
                end,
            },
            -- Right chevron — tap: next page.
            {
                id = "zen_pn_right_tap",
                ges = "tap",
                screen_zone = { ratio_x = rz_right_x,  ratio_y = rz_y, ratio_w = rz_chev_w,   ratio_h = rz_h },
                handler = function()
                    if not canUsePageNumber() then return end
                    local page = menu.page or 1
                    local target = page < menu.page_num and (page + 1) or 1
                    menu:onGotoPage(target)
                    return true
                end,
            },
            -- Center area — tap: numeric "Go to page" input dialog.
            {
                id = "zen_pn_center_tap",
                ges = "tap",
                screen_zone = { ratio_x = rz_center_x, ratio_y = rz_y, ratio_w = rz_center_w, ratio_h = rz_h },
                handler = function()
                    if menu.name == "zen_settings" then return true end
                    if not canUsePageNumber() then return end
                    local createZenDialog = require("common/ui/zen_dialog")
                    local nb     = menu.page_num or 1
                    local dialog = createZenDialog{
                        title           = _("Go to page"),
                        input           = "",
                        input_type      = "number",
                        input_hint      = "1 - " .. tostring(nb),
                        button_text     = "\u{F124} " .. _("Go"),
                        button_callback = function(dialog)
                            local p = tonumber(dialog:getInputText())
                            if p and p >= 1 and p <= nb then
                                UIManager:close(dialog)
                                menu:onGotoPage(math.floor(p))
                            end
                        end,
                    }
                    UIManager:show(dialog)
                    dialog:onShowKeyboard()
                    return true
                end,
            },
            -- Left chevron — hold: skip back (configurable) or jump to first page.
            {
                id = "zen_pn_left_hold",
                ges = "hold",
                screen_zone = { ratio_x = rz_left_x,  ratio_y = rz_y, ratio_w = rz_chev_w, ratio_h = rz_h },
                handler = function()
                    if not canUsePageNumber() then return end
                    local skip   = pager.getHoldSkip()
                    local page   = menu.page or 1
                    local target = skip == "ends"
                        and 1
                        or  math.max(1, page - (tonumber(skip) or 10))
                    menu:onGotoPage(target)
                    return true
                end,
            },
            -- Right chevron — hold: skip forward (configurable) or jump to last page.
            {
                id = "zen_pn_right_hold",
                ges = "hold",
                screen_zone = { ratio_x = rz_right_x, ratio_y = rz_y, ratio_w = rz_chev_w, ratio_h = rz_h },
                handler = function()
                    if not canUsePageNumber() then return end
                    local skip   = pager.getHoldSkip()
                    local page   = menu.page or 1
                    local target = skip == "ends"
                        and menu.page_num
                        or  math.min(menu.page_num, page + (tonumber(skip) or 10))
                    menu:onGotoPage(target)
                    return true
                end,
            },
        }
        self:registerTouchZones(self._zen_page_number_zones)

        -- Re-run layout so the new sizes take effect before the first paint.
        self:_recalculateDimen()
    end
end

return apply_zen_scroll_bar
