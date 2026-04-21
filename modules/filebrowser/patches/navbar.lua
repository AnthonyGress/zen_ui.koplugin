local function apply_navbar()
    -- Bottom nav bar for the KOReader File Manager.

    local Blitbuffer = require("ffi/blitbuffer")
    local CenterContainer = require("ui/widget/container/centercontainer")
    local Device = require("device")
    local FileManager = require("apps/filemanager/filemanager")
    local FileChooser = require("ui/widget/filechooser")
    local Font = require("ui/font")
    local Geom = require("ui/geometry")
    local GestureRange = require("ui/gesturerange")
    local HorizontalGroup = require("ui/widget/horizontalgroup")
    local IconWidget = require("ui/widget/iconwidget")
    local InputContainer = require("ui/widget/container/inputcontainer")
    local LineWidget = require("ui/widget/linewidget")
    local TextWidget = require("ui/widget/textwidget")
    local UIManager = require("ui/uimanager")
    local VerticalGroup = require("ui/widget/verticalgroup")
    local VerticalSpan = require("ui/widget/verticalspan")
    local utils = require("common/utils")
    local Screen = Device.screen
    local _ = require("gettext")
    local lfs = require("libs/libkoreader-lfs")

    local zen_plugin = rawget(_G, "__ZEN_UI_PLUGIN")
    if not zen_plugin or type(zen_plugin.config) ~= "table" then
        return
    end

    local _icons_dir
    do
        local src = debug.getinfo(1, "S").source or ""
        if src:sub(1,1) == "@" then
            local root = src:sub(2):match("^(.*)/modules/")
            if root then _icons_dir = root .. "/icons/" end
        end
    end

    local function is_navbar_enabled()
        local features = zen_plugin.config and zen_plugin.config.features
        return type(features) == "table" and features.navbar == true
    end

    -- === Layout constants ===

    local navbar_icon_size = Screen:scaleBySize(34)
    local navbar_font = Font:getFace("smallinfofont", 20)
    local navbar_font_bold = Font:getFace("smallinfofontbold", 20)
    local navbar_v_padding = Screen:scaleBySize(4)
    -- Dead zone at left/right edges to avoid stealing corner gesture taps
    local corner_dead_zone = math.floor(Screen:getWidth() / 20)
    local underline_thickness = Screen:scaleBySize(2)

    -- === Persistent config ===

    local config_default = {
        show_tabs = {
            books = true,
            manga = true,
            news = true,
            continue = true,
            history = false,
            favorites = false,
            collections = false,
            authors = false,
            series = false,
            to_be_read = false,
            search = false,
            stats = false,
            exit = false,
            page_left = false,
            page_right = false,
            menu = false,
        },
        tab_order = { "page_left", "books", "manga", "news", "continue", "authors", "series", "to_be_read", "history", "favorites", "collections", "stats", "search", "exit", "page_right", "menu" },
        show_labels = true,
        books_label = "Library",
        manga_action = "rakuyomi",
        manga_folder = "",
        news_action = "quickrss",
        news_folder = "",
        colored = false,
        active_tab_color = {0x33, 0x99, 0xFF}, -- blue
        active_tab_styling = true,
        active_tab_bold = true,
        active_tab_underline = true,
        underline_above = false,
        show_top_border = false,
    }

    local function loadConfig()
        local config = zen_plugin.config.navbar or {}
        for k, v in pairs(config_default) do
            if config[k] == nil then
                config[k] = utils.deepcopy(v)
            end
        end
        if type(config.show_tabs) == "table" then
            for k, v in pairs(config_default.show_tabs) do
                if config.show_tabs[k] == nil then
                    config.show_tabs[k] = v
                end
            end
        else
            config.show_tabs = config_default.show_tabs
        end
        -- Ensure tab_order contains all known tabs
        if type(config.tab_order) ~= "table" then
            config.tab_order = config_default.tab_order
        else
            local order_set = {}
            for _, v in ipairs(config.tab_order) do order_set[v] = true end
            for _, v in ipairs(config_default.tab_order) do
                if not order_set[v] then
                    table.insert(config.tab_order, v)
                end
            end
        end
        zen_plugin.config.navbar = config
        return config
    end

    local config = loadConfig()

    -- === Tab definitions ===

    local function getBooksLabel()
        return config.books_label ~= "" and config.books_label or "Books"
    end

    local tabs = {
        {
            id = "books",
            label = getBooksLabel(),
            icon = "library",
        },
        {
            id = "manga",
            label = _("Manga"),
            icon = "tab_manga",
        },
        {
            id = "news",
            label = _("News"),
            icon = "tab_news",
        },
        {
            id = "continue",
            label = _("Continue"),
            icon = "book.opened",
        },
        {
            id = "history",
            label = _("History"),
            icon = "tab_history",
        },
        {
            id = "favorites",
            label = _("Favorites"),
            icon = "star.empty",
        },
        {
            id = "collections",
            label = _("Collections"),
            icon = "tab_collections",
        },
        {
            id = "authors",
            label = _("Authors"),
            icon = "tab_authors",
        },
        {
            id = "series",
            label = _("Series"),
            icon = "tab_series",
        },
        {
            id = "to_be_read",
            label = _("To Be Read"),
            icon = "tab_to_be_read",
        },
        {
            id = "search",
            label = _("Search"),
            icon = "appbar.search",
        },
        {
            id = "stats",
            label = _("Stats"),
            icon = "tab_stats",
        },
        {
            id = "exit",
            label = _("Exit"),
            icon = "tab_exit",
        },
        {
            id = "page_left",
            label = _("Prev"),
            icon = "tab_left",
        },
        {
            id = "page_right",
            label = _("Next"),
            icon = "tab_right",
        },
        {
            id = "menu",
            label = _("Menu"),
            icon = "appbar.menu",
        },
    }

    local tabs_by_id = {}
    for _, tab in ipairs(tabs) do
        tabs_by_id[tab.id] = tab
    end

    -- === Active tab tracking ===

    local active_tab = "books"
    local _last_menu_item = nil  -- tracks last long-held item for the menu tab

    -- Forward declarations; defined later
    local injectNavbar
    local injectStandaloneNavbar
    local hookQuickRSSInit
    local getNavbarHeight

    local function setActiveTab(id)
        active_tab = id
        local fm = FileManager.instance
        if fm then
            injectNavbar(fm)
            UIManager:setDirty(fm, "full")
        end
    end

    -- === Tab callbacks ===

    local function onTabBooks()
        local fm = FileManager.instance
        if not fm then return end
        local home_dir = G_reader_settings:readSetting("home_dir")
                         or require("apps/filemanager/filemanagerutil").getDefaultDir()
        fm.file_chooser.path_items[home_dir] = nil
        fm.file_chooser:changeToPath(home_dir)
    end

    local function onTabManga()
        local fm = FileManager.instance
        if not fm then return end

        if config.manga_action == "folder" and config.manga_folder ~= "" then
            if lfs.attributes(config.manga_folder, "mode") == "directory" then
                fm.file_chooser:changeToPath(config.manga_folder)
            else
                local InfoMessage = require("ui/widget/infomessage")
                UIManager:show(InfoMessage:new{
                    text = _("Manga folder not found: ") .. config.manga_folder,
                })
            end
            return
        end

        -- Default: open Rakuyomi
        local rakuyomi = fm.rakuyomi
        if rakuyomi then
            rakuyomi:openLibraryView()
        else
            local InfoMessage = require("ui/widget/infomessage")
            UIManager:show(InfoMessage:new{
                text = _("Rakuyomi plugin is not installed."),
            })
        end
    end

    local function onTabNews()
        local fm = FileManager.instance
        if not fm then return end

        if config.news_action == "folder" and config.news_folder ~= "" then
            if lfs.attributes(config.news_folder, "mode") == "directory" then
                fm.file_chooser:changeToPath(config.news_folder)
            else
                local InfoMessage = require("ui/widget/infomessage")
                UIManager:show(InfoMessage:new{
                    text = _("News folder not found: ") .. config.news_folder,
                })
            end
            return
        end

        -- Default: open QuickRSS
        hookQuickRSSInit()
        local ok, QuickRSSUI = pcall(require, "modules/ui/feed_view")
        if ok and QuickRSSUI then
            UIManager:show(QuickRSSUI:new{})
        else
            local InfoMessage = require("ui/widget/infomessage")
            UIManager:show(InfoMessage:new{
                text = _("QuickRSS plugin is not installed."),
            })
        end
    end

    local function onTabContinue()
        local last_file = G_reader_settings:readSetting("lastfile")
        if not last_file or lfs.attributes(last_file, "mode") ~= "file" then
            local InfoMessage = require("ui/widget/infomessage")
            UIManager:show(InfoMessage:new{
                text = _("Cannot open last document"),
            })
            return
        end
        local ReaderUI = require("apps/reader/readerui")
        ReaderUI:showReader(last_file)
    end

    local function onTabHistory()
        local fm = FileManager.instance
        if fm and fm.history then
            fm.history:onShowHist()
        end
    end

    local function onTabFavorites()
        local fm = FileManager.instance
        if fm and fm.collections then
            fm.collections:onShowColl()
        end
    end

    local function onTabCollections()
        local fm = FileManager.instance
        if fm and fm.collections then
            fm.collections:onShowCollList()
        end
    end

    local function onTabAuthors()
        local GroupView = zen_plugin._zen_shared and zen_plugin._zen_shared.group_view
        if GroupView then GroupView.showAuthorsView(injectStandaloneNavbar) end
    end

    local function onTabSeries()
        local GroupView = zen_plugin._zen_shared and zen_plugin._zen_shared.group_view
        if GroupView then GroupView.showSeriesView(injectStandaloneNavbar) end
    end

    local function onTabTBR()
        local GroupView = zen_plugin._zen_shared and zen_plugin._zen_shared.group_view
        if GroupView then GroupView.showTBRView(injectStandaloneNavbar) end
    end

    local function onTabSearch()
        local fm = FileManager.instance
        if fm and fm.filesearcher then
            fm.filesearcher:onShowFileSearch()
        end
    end

    local function onTabStats()
        local StatsPage = require("modules/filebrowser/patches/stats_page")
        local _createStatusRow = zen_plugin._zen_shared
            and zen_plugin._zen_shared.createStatusRow
        local _repaintTitleBar = zen_plugin._zen_shared
            and zen_plugin._zen_shared.repaintTitleBar
        local stats_page = StatsPage.create(_createStatusRow, _repaintTitleBar)
        injectStandaloneNavbar(stats_page, "stats")
        UIManager:show(stats_page)
    end

    local function onTabExit()
        local fm = FileManager.instance
        if fm then
            fm:onClose()
        end
    end

    local function onTabPageLeft()
        local fm = FileManager.instance
        if fm and fm.file_chooser then
            fm.file_chooser:onPrevPage()
        end
    end

    local function onTabPageRight()
        local fm = FileManager.instance
        if fm and fm.file_chooser then
            fm.file_chooser:onNextPage()
        end
    end

    local function onTabMenu()
        local fm = FileManager.instance
        if not fm or not fm.file_chooser then return end
        local fc = fm.file_chooser
        -- Prefer the last touch-held item, then the d-pad focused item,
        -- then fall back to the current directory.
        local item = _last_menu_item
        if not item and fc.itemnumber and fc.itemnumber > 0 then
            item = fc.item_table and fc.item_table[fc.itemnumber]
        end
        if not item then
            item = {
                path = fc.path,
                is_file = false,
                is_go_up = false,
                text = fc.path:match("([^/]+)/?$") or fc.path,
            }
        end
        fc:showFileDialog(item)
    end

    local tab_callbacks = {
        books = onTabBooks,
        manga = onTabManga,
        news = onTabNews,
        continue = onTabContinue,
        history = onTabHistory,
        favorites = onTabFavorites,
        collections = onTabCollections,
        authors = onTabAuthors,
        series = onTabSeries,
        to_be_read = onTabTBR,
        search = onTabSearch,
        stats = onTabStats,
        exit = onTabExit,
        page_left = onTabPageLeft,
        page_right = onTabPageRight,
        menu = onTabMenu,
    }

    -- === Color text support ===
    -- TextWidget.colorblitFrom converts to grayscale; colorblitFromRGB32 needed for color.

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

    -- === Colored icon widget ===
    -- Invert icon bitmap so colored pixels get full coverage, then restore.

    local ColorIconWidget = IconWidget:extend{
        _tint_color = nil,
    }

    function ColorIconWidget:paintTo(bb, x, y)
        if not self._tint_color or not Screen:isColorScreen() then
            IconWidget.paintTo(self, bb, x, y)
            return
        end

        if self.hide then return end
        local size = self:getSize()
        if not self.dimen then
            self.dimen = Geom:new{ x = x, y = y, w = size.w, h = size.h }
        else
            self.dimen.x = x
            self.dimen.y = y
        end
        self._bb:invert()
        bb:colorblitFromRGB32(
            self._bb, x, y,
            self._offset_x, self._offset_y,
            size.w, size.h,
            self._tint_color)
        self._bb:invert()
    end

    -- === Build a single tab (visual only) ===

    local navbar_font_size_steps = {20, 18, 16, 14}

    -- Returns the largest size from navbar_font_size_steps where every label fits within max_w.
    -- Uses the bold face as the worst-case width so all tabs stay at the same size.
    local function getSharedFontSize(labels, max_w)
        for _, size in ipairs(navbar_font_size_steps) do
            local bold_face = Font:getFace("smallinfofontbold", size)
            local all_fit = true
            for _, text in ipairs(labels) do
                local probe = TextWidget:new{ text = text, face = bold_face }
                local fits = probe:getSize().w <= max_w
                probe:free()
                if not fits then all_fit = false; break end
            end
            if all_fit then return size end
        end
        return navbar_font_size_steps[#navbar_font_size_steps]
    end

    local function createTabWidget(tab, label_max_w, is_active, font_size)
        local styled = is_active and config.active_tab_styling
        local use_color = styled and config.colored and Screen:isColorScreen()
        local active_color
        if use_color then
            local c = config.active_tab_color
            if c and type(c) == "table" then
                active_color = Blitbuffer.ColorRGB32(c[1], c[2], c[3], 0xFF)
            end
        end

        local use_bold = styled and config.active_tab_bold

        local icon
        local icon_path = utils.resolveIcon(_icons_dir, tab.icon)
        if active_color then
            icon = ColorIconWidget:new{
                icon   = icon_path and nil or tab.icon,
                file   = icon_path or nil,
                width  = navbar_icon_size,
                height = navbar_icon_size,
                _tint_color = active_color,
            }
        else
            icon = IconWidget:new{
                icon   = icon_path and nil or tab.icon,
                file   = icon_path or nil,
                width  = navbar_icon_size,
                height = navbar_icon_size,
            }
        end

        local size = font_size or navbar_font_size_steps[1]
        local label_face = Font:getFace(use_bold and "smallinfofontbold" or "smallinfofont", size)
        local label
        if active_color then
            label = ColorTextWidget:new{
                text = tab.label,
                face = label_face,
                max_width = label_max_w,
                fgcolor = active_color,
            }
        else
            label = TextWidget:new{
                text = tab.label,
                face = label_face,
                max_width = label_max_w,
            }
        end

        local show_underline = styled and config.active_tab_underline
        local underline
        if show_underline then
            local underline_w = config.show_labels and label:getSize().w or icon:getSize().w
            local underline_color = Blitbuffer.COLOR_BLACK
            if config.colored then
                local c = config.active_tab_color
                if c and type(c) == "table" then
                    underline_color = Blitbuffer.ColorRGB32(c[1], c[2], c[3], 0xFF)
                end
            end
            if config.colored and Screen:isColorScreen() then
                local Widget = require("ui/widget/widget")
                local color_line = Widget:new{
                    dimen = Geom:new{ w = underline_w, h = underline_thickness },
                }
                function color_line:paintTo(bb, x, y)
                    bb:paintRectRGB32(x, y, self.dimen.w, self.dimen.h, underline_color)
                end
                underline = color_line
            else
                underline = LineWidget:new{
                    dimen = Geom:new{ w = underline_w, h = underline_thickness },
                    background = underline_color,
                }
            end
        else
            underline = VerticalSpan:new{ width = underline_thickness }
        end

        local icon_label_group
        if config.show_labels then
            if config.underline_above then
                icon_label_group = VerticalGroup:new{
                    align = "center",
                    underline,
                    icon,
                    label,
                }
            else
                icon_label_group = VerticalGroup:new{
                    align = "center",
                    icon,
                    label,
                    underline,
                }
            end
        else
            if config.underline_above then
                icon_label_group = VerticalGroup:new{
                    align = "center",
                    underline,
                    icon,
                }
            else
                icon_label_group = VerticalGroup:new{
                    align = "center",
                    icon,
                    underline,
                }
            end
        end

        local v_pad = config.show_labels and navbar_v_padding or navbar_v_padding * 2

        local children = {
            align = "center",
            VerticalSpan:new{ width = v_pad },
            icon_label_group,
            VerticalSpan:new{ width = v_pad },
        }

        return VerticalGroup:new(children)
    end

    -- === Build the full navbar ===

    local HorizontalSpan = require("ui/widget/horizontalspan")
    local navbar_h_padding = Screen:scaleBySize(10)

    local navbar_max_tabs = 7

    local function getVisibleTabs()
        local visible = {}
        for _, id in ipairs(config.tab_order) do
            if (id == "books" or config.show_tabs[id]) and tabs_by_id[id] then
                table.insert(visible, tabs_by_id[id])
                if #visible >= navbar_max_tabs then break end
            end
        end
        return visible
    end

    local function getTabWidth(num_tabs)
        local inner_w = Screen:getWidth() - navbar_h_padding * 2
        return math.floor(inner_w / num_tabs)
    end

    local function tapIndexForTab(tap_x, tab_w, count)
        local idx = math.floor(tap_x / tab_w) + 1
        return math.max(1, math.min(count, idx))
    end

    local function createNavBar()
        if not is_navbar_enabled() then
            return nil
        end

        -- Update books tab label from config
        tabs_by_id["books"].label = getBooksLabel()

        local visible_tabs = getVisibleTabs()
        if #visible_tabs == 0 then return nil end

        local screen_w = Screen:getWidth()
        local inner_w = screen_w - navbar_h_padding * 2
        local num_tabs = #visible_tabs
        local label_max_w = math.floor(inner_w / num_tabs) - Screen:scaleBySize(4)

        -- Compute one font size that fits all labels so every tab uses the same size
        local tab_labels = {}
        for _, tab in ipairs(visible_tabs) do
            table.insert(tab_labels, tab.label)
        end
        local shared_font_size = getSharedFontSize(tab_labels, label_max_w)

        -- Build tab content widgets and measure their natural widths
        local tab_widgets = {}
        local total_content_w = 0
        for i, tab in ipairs(visible_tabs) do
            local widget = createTabWidget(tab, label_max_w, tab.id == active_tab, shared_font_size)
            tab_widgets[i] = widget
            total_content_w = total_content_w + widget:getSize().w
        end

        -- Space-evenly: distribute remaining width as equal gaps around and between tabs
        local remaining = inner_w - total_content_w
        local gap_count = num_tabs + 1
        local base_gap = math.max(0, math.floor(remaining / gap_count))
        local extra_pixels = remaining - base_gap * gap_count

        -- Build row with even spacing and track tab center positions for tap detection
        local row = HorizontalGroup:new{}
        local tab_centers = {}
        local x_pos = 0
        for i, widget in ipairs(tab_widgets) do
            local gap = base_gap + (i <= extra_pixels and 1 or 0)
            table.insert(row, HorizontalSpan:new{ width = gap })
            x_pos = x_pos + gap
            local w = widget:getSize().w
            tab_centers[i] = x_pos + w / 2
            table.insert(row, widget)
            x_pos = x_pos + w
        end
        table.insert(row, HorizontalSpan:new{ width = base_gap })

        local row_with_padding = HorizontalGroup:new{
            HorizontalSpan:new{ width = navbar_h_padding },
            row,
            HorizontalSpan:new{ width = navbar_h_padding },
        }

        local visual_children = {}

        if config.show_top_border then
            table.insert(visual_children, LineWidget:new{
                dimen = Geom:new{ w = screen_w, h = Screen:scaleBySize(1) },
                background = Blitbuffer.COLOR_DARK_GRAY,
            })
        end

        table.insert(visual_children, row_with_padding)

        local visual = VerticalGroup:new(visual_children)

        -- Wrap in InputContainer to handle taps on the whole navbar
        local navbar = InputContainer:new{
            dimen = Geom:new{ w = screen_w, h = visual:getSize().h },
            ges_events = {
                TapNavBar = {
                    GestureRange:new{
                        ges = "tap",
                        range = Geom:new{ x = 0, y = 0, w = screen_w, h = Screen:getHeight() },
                    },
                },
            },
        }

        navbar.onTapNavBar = function(self, _, ges)
            -- Only handle taps within the navbar's actual screen area
            if not self.dimen or not self.dimen:contains(ges.pos) then
                return false
            end
            -- Let corner gesture zones pass through
            if ges.pos.x < corner_dead_zone or ges.pos.x > screen_w - corner_dead_zone then
                return false
            end
            -- Find nearest tab by comparing tap position to midpoints between tab centers
            local tap_x = ges.pos.x - navbar_h_padding
            local idx = 1
            for i = 1, num_tabs - 1 do
                local boundary = (tab_centers[i] + tab_centers[i + 1]) / 2
                if tap_x >= boundary then
                    idx = i + 1
                else
                    break
                end
            end
            local tapped_id = visible_tabs[idx].id
            local cb = tab_callbacks[tapped_id]
            if cb then cb() end
            -- Track active tab for all persistent views (not transient: search/stats/exit/continue/menu/page_*)
            local track_tab = tapped_id == "books" or tapped_id == "manga"
                or tapped_id == "news"      or tapped_id == "authors"
                or tapped_id == "series"    or tapped_id == "to_be_read"
                or tapped_id == "history"   or tapped_id == "favorites"
                or tapped_id == "collections"
            if track_tab and tapped_id ~= active_tab then
                active_tab = tapped_id
                -- Only repaint the FM navbar for tabs that render inside it (not overlay views)
                local stays_in_browser = tapped_id == "books"
                    or (tapped_id == "manga" and config.manga_action == "folder" and config.manga_folder ~= "")
                    or (tapped_id == "news" and config.news_action == "folder" and config.news_folder ~= "")
                if stays_in_browser then
                    local fm = FileManager.instance
                    if fm then injectNavbar(fm); UIManager:setDirty(fm, "full") end
                end
            end
            return true
        end

        navbar[1] = visual
        return navbar
    end

    -- === Hook Menu:init() to reduce height for FM and standalone views ===

    local Menu = require("ui/widget/menu")

    getNavbarHeight = function()
        if not is_navbar_enabled() then
            return 0
        end
        local nb = createNavBar()
        if not nb then return 0 end
        local h = nb:getSize().h
        nb:free()
        return h
    end

    -- Standalone views (History, Favorites, Collections, Stats, Rakuyomi) that should get navbar
    local standalone_view_names = {
        history = true,
        collections = true,
        authors = true,
        series = true,
        to_be_read = true,
        authors_detail = true,
        series_detail = true,
        stats = true,
        library_view = true, -- Rakuyomi
    }

    -- Views where we inject navbar via nextTick in Menu:init
    -- (plugin views that can't be hooked via show functions)
    local standalone_nexttick_tab_ids = {
        library_view = "manga",
    }

    local function isStandaloneNavbarView(menu)
        if standalone_view_names[menu.name] then return true end
        -- Collections list has no name but has these flags
        if not menu.name and menu.covers_fullscreen and menu.is_borderless and menu.title_bar_fm_style then
            return true
        end
        return false
    end

    -- Flag to skip navbar for nested views (e.g. collection opened from collections list)
    -- or selection-mode dialogs (e.g. "add to collection")
    local _skip_standalone_navbar = false

    -- Track the last long-held item so the menu tab can show its context dialog.
    local orig_fc_onMenuHold = FileChooser.onMenuHold
    FileChooser.onMenuHold = function(self, item)
        _last_menu_item = item
        return orig_fc_onMenuHold and orig_fc_onMenuHold(self, item)
    end

    local orig_menu_init = Menu.init

    function Menu:init()
        if self.name == "filemanager" and not self.height then
            self.height = Screen:getHeight() - getNavbarHeight()
        elseif not _skip_standalone_navbar and isStandaloneNavbarView(self) then
            -- Override height even if already set (e.g. Rakuyomi sets height = screen_h)
            local reserve = getNavbarHeight()
            self.height = Screen:getHeight() - reserve
            -- Force borderless for plugin views that forgot to set it (e.g. Rakuyomi)
            if not self.is_borderless then
                self.is_borderless = true
            end
        end
        orig_menu_init(self)
        -- Plugin views (e.g. Rakuyomi) can't be hooked via show functions,
        -- so inject navbar via nextTick from here. Hide-pagination doesn't
        -- apply to these views so there's no ordering conflict.
        local nexttick_tab_id = standalone_nexttick_tab_ids[self.name]
        if nexttick_tab_id then
            local menu = self
            UIManager:nextTick(function()
                injectStandaloneNavbar(menu, nexttick_tab_id)
            end)
        end
    end

    -- === Auto-switch active tab on folder change ===

    local orig_onPathChanged = FileManager.onPathChanged

    function FileManager:onPathChanged(path)
        if orig_onPathChanged then
            orig_onPathChanged(self, path)
        end

        local function startsWith(str, prefix)
            return str:sub(1, #prefix) == prefix
        end

        local new_tab
        -- Check manga folder
        if config.manga_action == "folder" and config.manga_folder ~= "" then
            if path == config.manga_folder or startsWith(path, config.manga_folder .. "/") then
                new_tab = "manga"
            end
        end
        -- Check news folder
        if not new_tab and config.news_action == "folder" and config.news_folder ~= "" then
            if path == config.news_folder or startsWith(path, config.news_folder .. "/") then
                new_tab = "news"
            end
        end
        -- Check home dir for books
        if not new_tab then
            local home_dir = G_reader_settings:readSetting("home_dir")
                             or require("apps/filemanager/filemanagerutil").getDefaultDir()
            if path == home_dir or startsWith(path, home_dir .. "/") then
                new_tab = "books"
            end
        end

        if new_tab and new_tab ~= active_tab then
            active_tab = new_tab
            injectNavbar(self)
            UIManager:setDirty(self, "full")
        end
    end

    -- Inject navbar into FM after all plugins finish init.

    local function resizeFileChooser(file_chooser, target_height)
        if not file_chooser or target_height <= 0 then
            return
        end
        if file_chooser.height == target_height then
            return
        end

        local chrome = file_chooser.dimen.h - file_chooser.inner_dimen.h
        file_chooser.height = target_height
        file_chooser.dimen.h = target_height
        file_chooser.inner_dimen.h = target_height - chrome
        file_chooser:updateItems()
    end

    injectNavbar = function(fm)
        local fm_ui = fm[1]            -- FrameContainer wrapping file_chooser
        if not fm_ui then return end

        local file_chooser
        if fm._navbar_injected then
            -- Already injected: fm_ui[1] is VerticalGroup{file_chooser, navbar}
            local maybe_group = fm_ui[1]
            if type(maybe_group) == "table" and maybe_group[1] then
                file_chooser = maybe_group[1]
            else
                -- Guard against stale state after toggling feature off.
                file_chooser = maybe_group
            end
        else
            file_chooser = fm_ui[1]    -- the actual FileChooser/MosaicMenu widget
        end
        if not file_chooser then return end

        local navbar = createNavBar()
        if not navbar then
            fm_ui[1] = file_chooser
            fm._navbar_injected = false
            resizeFileChooser(file_chooser, Screen:getHeight())
            return
        end

        fm._navbar_injected = true

        -- Update FileChooser height to account for (potentially changed) navbar height
        local navbar_h = navbar:getSize().h
        local new_height = Screen:getHeight() - navbar_h
        resizeFileChooser(file_chooser, new_height)

        fm_ui[1] = VerticalGroup:new{
            align = "left",
            file_chooser,
            navbar,
        }
    end

    -- === Inject navbar into standalone views (History, Favorites, Collections) ===

    injectStandaloneNavbar = function(menu, view_tab_id)
        if not is_navbar_enabled() then
            return
        end
        if not menu or not menu[1] then return end

        -- Temporarily highlight the view's tab
        local saved_active = active_tab
        active_tab = view_tab_id
        local navbar = createNavBar()
        active_tab = saved_active

        if not navbar then return end

        -- Override tap handler for standalone view context
        navbar.onTapNavBar = function(self_nb, _, ges)
            if not self_nb.dimen or not self_nb.dimen:contains(ges.pos) then
                return false
            end
            local screen_w = Screen:getWidth()
            if ges.pos.x < corner_dead_zone or ges.pos.x > screen_w - corner_dead_zone then
                return false
            end
            local vis_tabs = getVisibleTabs()
            if #vis_tabs == 0 then return false end
            local tab_w_local = getTabWidth(#vis_tabs)
            local tap_x = ges.pos.x - navbar_h_padding
            local idx = tapIndexForTab(tap_x, tab_w_local, #vis_tabs)
            local tapped_id = vis_tabs[idx].id

            -- Already in this view: close detail to return to group, or scroll to first page
            if tapped_id == view_tab_id then
                local is_detail = menu.name == "authors_detail" or menu.name == "series_detail"
                if is_detail then
                    if menu.close_callback then
                        menu.close_callback()
                    elseif menu.onClose then
                        menu:onClose()
                    else
                        UIManager:close(menu)
                    end
                else
                    menu.page = 1
                    menu:updateItems()
                end
                return true
            end

            -- Close this standalone view first
            if menu.close_callback then
                menu.close_callback()
            elseif menu.onClose then
                menu:onClose()
            else
                UIManager:close(menu)
            end
            -- Unwind any parent stack (e.g. authors/series group view under a detail view)
            if menu._zen_close_stack then
                menu._zen_close_stack()
            end

            -- Update FM navbar active tab
            setActiveTab(tapped_id)

            -- Execute the tapped tab's callback
            local cb = tab_callbacks[tapped_id]
            if cb then cb() end

            return true
        end

        -- Expand dimen to full screen so gestures and repaints cover the navbar area
        menu.dimen.h = Screen:getHeight()
        -- Suppress the spurious partial_page_repaint nextTick forceRePaint that fires
        -- after updateItems on initial load — the UIManager:show() paint already covers it.
        menu._zen_no_forced_repaint = true

        -- Wrap with navbar below,
        -- opaque background to prevent FM navbar bleed-through
        local FrameContainer = require("ui/widget/container/framecontainer")
        local vg_children = { align = "left" }
        table.insert(vg_children, menu[1])
        table.insert(vg_children, navbar)

        menu[1] = FrameContainer:new{
            background = Blitbuffer.COLOR_WHITE,
            bordersize = 0,
            padding = 0,
            margin = 0,
            VerticalGroup:new(vg_children),
        }

        -- Top south swipe → open KOReader menu is handled globally by
        -- menu_top_swipe (class-level patch on Menu.onSwipe).
    end

    local function is_restore_enabled()
        local features = zen_plugin.config and zen_plugin.config.features
        return type(features) == "table" and features.restore_library_view == true
    end

    -- Save current library view state just before the reader takes over.
    -- The FM is about to be destroyed; we persist {tab, page} so that when
    -- showFileManager() recreates it we can scroll back to the right place.
    local skip_tabs_for_state = {
        books = true, manga = true, news = true,
        continue = true, search = true, stats = true, exit = true,
    }
    local orig_fm_onShowingReader = FileManager.onShowingReader
    function FileManager:onShowingReader()
        local gv = zen_plugin._zen_shared and zen_plugin._zen_shared.group_view
        if is_restore_enabled() and not skip_tabs_for_state[active_tab] then
            local page = 1
            -- Group views expose page via M.getActivePage
            if gv and gv.getActivePage then
                page = gv.getActivePage(active_tab) or 1
            end
            -- Standalone views: history / favorites / collections
            local fm = FileManager.instance
            if fm and active_tab == "history"
                    and fm.history and fm.history.booklist_menu then
                page = fm.history.booklist_menu.page or 1
            elseif fm and (active_tab == "favorites" or active_tab == "collections")
                    and fm.collections and fm.collections.booklist_menu then
                page = fm.collections.booklist_menu.page or 1
            end
            -- If a detail view (author/series book list) was open, save which one
            local detail_group, detail_page
            if gv and gv.getActiveDetail then
                local detail = gv.getActiveDetail()
                if detail then
                    detail_group = detail.group_name
                    detail_page  = detail.page
                end
            end
            _G.__ZEN_UI_LIBRARY_STATE = {
                tab          = active_tab,
                page         = page,
                detail_group = detail_group,
                detail_page  = detail_page,
            }
        else
            _G.__ZEN_UI_LIBRARY_STATE = nil
        end
        -- Close orphaned overlay menus to keep UIManager's stack clean
        if gv and gv.closeAll then gv.closeAll() end
        local fm = FileManager.instance
        if fm then
            if fm.history and fm.history.booklist_menu then
                UIManager:close(fm.history.booklist_menu)
                fm.history.booklist_menu = nil
            end
            if fm.collections then
                if fm.collections.booklist_menu then
                    UIManager:close(fm.collections.booklist_menu)
                    fm.collections.booklist_menu = nil
                end
                if fm.collections.coll_list then
                    UIManager:close(fm.collections.coll_list)
                    fm.collections.coll_list = nil
                end
            end
        end
        if orig_fm_onShowingReader then orig_fm_onShowingReader(self) end
    end

    local orig_setupLayout = FileManager.setupLayout

    function FileManager:setupLayout()
        orig_setupLayout(self)
        self._navbar_injected = false
        injectNavbar(self)
        -- On reinit (FM already in the window stack), dirty-mark so the updated navbar
        -- is painted. On fresh init, UIManager:show(fm) inside showFiles handles it.
        if FileManager.instance == self then
            UIManager:setDirty(self, "ui")
        end
    end

    -- Restore the view state (group tab + optional detail) when returning from the reader.
    -- Patching showFiles (rather than setupLayout) is critical: UIManager:show(fm) is called
    -- inside showFiles *after* setupLayout returns.  Any overlay we show here therefore lands
    -- *above* fm in the window stack, so _repaint starts from the overlay (topmost
    -- covers_fullscreen) and never paints the FM books view at all -- no flash, no artifacts.
    local orig_showFiles = FileManager.showFiles
    function FileManager:showFiles(path, focused_file, selected_files)
        -- When restore is disabled, drop focused_file so KOReader doesn't scroll
        -- the file browser to the page containing the last-opened book.
        local effective_focused = is_restore_enabled() and focused_file or nil
        orig_showFiles(self, path, effective_focused, selected_files)
        local state = rawget(_G, "__ZEN_UI_LIBRARY_STATE")
        if not is_restore_enabled() then
            _G.__ZEN_UI_LIBRARY_STATE = nil
            return
        end
        if not state or not state.tab or not tab_callbacks[state.tab] then return end
        local gv = zen_plugin._zen_shared and zen_plugin._zen_shared.group_view
        -- onPathChanged inside orig_setupLayout may have reset active_tab to "books";
        -- restore it now so onShowingReader saves the right tab on the next book open.
        active_tab = state.tab
        -- Open group/standalone view synchronously (stack: [fm, group_menu])
        tab_callbacks[state.tab]()
        -- If a detail view was open, open it synchronously too (stack: [fm, group_menu, detail_menu]).
        -- _repaint will then start from detail_menu and never show the intermediate views.
        if state.detail_group and gv and gv.restoreDetail then
            gv.restoreDetail(state.detail_group, state.tab, injectStandaloneNavbar)
        end
    end

    -- === Hook standalone views to inject navbar after creation ===
    -- Injection happens after UIManager:show() in the same execution frame,
    -- so the first paint uses the modified widget tree. No setDirty needed.

    local FileManagerHistory = require("apps/filemanager/filemanagerhistory")
    local orig_onShowHist = FileManagerHistory.onShowHist

    function FileManagerHistory:onShowHist(search_info)
        local result = orig_onShowHist(self, search_info)
        if self.booklist_menu then
            injectStandaloneNavbar(self.booklist_menu, "history")
            local state = rawget(_G, "__ZEN_UI_LIBRARY_STATE")
            if state and state.tab == "history" and state.page and state.page > 1 then
                local menu = self.booklist_menu
                _G.__ZEN_UI_LIBRARY_STATE = nil
                UIManager:nextTick(function()
                    if menu.onGotoPage then menu:onGotoPage(state.page) end
                end)
            end
        end
        return result
    end

    local FileManagerFileSearcher = require("apps/filemanager/filemanagerfilesearcher")
    local orig_onShowSearchResults = FileManagerFileSearcher.onShowSearchResults

    function FileManagerFileSearcher:onShowSearchResults(not_cached)
        local result = orig_onShowSearchResults(self, not_cached)
        if self.booklist_menu then
            injectStandaloneNavbar(self.booklist_menu, "search")
        end
        return result
    end

    local FileManagerCollection = require("apps/filemanager/filemanagercollection")
    local orig_onShowColl = FileManagerCollection.onShowColl

    function FileManagerCollection:onShowColl(collection_name)
        local from_coll_list = self.coll_list ~= nil
        local result = orig_onShowColl(self, collection_name)
        if self.booklist_menu then
            local inferred_tab = from_coll_list and "collections" or "favorites"
            injectStandaloneNavbar(self.booklist_menu, inferred_tab)
            local state = rawget(_G, "__ZEN_UI_LIBRARY_STATE")
            if state and state.tab == inferred_tab and state.page and state.page > 1 then
                local menu = self.booklist_menu
                _G.__ZEN_UI_LIBRARY_STATE = nil
                UIManager:nextTick(function()
                    if menu.onGotoPage then menu:onGotoPage(state.page) end
                end)
            end
        end
        return result
    end

    local orig_onShowCollList = FileManagerCollection.onShowCollList

    function FileManagerCollection:onShowCollList(file_or_selected_collections, caller_callback, no_dialog)
        -- Skip navbar in selection mode (adding file to collection, filtering by collection)
        if file_or_selected_collections ~= nil then
            _skip_standalone_navbar = true
        end
        local result = orig_onShowCollList(self, file_or_selected_collections, caller_callback, no_dialog)
        _skip_standalone_navbar = false
        -- Only inject navbar in browse mode, not selection mode
        if self.coll_list and file_or_selected_collections == nil then
            injectStandaloneNavbar(self.coll_list, "collections")
            local state = rawget(_G, "__ZEN_UI_LIBRARY_STATE")
            if state and state.tab == "collections" and state.page and state.page > 1 then
                local menu = self.coll_list
                _G.__ZEN_UI_LIBRARY_STATE = nil
                UIManager:nextTick(function()
                    if menu.onGotoPage then menu:onGotoPage(state.page) end
                end)
            end
        end
        return result
    end

    -- === Hook QuickRSS feed view to inject navbar ===
    -- QuickRSS extends InputContainer (not Menu), so Menu:init() hook doesn't apply.
    -- We hook its init lazily on first use since the plugin path isn't available at patch load time.

    local _qrss_hooked = false

    hookQuickRSSInit = function()
        if _qrss_hooked then return end
        local ok, QuickRSSUI_class = pcall(require, "modules/ui/feed_view")
        if not ok or not QuickRSSUI_class then return end
        _qrss_hooked = true

        local ok_ai, ArticleItemModule = pcall(require, "modules/ui/article_item")
        local QRSS_ITEM_HEIGHT = ok_ai and ArticleItemModule.ITEM_HEIGHT

        local orig_qrss_init = QuickRSSUI_class.init
        function QuickRSSUI_class:init()
            orig_qrss_init(self)

            local navbar_h = getNavbarHeight()
            if navbar_h <= 0 then return end

            -- Reduce the outer FrameContainer height
            self[1].height = self[1].height - navbar_h

            -- Reduce the article list area and recalculate items per page
            self.list_h = self.list_h - navbar_h
            if QRSS_ITEM_HEIGHT then
                self.items_per_page = math.max(1, math.floor(self.list_h / QRSS_ITEM_HEIGHT))
            end

            -- Inject navbar below the QuickRSS view
            local saved_active = active_tab
            active_tab = "news"
            local navbar = createNavBar()
            active_tab = saved_active
            if not navbar then return end

            -- Override tap handler for standalone view context
            navbar.onTapNavBar = function(self_nb, _, ges)
                if not self_nb.dimen or not self_nb.dimen:contains(ges.pos) then
                    return false
                end
                local screen_w = Screen:getWidth()
                if ges.pos.x < corner_dead_zone or ges.pos.x > screen_w - corner_dead_zone then
                    return false
                end
                local vis_tabs = getVisibleTabs()
                if #vis_tabs == 0 then return false end
                local tab_w_local = getTabWidth(#vis_tabs)
                local tap_x = ges.pos.x - navbar_h_padding
                local idx = tapIndexForTab(tap_x, tab_w_local, #vis_tabs)
                local tapped_id = vis_tabs[idx].id
                if tapped_id == "news" then return true end
                self:onClose()
                setActiveTab(tapped_id)
                local cb = tab_callbacks[tapped_id]
                if cb then cb() end
                return true
            end

            -- Wrap with navbar below, opaque background to prevent bleed-through
            local FrameContainer = require("ui/widget/container/framecontainer")
            self[1] = FrameContainer:new{
                background = Blitbuffer.COLOR_WHITE,
                bordersize = 0,
                padding = 0,
                margin = 0,
                VerticalGroup:new{
                    align = "left",
                    self[1],
                    navbar,
                },
            }

            -- Set dimen to full screen for gesture handling and setDirty
            self.dimen = Geom:new{ w = Screen:getWidth(), h = Screen:getHeight() }

            -- Re-populate with corrected items_per_page
            if #self.articles > 0 then
                self:_populateItems()
            end
        end

        local orig_qrss_onClose = QuickRSSUI_class.onClose
        function QuickRSSUI_class:onClose()
            orig_qrss_onClose(self)
            -- Reset FM navbar to "books" when QuickRSS closes via its own close button
            setActiveTab("books")
        end
    end

    -- Hook QuickRSS init eagerly so navbar support is ready regardless
    -- of how QuickRSS is opened.
    hookQuickRSSInit()

    -- Expose a reinject function for external callers (e.g. quickstart on_close).
    -- Allows main.lua to rebuild the navbar after quickstart changes tab config.
    _G.__ZEN_UI_REINJECT_FM_NAVBAR = function()
        local fm = FileManager.instance
        if fm then
            injectNavbar(fm)
            UIManager:setDirty(fm, "full")
        else
            UIManager:setDirty(nil, "full")
        end
        UIManager:forceRePaint()
    end
end


return apply_navbar
