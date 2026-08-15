local function apply_book_status()
    local zen_plugin = rawget(_G, "__ZEN_UI_PLUGIN")

    -- Use KOReader's native "show Book Status at end of book" setting rather
    -- than hooking onEndOfBook ourselves.
    G_reader_settings:saveSetting("end_document_action", "book_status")

    -- Auto-mark the book as finished (summary.status = "complete") when the
    -- reader hits the end. ReaderStatus:onEndOfBook checks this before showing
    -- the Book Status widget, so it opens with "Finished" already selected.
    G_reader_settings:saveSetting("end_document_auto_mark", true)

    -- Always use the ZenOS custom Book Status layout (home + close buttons, cleaner stats)
    local BookStatusWidget = require("ui/widget/bookstatuswidget")
    local book_status = require("common/book_status")
    local library_navigation = require("common/library_navigation")
    local utils = require("common/utils")

    local _icons_dir
    local plugin_root = require("common/plugin_root")
    if plugin_root then _icons_dir = plugin_root .. "/icons/" end
    local _stock_icons_dir = require("libs/libkoreader-lfs").currentdir()
        .. "/resources/icons/mdlight/"

    local function resolve_icon(name)
        return utils.resolveIcon(_icons_dir, name)
            or utils.resolveLocalIcon(utils.getUserIconsDir(), name)
            or utils.resolveLocalIcon(_stock_icons_dir, name)
    end

    local function library_home_icon()
        local get_default_tab_icon = rawget(_G, "__ZEN_UI_NAVBAR_DEFAULT_TAB_ICON")
        local icon = type(get_default_tab_icon) == "function" and get_default_tab_icon()
        if type(icon) ~= "string" or icon == "" then
            local config = zen_plugin and zen_plugin.config
            local menu = type(config) == "table" and config.menu
            icon = type(menu) == "table" and menu.library_home_icon or "library"
        end
        return resolve_icon(icon) or resolve_icon("library")
    end

    if not BookStatusWidget._zen_status_cache_invalidation
            and type(BookStatusWidget.onChangeBookStatus) == "function" then
        BookStatusWidget._zen_status_cache_invalidation = true
        local original_onChangeBookStatus = BookStatusWidget.onChangeBookStatus
        function BookStatusWidget:onChangeBookStatus(...)
            local result = original_onChangeBookStatus(self, ...)
            local file = self.ui and self.ui.document and self.ui.document.file
            book_status.invalidate(file)
            return result
        end
    end

    local ok_reader_status, ReaderStatus = pcall(require, "apps/reader/modules/readerstatus")
    if ok_reader_status and not ReaderStatus._zen_status_cache_invalidation
            and type(ReaderStatus.markBook) == "function" then
        ReaderStatus._zen_status_cache_invalidation = true
        local original_markBook = ReaderStatus.markBook
        function ReaderStatus:markBook(...)
            local result = original_markBook(self, ...)
            local file = self.document and self.document.file
                or self.ui and self.ui.document and self.ui.document.file
            book_status.invalidate(file)
            return result
        end
    end

    BookStatusWidget.getStatusContent = function(self, width)
        local _ = require("gettext")
        local Size = require("ui/size")
        local Device = require("device")
        local Screen = Device.screen
        local ZenIconButton = require("common/ui/zen_icon_button")
        local Button = require("ui/widget/button")
        local CenterContainer = require("ui/widget/container/centercontainer")
        local Event = require("ui/event")
        local Geom = require("ui/geometry")
        local HorizontalGroup = require("ui/widget/horizontalgroup")
        local HorizontalSpan = require("ui/widget/horizontalspan")
        local VerticalGroup = require("ui/widget/verticalgroup")
        local VerticalSpan = require("ui/widget/verticalspan")
        local UIManager = require("ui/uimanager")

        -- Build a custom header row instead of TitleBar so both icons share the
        -- same HorizontalGroup centerline, compensating for the home SVG's
        -- built-in top whitespace that TitleBar's top-aligned OverlapGroup exposes.
        local DGENERIC_ICON_SIZE = G_defaults:readSetting("DGENERIC_ICON_SIZE")
        local close_size = Screen:scaleBySize(DGENERIC_ICON_SIZE * 0.85)
        local home_size  = Screen:scaleBySize(DGENERIC_ICON_SIZE * 1.1)
        local btn_pad    = Screen:scaleBySize(6)

        local home_callback = function()
            local ui = self.ui
            if self.updated then
                ui.doc_settings:flush()
            end
            UIManager:close(self)
            if ui and ui.document then
                library_navigation.showFromReader(ui, zen_plugin or rawget(_G, "__ZEN_UI_PLUGIN"))
            end
        end

        -- "Open next file" is only offered by KOReader when the folder collate
        -- order supports sequential navigation (not by access/date).
        local collate = G_reader_settings:readSetting("collate")
        local next_file_enabled = collate ~= "access" and collate ~= "date"

        local open_next_file_callback = function()
            local ui = self.ui
            if self.updated then
                ui.doc_settings:flush()
            end
            UIManager:close(self)
            UIManager:scheduleIn(0, function()
                if ui and ui.status then
                    ui.status:onOpenNextOrPreviousFileInFolder()
                end
            end)
        end

        -- On key devices, page-forward opens the next sequential file when
        -- available; otherwise it returns to the library.
        if Device:hasKeys() then
            if next_file_enabled then
                self.key_events.ZenOpenNextFile = { { Device.input.group.PgFwd } }
                self.onZenOpenNextFile = function()
                    open_next_file_callback()
                    return true
                end
            else
                self.key_events.ZenGoLibrary = { { Device.input.group.PgFwd } }
                self.onZenGoLibrary = function()
                    home_callback()
                    return true
                end
            end
        end

        local close_btn = ZenIconButton:new{
            file = resolve_icon("chevron.left"),
            width = close_size, height = close_size,
            padding = btn_pad,
            show_parent = self,
            callback = function() self:onClose() end,
        }
        local home_btn = ZenIconButton:new{
            file = library_home_icon(),
            width = home_size, height = home_size,
            padding = btn_pad,
            show_parent = self,
            callback = home_callback,
        }

        -- Center-align keeps both icons on the same horizontal midline
        local header_row = HorizontalGroup:new{
            align = "center",
            close_btn,
            HorizontalSpan:new{ width = width - (close_size + btn_pad * 2) - (home_size + btn_pad * 2) },
            home_btn,
        }
        local title_bar = VerticalGroup:new{
            header_row,
            VerticalSpan:new{ width = Size.padding.default },
        }

        -- Reduce the large top gap above the Statistics header (was Size.item.height_default ~48px)
        local stats_header = self:genHeader(_("Statistics"))
        if stats_header and stats_header[1] then
            stats_header[1].width = Size.span.vertical_default
        end

        -- Inject "Restart Book" button between the title/author block and the 5-star
        -- row by overriding generateRateGroup on this instance.  genBookInfoGroup calls
        -- self:generateRateGroup() internally, so the override is picked up through
        -- normal Lua method dispatch without duplicating genBookInfoGroup.
        -- genBookInfoGroup already has a large top gap (height * 0.2 ≈ 55px+) so the
        -- slightly taller content just shifts title/author up slightly — no overflow.
        local restart_book_btn = Button:new{
            text = _("Restart Book"),
            width = next_file_enabled and math.floor(width * 0.27) or math.floor(width * 0.55),
            show_parent = self,
            callback = function()
                local ui = self.ui
                if self.updated then
                    ui.doc_settings:flush()
                end
                UIManager:close(self)
                UIManager:scheduleIn(0, function()
                    UIManager:broadcastEvent(Event:new("GotoPage", 1))
                end)
            end,
        }
        local next_file_btn
        if next_file_enabled then
            next_file_btn = Button:new{
                text = _("Open next file"),
                width = math.floor(width * 0.27),
                preselect = true, -- inverts colors: black bg, white text
                show_parent = self,
                callback = open_next_file_callback,
            }
        end
        local orig_generateRateGroup = BookStatusWidget.generateRateGroup
        self.generateRateGroup = function(s, w, h, rating)
            local stars = orig_generateRateGroup(s, w, h, rating)
            local btn_h = restart_book_btn:getSize().h
            local btn_row
            if next_file_btn then
                btn_row = HorizontalGroup:new{
                    align = "center",
                    restart_book_btn,
                    HorizontalSpan:new{ width = Screen:scaleBySize(8) },
                    next_file_btn,
                }
            else
                btn_row = restart_book_btn
            end
            return VerticalGroup:new{
                CenterContainer:new{
                    dimen = Geom:new{ w = w, h = btn_h },
                    btn_row,
                },
                VerticalSpan:new{ width = Screen:scaleBySize(6) },
                stars,
            }
        end
        local book_info_group = self:genBookInfoGroup()
        self.generateRateGroup = nil -- remove instance override

        local summary_group = self:genSummaryGroup(width)
        -- Only open review dialog when the tap is within the note frame bounds
        if self.note_frame then
            self.note_frame.onGesture = function(frame, ev)
                if ev and ev.ges == "tap" and ev.pos
                        and frame.dimen and frame.dimen:contains(ev.pos) then
                    return self:openReviewDialog()
                end
            end
        end

        local switch_group = self:generateSwitchGroup(width)

        -- Keep the existing star selection while making the header and restart
        -- controls reachable by moving upward through the focus layout.
        table.insert(self.layout, 1, { close_btn, home_btn })
        table.insert(self.layout, 2, { restart_book_btn })
        self.selected.y = self.selected.y + 2

        return VerticalGroup:new{
            align = "left",
            title_bar,
            book_info_group,
            stats_header,
            self:genStatisticsGroup(width),
            self:genHeader(_("Review")),
            summary_group,
            self:genHeader(self.readonly and _("Book Status") or _("Update Status")),
            switch_group,
        }
    end
end

return apply_book_status
