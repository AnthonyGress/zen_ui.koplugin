describe("config manager folder-path migration", function()
    local Manager
    local settings_file
    local stores

    before_each(function()
        settings_file = { data = {}, flush = function() end }
        stores = {
            home = { settings = {}, presets = {} },
            reader = { settings = {}, presets = {} },
        }
        ZenSpec.replace("luasettings", { open = function() return settings_file end })
        ZenSpec.replace("util", {
            tableDeepCopy = function(value) return value end,
        })
        ZenSpec.replace("config/preset_store", {
            rootDir = function() return "/tmp/zen-ui-spec" end,
            getSettings = function() return {} end,
            saveSettings = function() return true end,
            loadStore = function(kind) return stores[kind] or { settings = {}, presets = {} } end,
            saveStore = function(kind, store)
                stores[kind] = store
                return true
            end,
            migrateStores = function() return false end,
        })
        ZenSpec.replace("modules/filebrowser/patches/home/home_presets", {
            applyMosaicTitlesToStrips = function() end,
            defaultHomePage = function() return { quotes = { font_size = 12 } } end,
        })
        ZenSpec.replace("modules/filebrowser/patches/home/home_quotes", {
            ensureFile = function() return false end,
        })
        ZenSpec.unload("config/manager")
        Manager = require("config/manager")
        _G.G_reader_settings = ZenSpec.memorySettings()
    end)

    it("moves sort and display overrides for a renamed folder subtree", function()
        Manager.save({
            folder_sort = {
                ["/library/old"] = { collate = "title", reverse = true },
                ["/library/old/nested"] = { collate = "access", reverse = false },
            },
            folder_display_mode = {
                ["/library/old"] = "mosaic",
                ["/unrelated"] = "list",
            },
        })
        assert.is_true(Manager.moveFolderPathSettings("/library/old/", "/library/new"))
        local config = Manager.get()
        assert.is_nil(config.folder_sort["/library/old"])
        assert.are.same({ collate = "title", reverse = true }, config.folder_sort["/library/new"])
        assert.are.same({ collate = "access", reverse = false }, config.folder_sort["/library/new/nested"])
        assert.are.equal("mosaic", config.folder_display_mode["/library/new"])
        assert.are.equal("list", config.folder_display_mode["/unrelated"])
    end)

    it("does not rewrite identical normalized paths", function()
        Manager.save({ folder_sort = { ["/library/same"] = { collate = "title" } } })
        assert.is_false(Manager.moveFolderPathSettings("/library/same/", "/library/same"))
    end)

    it("migrates missing and legacy quote font sizes to 12", function()
        stores.home = {
            settings = {
                font_size = 18,
                quotes = { day_seed = 123, font_size = 18, manual_index = 4 },
            },
            presets = {
                missing = { quotes = {} },
                explicit = { quotes = { font_size = 18, font_size_override = true } },
            },
        }

        Manager.load()

        assert.are.equal(12, stores.home.settings.quotes.font_size)
        assert.are.equal("daily", stores.home.settings.quotes.rotation)
        assert.are.same({ default = true }, stores.home.settings.quotes.sources)
        assert.is_nil(stores.home.settings.quotes.day_seed)
        assert.is_nil(stores.home.settings.quotes.manual_index)
        assert.are.equal(12, stores.home.presets.missing.quotes.font_size)
        assert.are.equal(18, stores.home.presets.explicit.quotes.font_size)
    end)

    it("removes obsolete folder-cover lifecycle settings", function()
        settings_file.data = {
            features = { browser_folder_cover = true },
            browser_folder_cover = { crop_to_fit = false, cover_mode = "stack" },
            _meta = { gallery_mode_defaulted = true },
        }

        local config = Manager.load()

        assert.is_nil(config.features.browser_folder_cover)
        assert.is_nil(config.browser_folder_cover.crop_to_fit)
        assert.are.equal("stack", config.browser_folder_cover.cover_mode)
        assert.is_nil(config._meta.gallery_mode_defaulted)
    end)

    it("moves global search and page-browser layout into their Zen settings", function()
        settings_file.data = {
            reader_page_browser = { layout = "single" },
        }
        _G.G_reader_settings = ZenSpec.memorySettings({
            substring_search = false,
            zen_page_browser_layout = "grid",
        })

        local config = Manager.load()

        assert.is_false(config.search.substring)
        assert.is_nil(config.reader_page_browser)
        assert.are.equal("single", stores.reader.settings.page_browser_layout)
        assert.is_nil(G_reader_settings:readSetting("substring_search"))
        assert.is_nil(G_reader_settings:readSetting("zen_page_browser_layout"))
    end)
end)
