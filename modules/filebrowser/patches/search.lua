local function apply_search()
    local FileManagerFileSearcher = require("apps/filemanager/filemanagerfilesearcher")
    local InputDialog = require("ui/widget/inputdialog")
    local UIManager = require("ui/uimanager")
    local _ = require("gettext")

    -- Capture plugin reference at apply time (global is only set transiently)
    local zen_plugin = rawget(_G, "__ZEN_UI_PLUGIN")
    if not zen_plugin or type(zen_plugin.config) ~= "table" then
        return
    end

    local function is_enabled()
        local features = zen_plugin.config and zen_plugin.config.features
        return type(features) == "table" and features.search == true
    end

    local orig_onShowFileSearch = FileManagerFileSearcher.onShowFileSearch

    function FileManagerFileSearcher:onShowFileSearch(search_string)
        if not is_enabled() then
            return orig_onShowFileSearch(self, search_string)
        end

        local search_dialog

        local function _doSearch()
            local search_str = search_dialog:getInputText()
            if search_str == "" then return end
            FileManagerFileSearcher.search_string = search_str
            UIManager:close(search_dialog)
            -- Always: home folder, case insensitive, include subfolders, include metadata
            self.case_sensitive = false
            self.include_subfolders = true
            self.include_metadata = self.ui.coverbrowser and true or false
            FileManagerFileSearcher.search_path = G_reader_settings:readSetting("home_dir")
            local Trapper = require("ui/trapper")
            Trapper:wrap(function()
                self:doSearch()
            end)
        end

        local function _close()
            UIManager:close(search_dialog)
        end

        -- Patch InputDialog:onTap so tapping outside closes both keyboard AND dialog
        local orig_InputDialog_onTap = InputDialog.onTap

        local Font = require("ui/font")
        local TextWidget = require("ui/widget/textwidget")
        local HorizontalGroup = require("ui/widget/horizontalgroup")
        local HorizontalSpan = require("ui/widget/horizontalspan")
        local Device = require("device")
        local Screen = Device.screen

        local SEARCH_ICON = "\u{F002}"

        search_dialog = InputDialog:new{
            title = _("Search Library"),
            input = search_string or FileManagerFileSearcher.search_string,
            -- X close icon in top left
            title_bar_left_icon = "close",
            title_bar_left_icon_tap_callback = function()
                UIManager:close(search_dialog)
            end,
            buttons = {
                {
                    {
                        text             = SEARCH_ICON .. " " .. _("Search"),
                        is_enter_default = true,
                        callback = function()
                            _doSearch()
                        end,
                    },
                },
            },
        }

        -- Override onTap: always close the full dialog (keyboard + dialog) on outside tap
        function search_dialog:onTap(arg, ges)
            if self.deny_keyboard_hiding then
                return
            end
            if self:isKeyboardVisible() then
                local kb = self._input_widget and self._input_widget.keyboard
                if kb and kb.dimen and ges.pos:notIntersectWith(kb.dimen)
                   and ges.pos:notIntersectWith(self.dialog_frame.dimen) then
                    self:onCloseKeyboard()
                    UIManager:close(self)
                    return true
                end
                -- Tap is inside the keyboard or dialog area — let InputDialog handle it
                return orig_InputDialog_onTap(self, arg, ges)
            else
                if ges.pos:notIntersectWith(self.dialog_frame.dimen) then
                    UIManager:close(self)
                    return true
                end
            end
        end

        UIManager:show(search_dialog)
        search_dialog:onShowKeyboard()
        return true
    end

    -- Whole-word matching and description exclusion for Zen search
    local util = require("util")
    local DocumentRegistry = require("document/documentregistry")

    local function find_whole_word(text, pattern)
        -- Word char: ASCII alnum/_ OR any byte ≥ 128 (part of a UTF-8 multibyte sequence,
        -- i.e. any non-ASCII character: Cyrillic, CJK, Arabic, accented Latin, etc.)
        local function is_word_byte(b)
            return (b >= 48 and b <= 57)
                or (b >= 65 and b <= 90)
                or (b >= 97 and b <= 122)
                or b == 95
                or b >= 128
        end
        local start = 1
        while true do
            local s, e = string.find(text, pattern, start)
            if not s then return false end
            local before_ok = (s == 1) or not is_word_byte(text:byte(s - 1))
            local after_ok  = (e == #text) or not is_word_byte(text:byte(e + 1))
            if before_ok and after_ok then return true end
            start = s + 1
        end
    end

    local orig_isFileMatch = FileManagerFileSearcher.isFileMatch

    function FileManagerFileSearcher:isFileMatch(filename, fullpath, search_string, is_file)
        if not is_enabled() then
            return orig_isFileMatch(self, filename, fullpath, search_string, is_file)
        end
        if search_string == "*" then
            return true
        end
        -- Filename: whole-word, always case-insensitive
        if find_whole_word(util.stringLower(filename), search_string) then
            return true
        end
        -- Metadata: skip description, whole-word matching
        if self.include_metadata and is_file and DocumentRegistry:hasProvider(fullpath) then
            local book_props = self.ui.bookinfo:getDocProps(fullpath, nil, true)
            if next(book_props) ~= nil then
                local props = {"title", "authors", "series", "series_index", "language", "keywords"}
                for _, key in ipairs(props) do
                    local prop = book_props[key]
                    if prop then
                        if key == "series_index" then prop = tostring(prop) end
                        if find_whole_word(util.stringLower(prop), search_string) then
                            return true
                        end
                    end
                end
            else
                self.no_metadata_count = self.no_metadata_count + 1
            end
        end
    end

    -- Remove hamburger / select-mode icon from search results title bar,
    -- and route tap-and-hold to the Zen context menu (FileManager only).
    local orig_onMenuHold = FileManagerFileSearcher.onMenuHold
    local orig_onShowSearchResults = FileManagerFileSearcher.onShowSearchResults

    function FileManagerFileSearcher:onShowSearchResults(not_cached)
        local result = orig_onShowSearchResults(self, not_cached)

        local menu = self.booklist_menu
        if menu and is_enabled() then
            -- Remove left icon (hamburger / select-mode button) from title bar
            local tb = menu.title_bar
            if tb then
                local function remove_from_overlap(group, widget)
                    if not widget then return end
                    for i = #group, 1, -1 do
                        if rawequal(group[i], widget) then
                            table.remove(group, i)
                            return
                        end
                    end
                end
                remove_from_overlap(tb, tb.left_button)
                tb.has_left_icon = false
                UIManager:setDirty(menu, "ui", tb.dimen)
            end

            -- Route tap-and-hold to Zen context menu in FileManager context
            menu.onMenuHold = function(menu_self, item)
                local fc = menu_self._manager
                    and menu_self._manager.ui
                    and menu_self._manager.ui.file_chooser
                if fc and fc.showFileDialog then
                    return fc:showFileDialog(item)
                end
                if orig_onMenuHold then
                    return orig_onMenuHold(menu_self, item)
                end
            end
        end

        return result
    end
end

return apply_search
