local function apply_zen_mode()
    local FileManagerMenu = require("apps/filemanager/filemanagermenu")
    local ReaderMenu = require("apps/reader/modules/readermenu")

    local zen_plugin = rawget(_G, "__ZEN_UI_PLUGIN")

    local function is_enabled()
        local features = zen_plugin and zen_plugin.config and zen_plugin.config.features
        return type(features) == "table" and features.zen_mode == true
    end

    local blocked_exact = {
        ["filebrowser"] = true,
        ["file browser"] = true,
        ["settings"] = true,
        ["setting"] = true,
        ["tools"] = true,
        ["search"] = true,
        ["menu"] = true,
        ["navi"] = true,
    }

    local blocked_contains = {
        "filebrowser",
        "setting",
        "tools",
        "search",
        "menu",
        "typeset",
        "display",
        "book",
        "status",
        "frontlight",
        "network",
        "screen",
        "navigation",
    }

    local allow_exact = {
        ["quicksettings"] = true,
        ["quick settings"] = true,
    }

    local function normalize(value)
        if type(value) ~= "string" then
            return nil
        end
        local s = value:lower():gsub("%s+", " ")
        s = s:gsub("^%s+", ""):gsub("%s+$", "")
        return s
    end

    local function tab_values(tab)
        if type(tab) ~= "table" then
            return {}
        end

        local values = {}

        local function push(v)
            if type(v) == "string" then
                local n = normalize(v)
                if n and n ~= "" then
                    table.insert(values, n)
                end
            end
        end

        push(tab.text)

        if type(tab.text_func) == "function" then
            local ok, text = pcall(tab.text_func)
            if ok and type(text) == "string" then
                push(text)
            end
        end

        push(tab.name)
        push(tab.id)
        push(tab.icon)

        return values
    end

    local function should_keep_tab(tab)
        if not is_enabled() then
            return true
        end

        local values = tab_values(tab)
        if #values == 0 then
            return true
        end

        for _, value in ipairs(values) do
            if allow_exact[value] then
                return true
            end
        end

        for _, value in ipairs(values) do
            if blocked_exact[value] then
                return false
            end
            for _, token in ipairs(blocked_contains) do
                if value:find(token, 1, true) then
                    return false
                end
            end
        end

        return true
    end

    local function filter_tab_item_table(tab_item_table)
        if type(tab_item_table) ~= "table" then
            return tab_item_table
        end

        local filtered = {}
        for _, tab in ipairs(tab_item_table) do
            if should_keep_tab(tab) then
                table.insert(filtered, tab)
            end
        end

        return filtered
    end

    local orig_fm_setUpdateItemTable = FileManagerMenu.setUpdateItemTable
    FileManagerMenu.setUpdateItemTable = function(self)
        orig_fm_setUpdateItemTable(self)
        if self.tab_item_table then
            self.tab_item_table = filter_tab_item_table(self.tab_item_table)
        end
    end

    local orig_reader_setUpdateItemTable = ReaderMenu.setUpdateItemTable
    ReaderMenu.setUpdateItemTable = function(self)
        orig_reader_setUpdateItemTable(self)
        if self.tab_item_table then
            self.tab_item_table = filter_tab_item_table(self.tab_item_table)
        end
    end

    local ReaderConfig = require("apps/reader/modules/readerconfig")

    local orig_onShowConfigMenu = ReaderConfig.onShowConfigMenu
    ReaderConfig.onShowConfigMenu = function(self)
        if is_enabled() then return end
        return orig_onShowConfigMenu(self)
    end

    local ReaderStatus = require("apps/reader/modules/readerstatus")

    local orig_onEndOfBook = ReaderStatus.onEndOfBook
    ReaderStatus.onEndOfBook = function(self)
        if is_enabled() then
            return self:onShowBookStatus()
        end
        return orig_onEndOfBook(self)
    end

    local BookStatusWidget = require("ui/widget/bookstatuswidget")

    local orig_getStatusContent = BookStatusWidget.getStatusContent
    BookStatusWidget.getStatusContent = function(self, width)
        if not is_enabled() then
            return orig_getStatusContent(self, width)
        end

        local _ = require("gettext")
        local Size = require("ui/size")
        local Device = require("device")
        local Screen = Device.screen
        local IconButton = require("ui/widget/iconbutton")
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
            local file = ui and ui.document and ui.document.file
            if self.updated then
                ui.doc_settings:flush()
            end
            UIManager:close(self)
            if ui and ui.document then
                ui:onClose()
                if type(ui.showFileManager) == "function" then
                    ui:showFileManager(file)
                end
            end
        end

        local close_btn = IconButton:new{
            icon = "close",
            width = close_size, height = close_size,
            padding = btn_pad,
            show_parent = self,
            callback = function() self:onClose() end,
            allow_flash = false,
        }
        local home_btn = IconButton:new{
            icon = "home",
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

        return VerticalGroup:new{
            align = "left",
            title_bar,
            self:genBookInfoGroup(),
            stats_header,
            self:genStatisticsGroup(width),
            self:genHeader(_("Review")),
            summary_group,
            self:genHeader(self.readonly and _("Book Status") or _("Update Status")),
            self:generateSwitchGroup(width),
        }
    end
end

return apply_zen_mode
