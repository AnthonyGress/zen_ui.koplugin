local function apply_navbar()
    -- Bottom Navigation Bar patch for KOReader File Manager
    -- Adds a tab bar at the bottom with Books, Manga, News, Continue
    -- Sits below pagination controls

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
    local navbar_font = Font:getFace("smallinfofont")
    local navbar_font_bold = Font:getFace("smallinfofontbold")
    local navbar_v_padding = Screen:scaleBySize(4)
    -- Dead zone at left/right edges to avoid stealing corner gesture taps
    local corner_dead_zone = math.floor(Screen:getWidth() / 12)
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
            search = false,
            exit = false,
            page_left = false,
            page_right = false,
            menu = false,
        },
        tab_order = { "page_left", "books", "manga", "news", "continue", "history", "favorites", "collections", "search", "exit", "page_right", "menu" },
        show_labels = true,
        books_label = "Books",
        manga_action = "rakuyomi",
        manga_folder = "",
        news_action = "quickrss",
        news_folder = "",
        colored = false,
        active_tab_color = {0x33, 0x99, 0xFF}, -- blue
        active_tab_styling = true,
        active_tab_bold = true,
        active_tab_underline = true,
        underline_above = true,
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
            icon = "tab_continue",
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
            id = "search",
            label = _("Search"),
            icon = "appbar.search",
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

    local function onTabSearch()
        local fm = FileManager.instance
        if fm and fm.filesearcher then
            fm.filesearcher:onShowFileSearch()
        end
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
        search = onTabSearch,
        exit = onTabExit,
        page_left = onTabPageLeft,
        page_right = onTabPageRight,
        menu = onTabMenu,
    }

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
    -- Flattened icons are black-on-white, but colorblitFromRGB32 treats bright
    -- pixels as full coverage. We invert the bitmap so the icon shape (now white)
    -- gets full color and the background (now black) gets none, then restore it.

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

    local function createTabWidget(tab, tab_w, is_active)
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
        local icon_path = utils.resolveLocalIcon(_icons_dir, tab.icon)
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

        local label
        if active_color then
            label = ColorTextWidget:new{
                text = tab.label,
                face = use_bold and navbar_font_bold or navbar_font,
                fgcolor = active_color,
            }
        else
            label = TextWidget:new{
                text = tab.label,
                face = use_bold and navbar_font_bold or navbar_font,
            }
        end

        local icon_label_group
        if config.show_labels then
            icon_label_group = VerticalGroup:new{
                align = "center",
                icon,
                label,
            }
        else
            icon_label_group = VerticalGroup:new{
                align = "center",
                icon,
            }
        end

        local show_underline = styled and config.active_tab_underline
        local underline
        if show_underline then
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
                    dimen = Geom:new{ w = tab_w, h = underline_thickness },
                }
                function color_line:paintTo(bb, x, y)
                    bb:paintRectRGB32(x, y, self.dimen.w, self.dimen.h, underline_color)
                end
                underline = color_line
            else
                underline = LineWidget:new{
                    dimen = Geom:new{ w = tab_w, h = underline_thickness },
                    background = underline_color,
                }
            end
        else
            underline = VerticalSpan:new{ width = underline_thickness }
        end

        local v_pad = config.show_labels and navbar_v_padding or navbar_v_padding * 2

        local children
        if config.underline_above then
            children = {
                align = "center",
                underline,
                VerticalSpan:new{ width = v_pad },
                icon_label_group,
                VerticalSpan:new{ width = v_pad },
            }
        else
            children = {
                align = "center",
                VerticalSpan:new{ width = v_pad },
                icon_label_group,
                VerticalSpan:new{ width = v_pad },
                underline,
            }
        end

        return CenterContainer:new{
            dimen = Geom:new{ w = tab_w, h = icon_label_group:getSize().h + v_pad * 2 + underline_thickness },
            VerticalGroup:new(children),
        }
    end

    -- === Build the full navbar ===

    local HorizontalSpan = require("ui/widget/horizontalspan")
    local navbar_h_padding = Screen:scaleBySize(10)

    local function getVisibleTabs()
        local visible = {}
        for _, id in ipairs(config.tab_order) do
            if (id == "books" or config.show_tabs[id]) and tabs_by_id[id] then
                table.insert(visible, tabs_by_id[id])
            end
        end
        return visible
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
        local tab_w = math.floor(inner_w / #visible_tabs)

        local row = HorizontalGroup:new{}
        for _, tab in ipairs(visible_tabs) do
            table.insert(row, createTabWidget(tab, tab_w, tab.id == active_tab))
        end

        local row_with_padding = HorizontalGroup:new{
            HorizontalSpan:new{ width = navbar_h_padding },
            row,
            HorizontalSpan:new{ width = navbar_h_padding },
        }

        local visual_children = { row_with_padding }

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
            -- Determine which tab was tapped based on x position
            local tap_x = ges.pos.x - navbar_h_padding
            local idx = math.floor(tap_x / tab_w) + 1
            idx = math.max(1, math.min(#visible_tabs, idx))
            local tapped_id = visible_tabs[idx].id
            local cb = tab_callbacks[tapped_id]
            if cb then cb() end
            -- Only update active tab for tabs that stay in the file browser
            local stays_in_browser = tapped_id == "books"
                or (tapped_id == "manga" and config.manga_action == "folder" and config.manga_folder ~= "")
                or (tapped_id == "news" and config.news_action == "folder" and config.news_folder ~= "")
            if stays_in_browser and tapped_id ~= active_tab then
                setActiveTab(tapped_id)
            end
            return true
        end

        navbar[1] = visual
        return navbar
    end

    -- === Hook Menu:init() to reduce height for FM and standalone views ===

    local Menu = require("ui/widget/menu")

    local function getNavbarHeight()
        if not is_navbar_enabled() then
            return 0
        end
        local nb = createNavBar()
        if not nb then return 0 end
        local h = nb:getSize().h
        nb:free()
        return h
    end

    -- Standalone views (History, Favorites, Collections, Rakuyomi) that should get navbar
    local standalone_view_names = {
        history = true,
        collections = true,
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
            self.height = Screen:getHeight() - getNavbarHeight()
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

    -- === Inject navbar INTO the existing fm_ui FrameContainer ===
    -- Deferred to run AFTER all plugins (coverbrowser etc.) finish init

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
            local inner_w = screen_w - navbar_h_padding * 2
            local tab_w_local = math.floor(inner_w / #vis_tabs)
            local tap_x = ges.pos.x - navbar_h_padding
            local idx = math.floor(tap_x / tab_w_local) + 1
            idx = math.max(1, math.min(#vis_tabs, idx))
            local tapped_id = vis_tabs[idx].id

            -- Already in this view, do nothing
            if tapped_id == view_tab_id then
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

            -- Update FM navbar active tab
            setActiveTab(tapped_id)

            -- Execute the tapped tab's callback
            local cb = tab_callbacks[tapped_id]
            if cb then cb() end

            return true
        end

        -- Expand dimen to full screen so gestures and repaints cover the navbar area
        menu.dimen.h = Screen:getHeight()

        -- Wrap with navbar below, opaque background to prevent FM navbar bleed-through
        local FrameContainer = require("ui/widget/container/framecontainer")
        menu[1] = FrameContainer:new{
            background = Blitbuffer.COLOR_WHITE,
            bordersize = 0,
            padding = 0,
            margin = 0,
            VerticalGroup:new{
                align = "left",
                menu[1],
                navbar,
            },
        }
    end

    local orig_setupLayout = FileManager.setupLayout

    function FileManager:setupLayout()
        orig_setupLayout(self)

        -- On reinit, re-inject (preserve active tab)
        self._navbar_injected = false

        -- Inject synchronously so the navbar is part of the widget tree on the
        -- first paint.  Deferring via nextTick caused a two-phase repaint where
        -- the file browser was visible for one frame before the navbar appeared.
        injectNavbar(self)
        UIManager:setDirty(self, "ui")
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
            injectStandaloneNavbar(self.booklist_menu, from_coll_list and "collections" or "favorites")
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
                local inner_w = screen_w - navbar_h_padding * 2
                local tab_w_local = math.floor(inner_w / #vis_tabs)
                local tap_x = ges.pos.x - navbar_h_padding
                local idx = math.floor(tap_x / tab_w_local) + 1
                idx = math.max(1, math.min(#vis_tabs, idx))
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
end


return apply_navbar
