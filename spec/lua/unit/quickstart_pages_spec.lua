describe("Quickstart pages", function()
    local original_modules
    local original_settings
    local reader_apply_result

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
        "modules/settings/zen_settings_apply",
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
        ZenSpec.replace("common/plugin_root", "/plugins/zenos.koplugin")
        reader_apply_result = nil
        ZenSpec.replace("common/reader_defaults", {
            apply = function() return reader_apply_result end,
        })
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
        ZenSpec.replace("modules/settings/zen_settings_apply", {
            apply_feature_toggle = function() end,
        })
        ZenSpec.unload("common/quickstart/quickstart_pages")
        _G.G_reader_settings = ZenSpec.memorySettings()
    end)

    after_each(function()
        for _i, name in ipairs(module_names) do
            package.loaded[name] = original_modules[name]
        end
        _G.G_reader_settings = original_settings
    end)

    local function install_page(title, completed, pending)
        local config = {
            _meta = {
                quickstart_completed = completed,
                reader_defaults_apply_on_next_open = pending == true,
            },
            features = {},
            navbar = { show_tabs = {} },
        }
        local pages = require("common/quickstart/quickstart_pages").build_install_pages({
            config = config,
            plugin = {},
        })
        for _i, page in ipairs(pages) do
            if page.title == title then return page, config end
        end
    end

    local function reader_page(completed, pending)
        return install_page("Reader", completed, pending)
    end

    local function reader_choices(completed)
        return reader_page(completed).choices
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

    it("selects the book cover sleep screen before setup has been completed", function()
        local choices = install_page("Sleep Screen", false).choices

        assert.is_false(choices[1].checked)
        assert.is_true(choices[2].checked)
    end)

    it("keeps existing sleep screen settings when a completed setup is rerun", function()
        local choices = install_page("Sleep Screen", true).choices

        assert.is_true(choices[1].checked)
        assert.is_false(choices[2].checked)
    end)

    it("applies Zen Reader defaults to the next book when no reader is active", function()
        reader_apply_result = false
        local page, config = reader_page(false)

        page.on_apply({ zen = true })

        assert.is_true(config._meta.reader_defaults_apply_on_next_open)
    end)

    it("does not defer Zen Reader defaults after applying them to an active book", function()
        reader_apply_result = true
        local page, config = reader_page(true, true)

        page.on_apply({ zen = true })

        assert.is_false(config._meta.reader_defaults_apply_on_next_open)
    end)

    it("cancels a deferred application when existing Reader settings are kept", function()
        local page, config = reader_page(true, true)

        page.on_apply({ keep = true })

        assert.is_false(config._meta.reader_defaults_apply_on_next_open)
    end)

    it("still offers Home Folder setup when only the device fallback exists", function()
        local found = false
        for _i, page in ipairs(install_pages()) do
            if page.title == "Home Folder" then found = true end
        end

        assert.is_true(found)
    end)
end)
