describe("OPDS header", function()
    local Browser, closed, menu_opened, returned, searched
    local originals = {}
    local replaced = {
        "opdsbrowser", "ui/bidi", "ffi/blitbuffer",
        "ui/widget/container/centercontainer", "ui/font",
        "ui/widget/container/framecontainer", "ui/geometry", "ui/gesturerange",
        "ui/widget/horizontalgroup", "ui/widget/horizontalspan", "ui/widget/imagewidget",
        "ui/widget/container/inputcontainer", "ui/widget/linewidget", "ui/widget/menu",
        "ui/size", "ui/widget/textboxwidget", "ui/widget/textwidget",
        "ui/widget/container/topcontainer", "ui/uimanager", "ui/widget/verticalgroup",
        "ui/widget/verticalspan", "common/ui/zen_icon_button",
        "common/ui/zen_modal_close", "common/zen_logger", "device", "opdsparser",
        "common/cover_utils", "common/utils", "common/plugin_root",
    }

    local function widget_class()
        local class = {}
        function class:extend(values)
            values = values or {}
            values.extend = self.extend
            values.new = function(cls, spec)
                spec = spec or {}
                return setmetatable(spec, { __index = cls })
            end
            return setmetatable(values, { __index = self })
        end
        function class:new(values) return values or {} end
        return class
    end

    local function generated_button(side, callback, icon)
        return {
            side = side,
            icon = icon,
            width = 24,
            height = 24,
            padding = 4,
            callback = callback,
            free = function(self) self.freed = true end,
        }
    end

    local function new_title_bar()
        local title_bar = {
            width = 320,
            title_h_padding = 4,
            button_padding = 4,
            left_icon = "menu",
            right_icon = "close",
        }
        function title_bar:clear()
            for i = #self, 1, -1 do self[i] = nil end
        end
        function title_bar:init()
            self.left_button = generated_button("left", self.left_icon_tap_callback, self.left_icon)
            self.right_button = generated_button("right", self.right_icon_tap_callback, self.right_icon)
            self[1] = self.left_button
            self[2] = self.right_button
        end
        title_bar:init()
        return title_bar
    end

    before_each(function()
        for _i, name in ipairs(replaced) do originals[name] = package.loaded[name] end
        closed, menu_opened, returned, searched = 0, 0, 0, 0

        Browser = {
            getPageNumber = function() return 1 end,
            mergeTitleBarIntoLayout = function() end,
            updatePageInfo = function() end,
            parseFeed = function() end,
            genItemTableFromCatalog = function() return {} end,
            editCatalogFromInput = function() end,
        }
        Browser.init = function(self)
            self.paths = self.paths or {}
            self.title_bar = new_title_bar()
            self.layout = { { self.title_bar.left_button }, { self.title_bar.right_button }, { self.item } }
            self.selected = { x = 1, y = 3 }
        end
        Browser.updateCatalog = function(self)
            self.layout = { { self.item } }
            self.selected = { x = 1, y = 1 }
            self:mergeTitleBarIntoLayout()
        end

        local Base = widget_class()
        local Menu = {
            onCloseWidget = function() end,
            updatePageInfo = function() end,
        }
        ZenSpec.replace("opdsbrowser", Browser)
        ZenSpec.replace("ui/bidi", { mirroredUILayout = function() return false end })
        ZenSpec.replace("ffi/blitbuffer", {
            COLOR_BLACK = 0, COLOR_DARK_GRAY = 1, COLOR_GRAY = 2,
            COLOR_LIGHT_GRAY = 3, COLOR_WHITE = 4,
        })
        for _i, name in ipairs({
            "ui/widget/container/centercontainer", "ui/widget/container/framecontainer",
            "ui/widget/horizontalgroup", "ui/widget/horizontalspan", "ui/widget/imagewidget",
            "ui/widget/linewidget", "ui/widget/textboxwidget", "ui/widget/textwidget",
            "ui/widget/container/topcontainer", "ui/widget/verticalgroup", "ui/widget/verticalspan",
        }) do
            ZenSpec.replace(name, Base)
        end
        ZenSpec.replace("ui/font", { getFace = function() return {} end })
        ZenSpec.replace("ui/geometry", Base)
        ZenSpec.replace("ui/gesturerange", Base)
        ZenSpec.replace("ui/widget/container/inputcontainer", Base)
        ZenSpec.replace("ui/widget/menu", Menu)
        ZenSpec.replace("ui/size", {
            padding = { small = 4, default = 4, button = 4 },
            margin = { default = 4 }, border = { window = 1 }, line = { medium = 1 },
        })
        ZenSpec.replace("ui/uimanager", {
            close = function() closed = closed + 1 end,
            nextTick = function(_, callback) callback() end,
            setDirty = function() end,
        })
        ZenSpec.replace("common/ui/zen_icon_button", {
            new = function(_, spec)
                spec.image = { dimen = {} }
                spec.handleEvent = function(self, event)
                    self.focused = event and event.name == "Focus" or false
                    return true
                end
                return spec
            end,
        })
        ZenSpec.replace("common/ui/zen_modal_close", { installDialog = function() end })
        ZenSpec.replace("common/zen_logger", {
            new = function() return { dbg = function() end, warn = function() end } end,
        })
        ZenSpec.replace("device", {
            screen = {
                scaleBySize = function(_, value) return value end,
                getWidth = function() return 600 end,
                getHeight = function() return 800 end,
            },
            hasKeys = function() return true end,
        })
        ZenSpec.replace("opdsparser", { parse = function() return {} end })
        ZenSpec.replace("common/cover_utils", {
            BORDER_SIZE = 1,
            getRatio = function() return 2 / 3 end,
        })
        ZenSpec.replace("common/utils", {
            resolveLocalIcon = function(dir, name) return dir .. name .. ".svg" end,
        })
        ZenSpec.replace("common/plugin_root", "/zen-ui")
        ZenSpec.unload("modules/global/patches/opds")
        _G.G_reader_settings = ZenSpec.memorySettings()
        _G.__ZEN_UI_PLUGIN = { config = { opds = {} } }
        require("modules/global/patches/opds")()
    end)

    after_each(function()
        ZenSpec.unload("modules/global/patches/opds")
        _G.__ZEN_UI_PLUGIN = nil
        for _i, name in ipairs(replaced) do package.loaded[name] = originals[name] end
    end)

    it("keeps back, search, and close together in a focusable header row", function()
        local browser = setmetatable({
            paths = { { url = "/catalog" } },
            search_url = "/search",
            item = { name = "book" },
            servers = {},
            onReturn = function() returned = returned + 1 end,
            searchCatalog = function() searched = searched + 1 end,
            showOPDSMenu = function() menu_opened = menu_opened + 1 end,
            onCloseAllMenus = function() closed = closed + 1 end,
        }, { __index = Browser })

        browser:init()
        local buttons = browser._zen_opds_header_buttons
        assert.are.equal(3, #buttons)
        assert.are.equal("back", buttons[1]._zen_opds_focus_id)
        assert.are.equal("search", buttons[2]._zen_opds_focus_id)
        assert.are.equal("close", buttons[3]._zen_opds_focus_id)
        assert.are.equal("/zen-ui/icons/tab_left.svg", buttons[1].file)
        assert.are.equal("/zen-ui/icons/quick_search.svg", buttons[2].file)
        assert.are.equal("/zen-ui/icons/close.svg", buttons[3].file)
        assert.are.equal("chevron.left", browser.title_bar.left_icon)
        assert.are.equal("close", browser.title_bar.right_icon)
        assert.are.equal("left", buttons[1].overlap_align)
        assert.are.equal("right", buttons[3].overlap_align)
        assert.is_true(browser.layout[1] == buttons)
        assert.is_true(browser.layout[2][1] == browser.item)
        assert.are.same({ x = 1, y = 2 }, browser.selected)

        buttons[1].callback()
        buttons[2].callback()
        buttons[3].callback()
        assert.are.equal(1, returned)
        assert.are.equal(1, searched)
        assert.are.equal(1, closed)

        browser:updateCatalog("/next")
        assert.are.equal(3, #browser.layout[1])
        assert.are.equal("back", browser.layout[1][1]._zen_opds_focus_id)
        assert.are.equal("search", browser.layout[1][2]._zen_opds_focus_id)
        assert.are.equal("close", browser.layout[1][3]._zen_opds_focus_id)
        assert.are.equal("chevron.left", browser.title_bar.left_icon)
        assert.are.equal("close", browser.title_bar.right_icon)
        assert.is_true(browser.layout[2][1] == browser.item)

        browser.search_url = nil
        browser:updateCatalog("/without-search")
        assert.are.equal("menu", browser.layout[1][2]._zen_opds_focus_id)
        browser.layout[1][2].callback()
        assert.are.equal(1, menu_opened)

        -- appendCatalog changes the title, which rebuilds TitleBar without fix_buttons.
        browser.title_bar:clear()
        browser.title_bar:init()
        assert.are.equal("chevron.left", browser.title_bar.left_button.icon)
        assert.are.equal("close", browser.title_bar.right_button.icon)
    end)
end)
