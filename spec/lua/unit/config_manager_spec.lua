describe("config manager folder-path migration", function()
    local Manager
    local settings_file

    before_each(function()
        settings_file = { data = {}, flush = function() end }
        ZenSpec.replace("luasettings", { open = function() return settings_file end })
        ZenSpec.replace("config/preset_store", {
            rootDir = function() return "/tmp/zen-ui-spec" end,
            getSettings = function() return {} end,
            saveSettings = function() return true end,
        })
        ZenSpec.replace("modules/filebrowser/patches/home/home_presets", {
            applyMosaicTitlesToStrips = function() end,
        })
        ZenSpec.replace("modules/filebrowser/patches/home/home_quotes", {})
        ZenSpec.unload("config/manager")
        Manager = require("config/manager")
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
end)
