describe("mosaic title strip", function()
    local MosaicMenuItem
    local FileManager
    local text_widgets
    local book_info

    before_each(function()
        text_widgets = {}
        book_info = {}
        MosaicMenuItem = {
            init = function(self) self.init_height = self.height end,
            update = function(self) self.update_height = self.height end,
            paintTo = function(self) self.stock_paints = (self.stock_paints or 0) + 1 end,
        }
        local function build_item()
            return MosaicMenuItem
        end
        ZenSpec.replace("mosaicmenu", { _updateItemsBuildUI = build_item })
        ZenSpec.replace("common/zen_logger", {
            new = function() return { dbg = function() end, warn = function() end } end,
        })
        ZenSpec.replace("bookinfomanager", {
            getBookInfo = function(_, path) return book_info[path] end,
        })
        ZenSpec.replace("device", { screen = { scaleBySize = function(_, value) return value end } })
        ZenSpec.replace("ffi/blitbuffer", {
            COLOR_BLACK = "black",
            COLOR_WHITE = "white",
            new = function(width, height, kind)
                return {
                    width = width, height = height, kind = kind,
                    fill = function(self, color) self.fill_color = color end,
                    free = function(self) self.freed = true end,
                }
            end,
        })
        ZenSpec.replace("ui/widget/textwidget", {
            new = function(_, values)
                values.getSize = function(self) return { w = #self.text * 5, h = self.bold and 16 or 13 } end
                values.paintTo = function(self, _bb, x, y)
                    self.paint_x, self.paint_y = x, y
                    self.painted = true
                end
                values.free = function(self) self.freed = true end
                text_widgets[#text_widgets + 1] = values
                return values
            end,
        })
        ZenSpec.replace("ui/bidi", { auto = function(text) return text end })
        ZenSpec.replace("common/ui/background", {
            library_path = function() return "" end,
            paintScreenRegion = function() return false end,
        })
        ZenSpec.replace("modules/filebrowser/patches/library_font", {
            scaleValue = function(value) return value end,
            getFace = function(size) return { size = size } end,
        })
        FileManager = { setupLayout = function(self) self.stock_layout = true end }
        ZenSpec.replace("apps/filemanager/filemanager", FileManager)
        _G.__ZEN_UI_PLUGIN = {
            config = { mosaic_title_strip = { show_title = true, show_author = true } },
        }
        ZenSpec.unload("modules/filebrowser/patches/mosaic_title_strip")
    end)

    after_each(function()
        _G.__ZEN_UI_PLUGIN = nil
    end)

    local function has_painted_text(expected)
        for _i, widget in ipairs(text_widgets) do
            if widget.text == expected and widget.painted then return true end
        end
        return false
    end

    it("reserves strip height and restores cell geometry after init and update", function()
        require("modules/filebrowser/patches/mosaic_title_strip")()
        local strip_h = assert(MosaicMenuItem._zen_strip_h)
        local item = setmetatable({ height = 240 }, { __index = MosaicMenuItem })

        item:init()
        assert.are.equal(240 - strip_h, item.init_height)
        assert.are.equal(240, item.height)
        item:update()
        assert.are.equal(240 - strip_h, item.update_height)
        assert.are.equal(240, item.height)
    end)

    it("renders cached title and first author line after CoverBrowser layout", function()
        require("modules/filebrowser/patches/mosaic_title_strip")()
        FileManager.setupLayout({ coverbrowser = true })
        book_info["/library/alpha.epub"] = {
            title = "Alpha",
            authors = "Zen Author\nSecond Author",
        }
        local item = setmetatable({
            height = 240,
            width = 160,
            filepath = "/library/alpha.epub",
            bookinfo_found = true,
            is_directory = false,
            menu = { name = "filemanager" },
        }, { __index = MosaicMenuItem })
        local target = {
            getType = function() return "bb8" end,
            blitFrom = function(self, source) self.source = source end,
        }

        item:paintTo(target, 10, 20)
        assert.are.equal(1, item.stock_paints)
        assert.is_true(has_painted_text("Alpha"))
        assert.is_true(has_painted_text("Zen Author"))
        assert.are.equal("Alpha", item._zen_strip_data.title)
        assert.are.equal("Zen Author", item._zen_strip_data.authors)
        assert.are.equal(item._zen_strip_bb, target.source)
    end)

    it("uses a filename title fallback and paints folder names", function()
        require("modules/filebrowser/patches/mosaic_title_strip")()
        FileManager.setupLayout({ coverbrowser = true })
        book_info["/library/Fallback Name.epub"] = { authors = "Author" }
        local target = {
            getType = function() return "bb8" end,
            blitFrom = function() end,
        }
        local book = setmetatable({
            height = 200, width = 140, filepath = "/library/Fallback Name.epub",
            bookinfo_found = true, menu = { name = "filemanager" },
        }, { __index = MosaicMenuItem })
        book:paintTo(target, 0, 0)
        assert.is_true(has_painted_text("Fallback Name"))

        local folder = setmetatable({
            height = 200, width = 140, is_directory = true, text = "Series/",
        }, { __index = MosaicMenuItem })
        folder:paintTo(target, 0, 0)
        assert.is_true(has_painted_text("Series"))
    end)
end)
