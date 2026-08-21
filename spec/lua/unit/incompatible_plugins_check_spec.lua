local lfs = require("libs/libkoreader-lfs")

describe("incompatible plugin and patch check", function()
    local original_modules
    local original_plugin
    local original_settings
    local original_ptutil
    local original_sui_core
    local original_quickmenu
    local original_readermenuredesign_installer
    local original_suntime
    local original_appearance_setting
    local UIManager
    local settings
    local logs
    local data_dir
    local patch_dir

    local patch_files = {
        "2-quick-settings.lua",
        "2-automatic-book-series.lua",
        "2-ui-font.lua",
        "2-custom-navbar.lua",
    }

    local module_names = {
        "common/zen_logger",
        "userpatch",
        "datastorage",
        "ui/uimanager",
        "gettext",
        "ui/widget/confirmbox",
        "ui/event",
    }

    before_each(function()
        original_modules = {}
        for _i, name in ipairs(module_names) do
            original_modules[name] = package.loaded[name]
        end
        original_plugin = rawget(_G, "__ZEN_UI_PLUGIN")
        original_settings = _G.G_reader_settings
        original_ptutil = package.loaded["ptutil"]
        original_sui_core = package.loaded["sui_core"]
        original_quickmenu = package.loaded["quickmenu"]
        original_readermenuredesign_installer = package.loaded["readermenuredesign_installer"]
        original_suntime = package.loaded["suntime"]
        original_appearance_setting = package.loaded["lib/setting"]
        package.loaded["ptutil"] = nil
        package.loaded["sui_core"] = nil
        package.loaded["quickmenu"] = nil
        package.loaded["readermenuredesign_installer"] = nil
        package.loaded["suntime"] = nil
        package.loaded["lib/setting"] = nil
        _G.__ZEN_UI_PLUGIN = nil
        data_dir = os.tmpname()
        os.remove(data_dir)
        assert.is_true(lfs.mkdir(data_dir))
        patch_dir = data_dir .. "/patches"
        assert.is_true(lfs.mkdir(patch_dir))
        for _i, filename in ipairs(patch_files) do
            local file = assert(io.open(patch_dir .. "/" .. filename, "w"))
            file:close()
        end
        settings = {
            disabled = {},
            saves = 0,
            flushes = 0,
            readSetting = function(self, key)
                if key == "plugins_disabled" then return self.disabled end
                if key == "extra_plugin_paths" then return self.extra_plugin_paths end
            end,
            saveSetting = function(self, key, value)
                self.saves = self.saves + 1
                self.saved_key = key
                self.disabled = value
            end,
            flush = function(self) self.flushes = self.flushes + 1 end,
        }
        _G.G_reader_settings = settings
        logs = { dbg = {}, info = {}, warn = {} }
        ZenSpec.replace("common/zen_logger", {
            new = function()
                local logger = {}
                for _i, level in ipairs({ "dbg", "info", "warn" }) do
                    logger[level] = function(...)
                        logs[level][#logs[level] + 1] = { ... }
                    end
                end
                return logger
            end,
        })
        ZenSpec.replace("datastorage", {
            getDataDir = function() return data_dir end,
        })
        ZenSpec.replace("gettext", function(text) return text end)
        ZenSpec.replace("ui/widget/confirmbox", {
            new = function(_, spec) return spec end,
        })
        ZenSpec.replace("ui/event", { new = function(_, name) return { name = name } end })
        UIManager = {
            scheduled = {},
            shown = {},
            scheduleIn = function(self, delay, callback)
                self.scheduled[#self.scheduled + 1] = { delay = delay, callback = callback }
            end,
            show = function(self, widget) self.shown[#self.shown + 1] = widget end,
            broadcastEvent = function() end,
        }
        ZenSpec.replace("ui/uimanager", UIManager)
        ZenSpec.unload("modules/filebrowser/patches/incompatible_plugins_check")
    end)

    after_each(function()
        for _i, name in ipairs(module_names) do
            package.loaded[name] = original_modules[name]
        end
        package.loaded["ptutil"] = original_ptutil
        package.loaded["sui_core"] = original_sui_core
        package.loaded["quickmenu"] = original_quickmenu
        package.loaded["readermenuredesign_installer"] = original_readermenuredesign_installer
        package.loaded["suntime"] = original_suntime
        package.loaded["lib/setting"] = original_appearance_setting
        _G.__ZEN_UI_PLUGIN = original_plugin
        _G.G_reader_settings = original_settings
        for _i, filename in ipairs(patch_files) do
            os.remove(patch_dir .. "/" .. filename)
            os.remove(patch_dir .. "/" .. filename .. ".disabled")
        end
        lfs.rmdir(patch_dir)
        lfs.rmdir(data_dir)
        ZenSpec.unload("modules/filebrowser/patches/incompatible_plugins_check")
    end)

    it("disables executed incompatible user patches and requests a restart", function()
        ZenSpec.replace("userpatch", {
            execution_status = {
                ["2-quick-settings.lua"] = true,
                ["2-automatic-book-series.lua"] = false,
                ["2-ui-font.lua"] = true,
                ["2-custom-navbar.lua"] = true,
            },
        })

        assert.is_true(require("modules/filebrowser/patches/incompatible_plugins_check")())
        for _i, filename in ipairs(patch_files) do
            assert.is_nil(lfs.attributes(patch_dir .. "/" .. filename, "mode"))
            assert.are.equal("file", lfs.attributes(patch_dir .. "/" .. filename .. ".disabled", "mode"))
        end
        assert.are.equal("plugins_disabled", settings.saved_key)
        assert.are.equal(1, settings.flushes)
        assert.are.equal(1, #UIManager.scheduled)
        assert.are.equal(0, #logs.info)
        assert.are.equal(1, #logs.warn)
        assert.are.equal("Incompatible plugins or patches detected", logs.warn[1][1])

        UIManager.scheduled[1].callback()
        assert.are.equal(
            "Incompatible plugins and patches have been disabled:\n"
                .. "2-quick-settings.lua\n2-automatic-book-series.lua\n2-ui-font.lua\n2-custom-navbar.lua",
            UIManager.shown[1].text)
    end)

    it("ignores incompatible user patches that did not execute", function()
        ZenSpec.replace("userpatch", { execution_status = {} })

        assert.is_false(require("modules/filebrowser/patches/incompatible_plugins_check")())
        assert.are.equal("file", lfs.attributes(patch_dir .. "/2-quick-settings.lua", "mode"))
        assert.are.equal(0, settings.flushes)
        assert.are.same({}, UIManager.scheduled)
        assert.are.equal(1, #logs.info)
        assert.are.equal(0, #logs.warn)
        assert.are.equal("No incompatible plugins or patches detected", logs.info[1][1])
    end)

    it("disables Appearance when its settings module is loaded", function()
        local root = assert(os.getenv("ZEN_UI_ROOT"))
        package.loaded["lib/setting"] = assert(loadfile(
            root .. "/spec/lua/fixtures/appearance.koplugin/lib/setting.lua"))()
        ZenSpec.replace("userpatch", { execution_status = {} })

        assert.is_true(require("modules/filebrowser/patches/incompatible_plugins_check")())
        assert.is_true(settings.disabled.appearance)
        assert.are.equal(1, settings.flushes)

        UIManager.scheduled[1].callback()
        assert.are.equal(
            "Incompatible plugins and patches have been disabled:\nAppearance",
            UIManager.shown[1].text)
    end)

    it("records installed incompatible plugins before their main modules load", function()
        local plugins_dir = data_dir .. "/plugins"
        local simpleui_dir = plugins_dir .. "/simpleui.koplugin"
        local reader_menu_dir = plugins_dir .. "/zzz-readermenuredesign.koplugin"
        assert.is_true(lfs.mkdir(plugins_dir))
        assert.is_true(lfs.mkdir(simpleui_dir))
        assert.is_true(lfs.mkdir(reader_menu_dir))
        settings.extra_plugin_paths = { plugins_dir }
        ZenSpec.replace("userpatch", { execution_status = {} })

        assert.is_true(require("modules/filebrowser/patches/incompatible_plugins_check")())
        assert.is_true(settings.disabled.simpleui)
        assert.is_true(settings.disabled["zzz-readermenuredesign"])
        assert.are.equal(1, settings.flushes)

        UIManager.scheduled[1].callback()
        assert.are.equal(
            "Incompatible plugins and patches have been disabled:\n"
                .. "Simple UI\nReader Menu Redesign",
            UIManager.shown[1].text)

        lfs.rmdir(simpleui_dir)
        lfs.rmdir(reader_menu_dir)
        lfs.rmdir(plugins_dir)
    end)

    it("does not restart for an installed plugin that is already disabled", function()
        local plugins_dir = data_dir .. "/plugins"
        local reader_menu_dir = plugins_dir .. "/zzz-readermenuredesign.koplugin"
        assert.is_true(lfs.mkdir(plugins_dir))
        assert.is_true(lfs.mkdir(reader_menu_dir))
        settings.extra_plugin_paths = plugins_dir
        settings.disabled["zzz-readermenuredesign"] = true
        ZenSpec.replace("userpatch", { execution_status = {} })

        assert.is_false(require("modules/filebrowser/patches/incompatible_plugins_check")())
        assert.are.equal(0, settings.flushes)
        assert.are.same({}, UIManager.scheduled)

        lfs.rmdir(reader_menu_dir)
        lfs.rmdir(plugins_dir)
    end)

    it("does not mistake another plugin's settings module for Appearance", function()
        package.loaded["lib/setting"] = { get = function() end }
        ZenSpec.replace("userpatch", { execution_status = {} })

        assert.is_false(require("modules/filebrowser/patches/incompatible_plugins_check")())
        assert.is_nil(settings.disabled.appearance)
        assert.are.equal(0, settings.flushes)
    end)

    it("disables auto warmth for light/dark frontlight values", function()
        package.loaded["suntime"] = { loaded = true }
        _G.__ZEN_UI_PLUGIN = {
            config = {
                features = {},
                brightness_schedule = { use_mode_values = true },
            },
        }
        ZenSpec.replace("userpatch", { execution_status = {} })

        assert.is_true(require("modules/filebrowser/patches/incompatible_plugins_check")())
        assert.is_true(settings.disabled.autowarmth)
        assert.are.equal(1, settings.flushes)
    end)
end)
