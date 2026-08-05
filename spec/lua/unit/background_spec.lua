describe("library background cleanup", function()
    local original_plugin

    before_each(function()
        original_plugin = rawget(_G, "__ZEN_UI_PLUGIN")
        ZenSpec.replace("device", { screen = {} })
        ZenSpec.replace("ffi/blitbuffer", { COLOR_WHITE = "white" })
        ZenSpec.replace("common/zen_logger", {
            new = function()
                return { warn = function() end }
            end,
        })
        ZenSpec.replace("gettext", function(text) return text end)
        ZenSpec.replace("ui/widget/imagewidget", {})
        ZenSpec.replace("libs/libkoreader-lfs", {})
        ZenSpec.unload("common/ui/background")
    end)

    after_each(function()
        _G.__ZEN_UI_PLUGIN = original_plugin
        ZenSpec.unload("common/ui/background")
    end)

    it("keeps explicitly opaque widget backgrounds", function()
        local Background = require("common/ui/background")
        local protected = { background = "white", _zen_keep_background = true }
        local ordinary = { background = "white" }

        Background.clearWhiteBackgrounds({ protected, ordinary })

        assert.are.equal("white", protected.background)
        assert.is_nil(ordinary.background)

        Background.restoreWhiteBackgrounds({ protected, ordinary })

        assert.are.equal("white", protected.background)
        assert.are.equal("white", ordinary.background)
    end)

    it("does not compare opaque cdata backgrounds with nil while restoring", function()
        local ffi = require("ffi")
        local Color = ffi.metatype(ffi.typeof("struct { int value; }"), {
            __eq = function(_color, other) return other.value == 255 end,
        })
        local opaque = { background = Color(255) }
        local transparent = {
            _zen_library_bg_restore = "white",
        }

        local Background = require("common/ui/background")
        Background.restoreWhiteBackgrounds({ opaque, transparent })

        assert.are.equal(255, opaque.background.value)
        assert.are.equal("white", transparent.background)
    end)

    it("restores existing transparent tiles when the configured image disappears", function()
        local exists = true
        local path = "/library/background.jpg"
        local config = {
            library_background = { enabled = true, path = path },
        }
        local plugin = {
            config = config,
            saveConfig = function() end,
        }
        _G.__ZEN_UI_PLUGIN = plugin
        ZenSpec.replace("libs/libkoreader-lfs", {
            attributes = function() return exists and "file" or nil end,
        })
        ZenSpec.replace("ui/widget/notification", {
            new = function(_self, opts) return opts end,
        })
        ZenSpec.replace("ui/uimanager", {
            nextTick = function() end,
            show = function() end,
        })
        ZenSpec.unload("common/ui/background")

        local Background = require("common/ui/background")
        local tile = {
            background = nil,
            _zen_library_bg_restore = "white",
        }
        local root = { background = "white", tile }
        local menu = {
            dimen = { w = 100, h = 100 },
            root,
        }
        Background.applyToMenu(menu)

        menu:paintTo({}, 0, 0)
        assert.is_nil(root.background)
        assert.is_nil(tile.background)

        exists = false
        menu:paintTo({}, 0, 0)

        assert.is_false(config.library_background.enabled)
        assert.are.equal("white", root.background)
        assert.are.equal("white", tile.background)
    end)

    it("disables a configured background and notifies when its image is missing", function()
        local saved = 0
        local shown
        local pending_notice
        local path = "/library/removed.jpg"
        local config = {
            library_background = { enabled = true, path = path },
        }
        local plugin = {
            config = config,
            saveConfig = function() saved = saved + 1 end,
        }
        _G.__ZEN_UI_PLUGIN = plugin
        ZenSpec.replace("libs/libkoreader-lfs", {
            attributes = function(checked_path, attribute)
                assert.are.equal(path, checked_path)
                assert.are.equal("mode", attribute)
                return nil
            end,
        })
        ZenSpec.replace("ui/widget/notification", {
            new = function(_self, opts) return opts end,
        })
        ZenSpec.replace("ui/uimanager", {
            nextTick = function(_self, callback) pending_notice = callback end,
            show = function(_self, widget) shown = widget end,
        })
        ZenSpec.unload("common/ui/background")

        local Background = require("common/ui/background")
        assert.are.equal("", Background.library_path(plugin))

        assert.is_false(config.library_background.enabled)
        assert.are.equal(path, config.library_background.path)
        assert.are.equal(1, saved)
        assert.is_function(pending_notice)
        assert.is_nil(shown)

        pending_notice()
        assert.are.equal(
            "Library background was disabled because the image file was not found.",
            shown.text
        )
        assert.are.equal("", Background.library_path(plugin))
        assert.are.equal(1, saved)
    end)
end)
