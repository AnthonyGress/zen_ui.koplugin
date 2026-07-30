describe("Zen settings page", function()
    local Page
    local PageModule
    local saved_modules
    local shown_widgets

    local dependency_names = {
        "gettext",
        "ui/bidi",
        "ui/widget/menu",
        "ui/widget/infomessage",
        "ui/uimanager",
        "ffi/utf8proc",
        "util",
        "device",
        "ui/size",
        "ffi/blitbuffer",
        "ui/widget/inputdialog",
        "common/ui/icon_menu_item",
        "modules/settings/zen_settings",
        "common/ui/zen_settings_titlebar",
        "apps/filemanager/filemanager",
    }

    local Menu = {}

    function Menu:extend(prototype)
        prototype = prototype or {}
        setmetatable(prototype, { __index = self })
        prototype.__index = prototype
        return prototype
    end

    function Menu:new(instance)
        instance = instance or {}
        setmetatable(instance, { __index = self })
        instance:init()
        return instance
    end

    function Menu:init()
        self.item_table_stack = {}
        self.title_bar = self.custom_title_bar
        self:updateItems(1)
    end

    function Menu:updateItems(select_number)
        self.last_select_number = select_number
    end

    function Menu:onTap()
        self.top_menu_taps = (self.top_menu_taps or 0) + 1
        return true
    end

    function Menu:onSwipe()
        self.top_menu_swipes = (self.top_menu_swipes or 0) + 1
        return true
    end

    function Menu:getPageNumber()
        return 1
    end

    function Menu.onCloseWidget() end

    before_each(function()
        saved_modules = {}
        shown_widgets = {}
        for _i, name in ipairs(dependency_names) do
            saved_modules[name] = package.loaded[name] or false
        end
        ZenSpec.replace("gettext", function(text) return text end)
        ZenSpec.replace("ui/bidi", { mirroredUILayout = function() return false end })
        ZenSpec.replace("ui/widget/menu", Menu)
        ZenSpec.replace("ui/widget/infomessage", { new = function(_self, opts) return opts end })
        ZenSpec.replace("ui/uimanager", {
            close = function() end,
            nextTick = function(_self, callback) callback() end,
            show = function(_self, widget) shown_widgets[#shown_widgets + 1] = widget end,
        })
        ZenSpec.replace("ffi/utf8proc", {
            lowercase = function(text) return text:lower() end,
        })
        ZenSpec.replace("util", { fixUtf8 = function(text) return text end })
        ZenSpec.replace("device", {
            screen = {
                getWidth = function() return 600 end,
                getHeight = function() return 800 end,
            },
        })
        ZenSpec.replace("ui/size", { line = { thin = 1 } })
        ZenSpec.replace("ffi/blitbuffer", { COLOR_LIGHT_GRAY = 1 })
        ZenSpec.replace("ui/widget/inputdialog", { init = function() end })
        ZenSpec.replace("common/ui/icon_menu_item", {
            getSettingsFontSize = function() return 18 end,
            getSettingsRowHeight = function() return 64 end,
            installMenuPatch = function() end,
        })
        ZenSpec.replace("modules/settings/zen_settings", {
            build = function() return { sub_item_table = {} } end,
        })
        ZenSpec.replace("apps/filemanager/filemanager", {
            instance = {
                menu = {
                    onShowMenu = function(self)
                        self.opened = (self.opened or 0) + 1
                    end,
                },
            },
        })
        ZenSpec.replace("common/ui/zen_settings_titlebar", {
            new = function(_self, opts)
                opts.setState = function(self, title, back_visible, search_visible)
                    self.title = title
                    self.back_visible = back_visible
                    self.search_visible = search_visible
                end
                opts.setQuery = function(self, query) self.query = query end
                opts.collapseSearch = function(self)
                    self.search_collapsed = true
                end
                return opts
            end,
        })
        ZenSpec.unload("modules/settings/zen_settings_page")
        PageModule = require("modules/settings/zen_settings_page")
        Page = PageModule.Page
    end)

    after_each(function()
        _G.__ZEN_UI_SETTINGS_PAGE = nil
        ZenSpec.unload("modules/settings/zen_settings_page")
        for _i, name in ipairs(dependency_names) do
            package.loaded[name] = saved_modules[name] or nil
        end
    end)

    local function make_page(items)
        items._zen_title = "Settings"
        return Page:new{
            title = "Settings",
            item_table = items,
            _root_items = items,
        }
    end

    it("shows no root back button, navigates submenus, and updates radio choices", function()
        local choice = "a"
        local radio = {
            text = "Choice B",
            radio = true,
            checked_func = function() return choice == "b" end,
            callback = function() choice = "b" end,
        }
        local library_items = { radio }
        local library = { text = "Library >", sub_item_table = library_items }
        local settings = make_page({ library })

        assert.is_false(settings.title_bar.back_visible)
        assert.is_true(settings.title_bar.search_visible)
        assert.are.equal("Library", library._zen_display_text)
        assert.is_true(library._zen_has_submenu)

        settings:onMenuSelect(library)
        assert.are.equal("Library", settings.title_bar.title)
        assert.is_true(settings.title_bar.back_visible)
        assert.is_true(settings.title_bar.search_visible)

        settings:onMenuSelect(radio)
        assert.are.equal("b", choice)
        assert.is_true(radio.checked_func())

        settings:backToUpperMenu()
        assert.are.equal("Settings", settings.title_bar.title)
        assert.is_false(settings.title_bar.back_visible)
        assert.is_true(settings.title_bar.search_visible)
    end)

    it("reuses the active settings page", function()
        local plugin = { config = {} }
        local first = PageModule.show(plugin)
        local second = PageModule.show(plugin)

        assert.are.equal(first, second)
        assert.are.equal(1, #shown_widgets)

        first:closeMenu()
        local reopened = PageModule.show(plugin)
        assert.are_not.equal(first, reopened)
        assert.are.equal(2, #shown_widgets)
    end)

    it("covers the underlying page when first opened", function()
        local settings = make_page({})

        assert.is_true(settings.covers_fullscreen)
    end)

    it("restores the parent title when the parent table refreshes on back", function()
        local library = { text = "Library", sub_item_table = {{ text = "Layout" }} }
        local root = { library }
        root.needs_refresh = true
        root.refresh_func = function() return { library } end
        local settings = make_page(root)

        settings:onMenuSelect(library)
        assert.are.equal("Library", settings.title_bar.title)

        settings:backToUpperMenu()
        assert.are.equal("Settings", settings.title_bar.title)
        assert.is_false(settings.title_bar.back_visible)
    end)

    it("searches every settings branch and navigates to a matching row", function()
        local timeout = { text = "Screen timeout" }
        local controls = { text = "Controls", sub_item_table = { timeout } }
        local library = {
            text = "Library",
            sub_item_table = {{ text = "Items per page" }},
        }
        local settings = make_page({ controls, library })

        settings:onMenuSelect(library)
        settings:_onSearchChanged("screen")

        assert.is_true(settings._search_active)
        assert.are.equal(1, #settings.item_table)
        assert.are.equal("Screen timeout", settings.item_table[1].text)
        assert.are.equal("Controls", settings.item_table[1]._zen_settings_breadcrumb)

        settings:onMenuSelect(settings.item_table[1])
        assert.is_false(settings._search_active)
        assert.are.equal(controls.sub_item_table, settings.item_table)
        assert.are.equal("Controls", settings.title_bar.title)
        assert.is_true(settings.title_bar.search_collapsed)
        assert.are.equal(1, settings.itemnumber)
    end)

    it("collapses an empty search pill to an icon when opening a submenu", function()
        local controls = { text = "Controls", sub_item_table = {{ text = "Screen timeout" }} }
        local settings = make_page({ controls })

        settings:_onSearchChanged("control")
        settings:_onSearchChanged("")
        settings:onMenuSelect(controls)

        assert.are.equal("Controls", settings.title_bar.title)
        assert.is_true(settings.title_bar.search_visible)
        assert.is_true(settings.title_bar.search_collapsed)
    end)

    it("opens the KOReader menu from the physical Menu key", function()
        local settings = make_page({})
        local menu = require("apps/filemanager/filemanager").instance.menu

        assert.is_true(settings:onLeftButtonTap())
        assert.are.equal(1, menu.opened)
    end)

    it("keeps top-menu gestures away from header controls and their edges", function()
        local settings = make_page({})
        settings.title_bar.close_button = { dimen = { x = 50, y = 10, w = 24, h = 24 } }

        assert.is_true(settings:onTap(nil, { pos = { x = 46, y = 20 } }))
        assert.is_true(settings:onSwipe(nil, { pos = { x = 55, y = 20 } }))
        assert.is_nil(settings.top_menu_taps)
        assert.is_nil(settings.top_menu_swipes)
    end)

    it("leaves unoccupied header space for the KOReader top menu", function()
        local settings = make_page({})
        settings.title_bar.close_button = { dimen = { x = 50, y = 10, w = 24, h = 24 } }

        assert.is_true(settings:onTap(nil, { pos = { x = 100, y = 10 } }))
        assert.is_true(settings:onSwipe(nil, { pos = { x = 100, y = 10 } }))
        assert.are.equal(1, settings.top_menu_taps)
        assert.are.equal(1, settings.top_menu_swipes)
    end)

    it("opens an arrange-only item from search", function()
        local opened = 0
        local home = {
            text = "Home",
            _zen_search_items_func = function()
                return {
                    {
                        text = "Quotes",
                        _zen_search_breadcrumb = "Home",
                        _zen_search_open = function() opened = opened + 1 end,
                    },
                }
            end,
        }
        local settings = make_page({ home })

        settings:_onSearchChanged("quotes")

        assert.are.equal(1, #settings.item_table)
        assert.are.equal("Quotes", settings.item_table[1].text)
        assert.are.equal("Home", settings.item_table[1]._zen_settings_breadcrumb)
        assert.is_true(settings.item_table[1]._zen_has_submenu)

        settings:onMenuSelect(settings.item_table[1])

        assert.are.equal(1, opened)
        assert.is_false(settings._search_active)
        assert.is_true(settings.title_bar.search_collapsed)
    end)

end)
