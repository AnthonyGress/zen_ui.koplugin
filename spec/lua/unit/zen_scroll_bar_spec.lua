describe("Zen scroll bar", function()
    local Menu
    local shown
    local centered_content_bottom
    local saved_modules

    local module_names = {
        "gettext",
        "ffi/blitbuffer",
        "device",
        "ui/geometry",
        "ui/widget/menu",
        "ui/size",
        "ui/uimanager",
        "common/ui/zen_pager",
        "common/ui/zen_dialog",
        "common/ui/zen_scroll_bar",
    }

    local function find_zone(menu, id)
        for _i, zone in ipairs(menu._zen_page_number_zones) do
            if zone.id == id then return zone end
        end
    end

    local function new_menu(name)
        local menu = {
            name = name,
            page = 1,
            page_num = 3,
            dimen = { x = 0, y = 0, w = 600, h = 800 },
        }
        setmetatable(menu, { __index = Menu })
        Menu.init(menu)
        return menu
    end

    before_each(function()
        saved_modules = {}
        for _i, name in ipairs(module_names) do
            saved_modules[name] = package.loaded[name] or false
        end
        shown = nil
        centered_content_bottom = nil
        Menu = {
            init = function(self)
                self.page_info = { resetLayout = function() end }
                self.page_info_text = { tap_input = {}, hold_input = {} }
                self.page_return_arrow = {}
            end,
            registerTouchZones = function() end,
            _recalculateDimen = function() end,
        }
        ZenSpec.replace("gettext", function(text) return text end)
        ZenSpec.replace("ffi/blitbuffer", { COLOR_WHITE = "white" })
        ZenSpec.replace("device", {
            screen = {
                getWidth = function() return 600 end,
                getHeight = function() return 800 end,
            },
        })
        ZenSpec.replace("ui/geometry", { new = function(_self, values) return values end })
        ZenSpec.replace("ui/widget/menu", Menu)
        ZenSpec.replace("ui/size", { line = { thin = 1 } })
        ZenSpec.replace("ui/uimanager", {
            show = function(_self, widget) shown = widget end,
            close = function() end,
        })
        ZenSpec.replace("common/ui/zen_pager", {
            CHEV_W = 40,
            FOOTER_H = 32,
            PN_FOOTER_H = 40,
            setPlugin = function() end,
            getFooterGeometry = function() return 24, 552 end,
            getStyle = function() return "page_number" end,
            getCenteredFooterY = function(content_bottom, footer_y)
                centered_content_bottom = content_bottom
                return footer_y
            end,
            getHoldSkip = function() return "10" end,
            paint = function() end,
        })
        ZenSpec.replace("common/ui/zen_dialog", function(options)
            options.onShowKeyboard = function() end
            return options
        end)
        ZenSpec.unload("common/ui/zen_scroll_bar")
        require("common/ui/zen_scroll_bar")()
    end)

    after_each(function()
        ZenSpec.unload("common/ui/zen_scroll_bar")
        for _i, name in ipairs(module_names) do
            package.loaded[name] = saved_modules[name] or nil
        end
    end)

    it("does not open the go-to-page dialog from Zen settings", function()
        local settings = new_menu("zen_settings")
        local center_tap = find_zone(settings, "zen_pn_center_tap")

        assert.is_nil(settings.page_info_text.tap_input)
        assert.is_nil(settings.page_info_text.hold_input)
        assert.is_true(center_tap.handler())
        assert.is_nil(shown)
    end)

    it("keeps the go-to-page dialog in other paginated menus", function()
        local filemanager = new_menu("filemanager")
        local center_tap = find_zone(filemanager, "zen_pn_center_tap")

        assert.is_true(center_tap.handler())
        assert.are.equal("Go to page", shown.title)
    end)

    it("uses list geometry after switching from mosaic mode", function()
        local filemanager = new_menu("filemanager")
        filemanager.display_mode_type = "list"
        filemanager.perpage = 10
        filemanager.files_per_page = 10
        filemanager.item_dimen = { h = 50 }
        filemanager.item_height = 50
        -- These fields are retained from the prior mosaic layout.
        filemanager.nb_rows = 3
        filemanager.item_margin = 10

        filemanager.page_info.paintTo(nil, nil, 0, 760)

        assert.are.equal(511, centered_content_bottom)
    end)
end)
