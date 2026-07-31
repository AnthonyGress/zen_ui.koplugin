describe("file manager status bar visibility", function()
    local FileManager
    local UIManager
    local original_modules
    local original_plugin

    local function replace(name, module)
        original_modules[name] = { value = package.loaded[name] }
        ZenSpec.replace(name, module)
    end

    before_each(function()
        FileManager = {}
        UIManager = { _window_stack = {} }
        original_modules = {}
        original_plugin = rawget(_G, "__ZEN_UI_PLUGIN")

        replace("ui/bidi", {})
        replace("device", {
            screen = {
                getWidth = function() return 600 end,
                getHeight = function() return 800 end,
                scaleBySize = function(_, value) return value end,
            },
        })
        replace("apps/filemanager/filemanager", FileManager)
        replace("ui/font", {})
        replace("ui/geometry", {})
        replace("ui/widget/horizontalgroup", {})
        replace("ui/widget/horizontalspan", {})
        replace("ui/widget/container/leftcontainer", {})
        replace("ui/network/manager", {})
        replace("ui/widget/overlapgroup", {})
        replace("ui/widget/container/rightcontainer", {})
        replace("ui/widget/textwidget", {
            extend = function() return {} end,
        })
        replace("ui/uimanager", UIManager)
        replace("ffi/blitbuffer", {
            ColorRGB32 = function() return 0 end,
            COLOR_DARK_GRAY = 0,
        })
        replace("ui/widget/linewidget", {})
        replace("ui/size", {})
        replace("ui/widget/verticalgroup", {})
        replace("common/clock_timer", {})
        replace("modules/filebrowser/patches/library_font", {})
        replace("common/utils", { deepcopy = function(value) return value end })
        replace("common/paths", {})
        replace("common/shared_state", {
            register = function() end,
            registerLoader = function() end,
        })
        replace("common/status_bar_registry", {})
        replace("common/ui/background", {})
        replace("common/bluetooth", {})
        replace("common/inline_icon_map", {})
        replace("ui/rendertext", {})
        replace("gettext", setmetatable({
            pgettext = function(_, text) return text end,
        }, {
            __call = function(_, text) return text end,
        }))
        replace("common/zen_logger", {
            new = function()
                return { dbg = function() end, info = function() end, warn = function() end }
            end,
        })
        replace("ui/widget/menu", {})
        replace("ui/widget/touchmenu", {})
        original_modules["modules/filebrowser/patches/status_bar"] = {
            value = package.loaded["modules/filebrowser/patches/status_bar"],
        }
        ZenSpec.unload("modules/filebrowser/patches/status_bar")
        _G.__ZEN_UI_PLUGIN = {
            config = {
                features = { status_bar = true },
                status_bar = {},
            },
        }
    end)

    after_each(function()
        for name, saved in pairs(original_modules) do
            package.loaded[name] = saved.value
        end
        _G.__ZEN_UI_PLUGIN = original_plugin
    end)

    it("does not repaint behind a Home page that hides its status bar", function()
        require("modules/filebrowser/patches/status_bar")()
        UIManager._window_stack[1] = { widget = { _zen_home_show_status_bar = false } }

        local existing_row = {}
        local title_group = { {}, existing_row }
        FileManager:_updateStatusBar({ title_bar = { title_group = title_group } })

        assert.are.equal(existing_row, title_group[2])
    end)
end)
