describe("reader themes", function()
    local Themes
    local dirty_calls
    local next_tick_callback

    before_each(function()
        dirty_calls = {}
        next_tick_callback = nil
        _G.G_reader_settings = ZenSpec.memorySettings()
        _G.G_reader_settings.has = function(self, key) return self.data[key] ~= nil end
        ZenSpec.replace("ui/uimanager", {
            setDirty = function(...)
                dirty_calls[#dirty_calls + 1] = { ... }
            end,
            nextTick = function(_, callback) next_tick_callback = callback end,
        })
        ZenSpec.replace("device", {
            screen = {
                night_mode = false,
                toggleNightMode = function(self) self.night_mode = not self.night_mode end,
            },
        })
        ZenSpec.unload("common/reader_themes")
        Themes = require("common/reader_themes")
    end)

    it("appends the selected theme and removes it when disabled", function()
        local plugin = {
            config = {
                features = { reader_themes = true },
                reader_themes = { light_mode = "dark_warm_gray" },
            },
        }

        local css = Themes.appendCss(plugin, "body { margin: 0; }")
        assert.matches("#dcdccc", css, 1, true)
        assert.matches("#1f1f1f", css, 1, true)

        plugin.config.features.reader_themes = false
        assert.are.equal("body { margin: 0; }\n", Themes.appendCss(plugin, css))

        plugin.config.features.reader_themes = true
        plugin.config.reader_themes.light_mode = "default"
        assert.are.equal("body { margin: 0; }\n", Themes.appendCss(plugin, css))
    end)

    it("uses an independent theme for each display mode", function()
        local plugin = {
            config = {
                features = { reader_themes = true },
                reader_themes = {
                    dark_mode = "dark_graphite",
                    light_mode = "default",
                },
            },
        }

        G_reader_settings:saveSetting("night_mode", true)
        assert.matches("#252525", Themes.appendCss(plugin, "base"), 1, true)

        G_reader_settings:saveSetting("night_mode", false)
        assert.are.equal("base", Themes.appendCss(plugin, "base"))
    end)

    it("uses custom theme colors and font face", function()
        local face, background
        local reader = {
            document = {
                setFontFace = function(_, value) face = value end,
                setBackgroundColor = function(_, value) background = value end,
            },
        }
        local plugin = {
            config = {
                features = { reader_themes = true },
                reader_themes = {
                    light_mode = "custom_1",
                    custom = {
                        custom_1 = {
                            name = "Paper",
                            text = "#321",
                            background = "#abc",
                            font_face = "NotoSerif-Regular.ttf",
                        },
                    },
                },
            },
        }

        local css = Themes.appendCss(plugin, "base")
        assert.matches("#332211", css, 1, true)
        assert.matches("#aabbcc", css, 1, true)
        assert.is_true(Themes.applyFont(reader, plugin))
        assert.are.equal("NotoSerif-Regular.ttf", face)
        assert.is_true(Themes.applyBackground(reader, plugin))
        assert.are.equal(0xaabbcc, background)
        assert.is_true(Themes.isValidColor("#123abc"))
        assert.is_true(Themes.isValidColor("#abc"))
        assert.is_false(Themes.isValidColor("#123ab"))
    end)

    it("reapplies the open CRE reader and restores KOReader's background", function()
        local applied_css, backgrounds = 0, {}
        local call_cache_resets, buffer_cache_resets = 0, 0
        local reader = {
            document = {
                setStyleSheet = function() end,
                setBackgroundColor = function(_, color) backgrounds[#backgrounds + 1] = color end,
                resetCallCache = function() call_cache_resets = call_cache_resets + 1 end,
                resetBufferCache = function() buffer_cache_resets = buffer_cache_resets + 1 end,
            },
            typeset = {
                onApplyStyleSheet = function() applied_css = applied_css + 1 end,
            },
        }
        ZenSpec.replace("apps/reader/readerui", { instance = reader })
        local plugin = {
            config = {
                features = { reader_themes = true },
                reader_themes = { light_mode = "light_sepia" },
            },
        }

        assert.is_true(Themes.applyCurrent(plugin))
        assert.are.equal(1, applied_css)
        assert.are.equal(1, call_cache_resets)
        assert.are.equal(1, buffer_cache_resets)
        assert.are.equal(0xf3ead2, backgrounds[1])
        assert.are.equal("full", dirty_calls[1][3])

        plugin.config.features.reader_themes = false
        G_reader_settings:saveSetting("cre_background_color", "#ffffff")
        assert.is_true(Themes.applyCurrent(plugin))
        assert.are.equal("#ffffff", backgrounds[2])
    end)

    it("makes the footer container transparent while colors are enabled", function()
        local footer = {
            footer_content = {},
            footer_text = {},
            _zen_left_text = {},
        }
        local plugin = {
            config = {
                features = { reader_themes = true },
                reader_themes = { light_mode = "dark_warm_gray" },
            },
        }

        assert.is_true(Themes.applyFooterColors(footer, plugin))
        assert.is_true(footer.footer_content.background == false)

        plugin.config.features.reader_themes = false
        Themes.applyFooterColors(footer, plugin)
        assert.is_not_nil(footer.footer_content.background)
    end)

    it("wraps CRE stylesheets only while the feature is enabled", function()
        local received_css, cache_resets = nil, 0
        local CreDocument = {
            setStyleSheet = function(_, _file, css) received_css = css end,
        }
        local ReaderTypeset = {
            onReadSettings = function() return true end,
        }
        local ReaderFooter = {
            updateFooterContainer = function() end,
            updateFooterFont = function() end,
        }
        local DeviceListener = {
            onToggleNightMode = function() end,
        }
        local menu = {
            getSize = function() return { w = 100, h = 50 } end,
            paintTo = function() end,
        }
        local ReaderMenu = {
            onShowMenu = function(self) self.menu_container = { menu } end,
        }
        local plugin = {
            config = {
                features = { reader_themes = true },
                reader_themes = {
                    dark_mode = "dark_graphite",
                    light_mode = "dark_graphite",
                },
            },
        }
        _G.__ZEN_UI_PLUGIN = plugin
        ZenSpec.replace("document/credocument", CreDocument)
        ZenSpec.replace("device/devicelistener", DeviceListener)
        ZenSpec.replace("apps/reader/modules/readertypeset", ReaderTypeset)
        ZenSpec.replace("apps/reader/modules/readerfooter", ReaderFooter)
        ZenSpec.replace("apps/reader/modules/readermenu", ReaderMenu)
        local ReaderUI = {
            onClose = function() end,
        }
        ZenSpec.replace("apps/reader/readerui", ReaderUI)
        ZenSpec.unload("modules/reader/patches/reader_themes")

        assert.is_true(require("modules/reader/patches/reader_themes")())
        CreDocument:setStyleSheet("epub.css", "base")
        assert.matches("#252525", received_css, 1, true)

        ReaderMenu:onShowMenu()
        G_reader_settings:saveSetting("night_mode", true)
        local inversions = 0
        menu:paintTo({
            invertRect = function() inversions = inversions + 1 end,
        }, 0, 0)
        assert.are.equal(1, inversions)
        G_reader_settings:saveSetting("night_mode", false)

        plugin.config.features.reader_themes = false
        CreDocument:setStyleSheet("epub.css", "base")
        assert.are.equal("base", received_css)

        plugin.config.features.reader_themes = true
        DeviceListener.onToggleNightMode({
            ui = {
                document = {
                    provider = "crengine",
                    resetCallCache = function() cache_resets = cache_resets + 1 end,
                },
            },
        })
        assert.is_true(G_reader_settings:isTrue("night_mode"))
        assert.is_false(require("device").screen.night_mode)
        assert.are.equal(1, cache_resets)

        G_reader_settings:saveSetting("night_mode", false)
        local document = {
            setStyleSheet = function() end,
            setBackgroundColor = function() end,
        }
        ReaderUI.instance = {
            document = document,
            typeset = { css = "epub.css" },
            styletweak = { getCssText = function() return "" end },
        }
        require("device").screen:toggleNightMode()
        assert.is_false(require("device").screen.night_mode)
        G_reader_settings:saveSetting("night_mode", true)
        assert.is_function(next_tick_callback)
        next_tick_callback()
    end)
end)
