describe("Quickstart pages", function()
    local original_modules
    local original_settings

    local module_names = {
        "bookinfomanager",
        "common/cover_utils",
        "common/paths",
        "common/plugin_root",
        "common/quickstart/quickstart_pages",
        "common/reader_defaults",
        "common/zen_logger",
        "config/manager",
        "config/preset_store",
        "config/screensaver_presets",
        "device",
        "gettext",
    }

    before_each(function()
        original_modules = {}
        for _i, name in ipairs(module_names) do
            original_modules[name] = package.loaded[name]
        end
        original_settings = G_reader_settings

        ZenSpec.replace("bookinfomanager", {})
        ZenSpec.replace("common/cover_utils", {})
        ZenSpec.replace("common/paths", {
            getHomeDir = function() return "/books" end,
            getConfiguredHomeDir = function()
                return G_reader_settings:readSetting("home_dir")
            end,
        })
        ZenSpec.replace("common/plugin_root", "/plugins/zen_ui.koplugin")
        ZenSpec.replace("common/reader_defaults", { apply = function() end })
        ZenSpec.replace("common/zen_logger", {
            new = function() return { warn = function() end } end,
        })
        ZenSpec.replace("config/manager", { save = function() end })
        ZenSpec.replace("config/preset_store", {})
        ZenSpec.replace("config/screensaver_presets", {
            get = function() return {} end,
        })
        ZenSpec.replace("device", {})
        ZenSpec.replace("gettext", function(text) return text end)
        ZenSpec.unload("common/quickstart/quickstart_pages")
        _G.G_reader_settings = ZenSpec.memorySettings()
    end)

    after_each(function()
        for _i, name in ipairs(module_names) do
            package.loaded[name] = original_modules[name]
        end
        _G.G_reader_settings = original_settings
    end)

    local function reader_choices(completed)
        local pages = require("common/quickstart/quickstart_pages").build_install_pages({
            config = {
                _meta = { quickstart_completed = completed },
                features = {},
                navbar = { show_tabs = {} },
            },
            plugin = {},
        })
        for _i, page in ipairs(pages) do
            if page.title == "Reader" then return page.choices end
        end
    end

    local function install_pages()
        return require("common/quickstart/quickstart_pages").build_install_pages({
            config = {
                _meta = { quickstart_completed = false },
                features = {},
                navbar = { show_tabs = {} },
            },
            plugin = {},
        })
    end

    it("selects Zen Reader defaults before setup has been completed", function()
        local choices = reader_choices(false)

        assert.is_false(choices[1].checked)
        assert.is_true(choices[2].checked)
    end)

    it("keeps existing Reader settings when a completed setup is rerun", function()
        local choices = reader_choices(true)

        assert.is_true(choices[1].checked)
        assert.is_false(choices[2].checked)
    end)

    it("still offers Home Folder setup when only the device fallback exists", function()
        local found = false
        for _i, page in ipairs(install_pages()) do
            if page.title == "Home Folder" then found = true end
        end

        assert.is_true(found)
    end)
end)
