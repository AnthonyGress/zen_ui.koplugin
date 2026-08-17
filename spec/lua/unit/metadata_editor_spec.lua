describe("metadata editor from Book Details", function()
    local BookInfo
    local KeyValuePage
    local Pager
    local TitleBar
    local shown_page
    local registered_zones
    local painted
    local populate_count
    local closed
    local center_taps
    local renamed_file
    local renamed_is_file
    local moved_from
    local moved_to
    local opened_with_file
    local created_open_with_button

    before_each(function()
        shown_page = nil
        registered_zones = nil
        painted = nil
        populate_count = 0
        closed = 0
        center_taps = 0
        renamed_file = nil
        renamed_is_file = nil
        moved_from = nil
        moved_to = nil
        opened_with_file = nil
        created_open_with_button = nil

        ZenSpec.replace("device", {
            screen = {
                getWidth = function() return 600 end,
                getHeight = function() return 800 end,
                scaleBySize = function(_self, value) return value end,
            },
        })
        ZenSpec.replace("gettext", function(text) return text end)
        ZenSpec.replace("ui/widget/button", {
            new = function(_self, values)
                created_open_with_button = values
                return values
            end,
        })
        ZenSpec.replace("ui/widget/horizontalgroup", {
            new = function(_self, values)
                values._zen_inline_group = true
                return values
            end,
        })
        ZenSpec.replace("ui/widget/horizontalspan", {
            new = function(_self, values) return values end,
        })
        TitleBar = {
            new = function(_self, values)
                values.stock_header = true
                values.getHeight = function() return 54 end
                return values
            end,
        }
        ZenSpec.replace("ui/widget/titlebar", TitleBar)
        ZenSpec.replace("common/ui/zen_settings_titlebar", {
            new = function(_self, values)
                values.zen_header = true
                values.getHeight = function() return 58 end
                values.back_button = { name = "back" }
                values.close_button = { name = "close" }
                values.generateHorizontalLayout = function(self)
                    return { { self.back_button, self.close_button } }
                end
                values.installFocusLayout = function(self, owner)
                    local row = self:generateHorizontalLayout()[1]
                    row._zen_settings_titlebar = true
                    table.insert(owner.layout, 1, row)
                    owner.selected.y = owner.selected.y + 1
                    return row
                end
                return values
            end,
        })
        Pager = {
            PN_FOOTER_H = 42,
            setPlugin = function() end,
            getFooterGeometry = function() return 24, 552 end,
            getChevronHitWidth = function() return 96 end,
            getChevronHitBottom = function(y, h) return y + h end,
            getStyle = function() return "page_number" end,
            getHoldSkip = function() return "ends" end,
            paint = function(_bb, x, y, w, h, page, pages)
                painted = { x = x, y = y, w = w, h = h, page = page, pages = pages }
            end,
        }
        ZenSpec.replace("common/ui/zen_pager", Pager)

        KeyValuePage = {
            _populateItems = function(self)
                populate_count = populate_count + 1
                self.layout = {}
                self._mock_items = {}
                self.selected = { x = 1, y = 1 }
                for index, entry in ipairs(self.kv_pairs) do
                    local value_widget = { text = entry[2] }
                    local content_row = {
                        {},
                        {},
                        { dimen = { w = 260, h = 40 }, value_widget },
                        resetLayout = function() end,
                    }
                    local item = {
                        kv_pairs_idx = index,
                        [1] = { [1] = content_row },
                    }
                    self._mock_items[index] = item
                    table.insert(self.layout, { item })
                end
            end,
            init = function(self)
                self.dimen = { x = 0, y = 0, w = 600, h = 800 }
                self.show_page = 2
                self.pages = 4
                self.selected = { x = 1, y = 1 }
                self.items_font_size = 18
                self.page_info = {
                    getSize = function() return { w = 400, h = 42 } end,
                }
                self.page_info_text = {
                    onTapSelectButton = function() center_taps = center_taps + 1 end,
                }
                self.registerTouchZones = function(_, zones) registered_zones = zones end
                self.onPrevPage = function(page)
                    page.show_page = page.show_page - 1
                    return true
                end
                self.onNextPage = function(page)
                    page.show_page = page.show_page + 1
                    return true
                end
                self.onGoToPage = function(page, target)
                    page.show_page = target
                    return true
                end
                self.onClose = function()
                    closed = closed + 1
                    return true
                end
                self.title_bar = TitleBar:new{
                    title = self.title,
                    width = 600,
                    left_icon = self.title_bar_left_icon,
                    left_icon_tap_callback = self.title_bar_left_icon_tap_callback,
                    close_callback = function() return self:onClose() end,
                    show_parent = self,
                }
                self:_populateItems()
            end,
        }
        function KeyValuePage:new(values)
            values = values or {}
            setmetatable(values, { __index = self })
            values:init()
            return values
        end
        ZenSpec.replace("ui/widget/keyvaluepage", KeyValuePage)

        BookInfo = {
            show = function()
                shown_page = KeyValuePage:new{
                    title = "Book information",
                    kv_pairs = {
                        { "Filename:", "test.epub" },
                        { "Format:", "EPUB" },
                        { "Size:", "1 MB" },
                    },
                }
            end,
        }
        ZenSpec.replace("apps/filemanager/filemanagerbookinfo", BookInfo)
        ZenSpec.unload("modules/filebrowser/patches/metadata_editor")
        require("modules/filebrowser/patches/metadata_editor")()
    end)

    after_each(function()
        ZenSpec.unload("modules/filebrowser/patches/metadata_editor")
    end)

    local function zone(id)
        for _i, item in ipairs(registered_zones or {}) do
            if item.id == id then return item end
        end
    end

    it("uses the Zen header and pager only for the Details transition", function()
        local parent_closes = 0
        local bookinfo = setmetatable({
            ui = {
                showRenameFileDialog = function(_self, file, is_file)
                    renamed_file = file
                    renamed_is_file = is_file
                end,
                moveFile = function(_self, from, to)
                    moved_from = from
                    moved_to = to
                    return true
                end,
                showOpenWithDialog = function(_self, file)
                    opened_with_file = file
                end,
            },
        }, { __index = BookInfo })
        local function show_from_details()
            bookinfo:showFromBookDetails("/books/test.epub", nil, {
                close_parent_callback = function()
                    parent_closes = parent_closes + 1
                end,
            })
        end
        show_from_details()

        assert.is_true(shown_page.title_bar.zen_header)
        assert.is_nil(shown_page.title_bar.stock_header)
        assert.are.equal("Book information", shown_page.title_bar.title)
        assert.is_true(shown_page.title_bar.title_full_width)
        assert.is_true(shown_page.title_bar.back_visible)
        assert.is_false(shown_page.title_bar.search_visible)
        assert.is_nil(shown_page.title_bar.status_factory())
        assert.is_true(shown_page.title_bar.back_callback())
        assert.are.equal(1, closed)
        assert.are.equal(0, parent_closes)

        show_from_details()
        assert.is_true(shown_page.title_bar.close_callback())
        assert.are.equal(2, closed)
        assert.are.equal(1, parent_closes)

        shown_page.page_info:paintTo({}, 0, 758)
        assert.are.same({ x = 24, y = 758, w = 552, h = 42, page = 2, pages = 4 }, painted)
        assert.is_true(zone("zen_metadata_editor_left_tap").handler())
        assert.are.equal(1, shown_page.show_page)
        assert.is_true(zone("zen_metadata_editor_right_tap").handler())
        assert.are.equal(2, shown_page.show_page)
        assert.is_true(zone("zen_metadata_editor_center_tap").handler())
        assert.are.equal(1, center_taps)
        assert.is_true(zone("zen_metadata_editor_right_hold").handler())
        assert.are.equal(4, shown_page.show_page)

        assert.is_function(shown_page.kv_pairs[1].hold_callback)
        shown_page.kv_pairs[1].hold_callback()
        shown_page.kv_pairs[1].hold_callback() -- Reopening after cancel replaces the pending hook.
        assert.are.equal("/books/test.epub", renamed_file)
        assert.is_true(renamed_is_file)
        assert.are.equal("test.epub", shown_page.kv_pairs[1][2])
        local populate_count_before_rename = populate_count
        assert.is_true(bookinfo.ui:moveFile("/books/test.epub", "/books/renamed.epub"))
        assert.are.equal(populate_count_before_rename + 1, populate_count)
        assert.are.equal("/books/test.epub", moved_from)
        assert.are.equal("/books/renamed.epub", moved_to)
        assert.are.equal("renamed.epub", shown_page.kv_pairs[1][2])
        assert.are.equal("renamed.epub", shown_page._mock_items[1][1][1][3][1].text)
        shown_page.kv_pairs[1].hold_callback()
        assert.are.equal("/books/renamed.epub", renamed_file)
        assert.are.equal("Size:", shown_page.kv_pairs[3][1])
        assert.are.equal("Open with…", created_open_with_button.text)
        assert.are.equal(2, created_open_with_button.bordersize)
        assert.are.equal(10, created_open_with_button.radius)
        assert.are.equal(18, created_open_with_button.text_font_size)
        assert.is_true(created_open_with_button.text_font_bold)
        local format_item = shown_page._mock_items[2]
        local inline_group = format_item[1][1][3][1]
        assert.is_true(inline_group._zen_inline_group)
        assert.are.equal("EPUB", inline_group[1].text)
        assert.are.equal(created_open_with_button, inline_group[3])
        assert.are.equal(shown_page.title_bar.back_button, shown_page.layout[1][1])
        assert.are.equal(shown_page.title_bar.close_button, shown_page.layout[1][2])
        assert.are.equal(created_open_with_button, shown_page.layout[3][1])
        assert.are.equal(2, shown_page.selected.y)
        created_open_with_button.callback()
        assert.are.equal("/books/renamed.epub", opened_with_file)

        registered_zones = nil
        renamed_file = nil
        opened_with_file = nil
        created_open_with_button = nil
        bookinfo:show("/books/test.epub")
        assert.is_true(shown_page.title_bar.stock_header)
        assert.is_nil(shown_page.title_bar.zen_header)
        assert.is_nil(shown_page.title_bar_left_icon)
        assert.is_nil(registered_zones)
        assert.is_nil(shown_page.kv_pairs[1].hold_callback)
        assert.are.equal("Size:", shown_page.kv_pairs[3][1])
        assert.is_nil(created_open_with_button)
        assert.is_nil(renamed_file)
        assert.is_nil(opened_with_file)
    end)
end)
