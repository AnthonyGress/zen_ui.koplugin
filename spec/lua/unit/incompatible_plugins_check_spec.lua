local lfs = require("libs/libkoreader-lfs")

describe("incompatible plugin and patch check", function()
    local original_modules
    local original_plugin
    local original_settings
    local original_ptutil
    local original_sui_core
    local original_quickmenu
    local original_suntime
    local UIManager
    local settings
    local patch_dir

    local patch_files = {
        "2-quick-settings.lua",
        "2-automatic-book-series.lua",
        "2-ui-font.lua",
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
        original_suntime = package.loaded["suntime"]
        package.loaded["ptutil"] = nil
        package.loaded["sui_core"] = nil
        package.loaded["quickmenu"] = nil
        package.loaded["suntime"] = nil
        _G.__ZEN_UI_PLUGIN = nil
        patch_dir = os.tmpname()
        os.remove(patch_dir)
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
            end,
            saveSetting = function(self, key, value)
                self.saves = self.saves + 1
                self.saved_key = key
                self.disabled = value
            end,
            flush = function(self) self.flushes = self.flushes + 1 end,
        }
        _G.G_reader_settings = settings
        ZenSpec.replace("common/zen_logger", {
            new = function()
                return { info = function() end, warn = function() end }
            end,
        })
        ZenSpec.replace("datastorage", {
            getPatchesDir = function() return patch_dir end,
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
        package.loaded["suntime"] = original_suntime
        _G.__ZEN_UI_PLUGIN = original_plugin
        _G.G_reader_settings = original_settings
        for _i, filename in ipairs(patch_files) do
            os.remove(patch_dir .. "/" .. filename)
            os.remove(patch_dir .. "/" .. filename .. ".disabled")
        end
        lfs.rmdir(patch_dir)
        ZenSpec.unload("modules/filebrowser/patches/incompatible_plugins_check")
    end)

    it("disables executed incompatible user patches and requests a restart", function()
        ZenSpec.replace("userpatch", {
            execution_status = {
                ["2-quick-settings.lua"] = true,
                ["2-automatic-book-series.lua"] = false,
                ["2-ui-font.lua"] = true,
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

        UIManager.scheduled[1].callback()
        assert.are.equal(
            "Incompatible plugins and patches have been disabled:\n"
                .. "2-quick-settings.lua\n2-automatic-book-series.lua\n2-ui-font.lua",
            UIManager.shown[1].text)
    end)

    it("ignores incompatible user patches that did not execute", function()
        ZenSpec.replace("userpatch", { execution_status = {} })

        assert.is_false(require("modules/filebrowser/patches/incompatible_plugins_check")())
        assert.are.equal("file", lfs.attributes(patch_dir .. "/2-quick-settings.lua", "mode"))
        assert.are.equal(0, settings.flushes)
        assert.are.same({}, UIManager.scheduled)
    end)
end)
