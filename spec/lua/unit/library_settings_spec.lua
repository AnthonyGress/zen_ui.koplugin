describe("library settings", function()
    local saved_modules

    local dependencies = {
        "gettext",
        "ui/uimanager",
        "common/paths",
        "common/shared_state",
        "common/inline_icon_map",
        "common/ui/icon_menu_item",
        "modules/settings/sections/library_settings/status_bar_settings",
        "modules/settings/zen_settings_apply",
        "modules/settings/zen_settings_utils",
        "apps/filemanager/filemanager",
    }

    before_each(function()
        saved_modules = {}
        for _i, name in ipairs(dependencies) do
            saved_modules[name] = package.loaded[name] or false
        end
        ZenSpec.replace("gettext", function(text) return text end)
        ZenSpec.replace("ui/uimanager", {})
        ZenSpec.replace("common/paths", {})
        ZenSpec.replace("common/shared_state", {})
        ZenSpec.replace("common/inline_icon_map", {})
        ZenSpec.replace("common/ui/icon_menu_item", {
            decorate = function(item) return item end,
        })
        ZenSpec.replace("modules/settings/sections/library_settings/status_bar_settings", {
            build = function() return {} end,
        })
        ZenSpec.replace("modules/settings/zen_settings_apply", {})
        ZenSpec.replace("modules/settings/zen_settings_utils", {
            buildColorSubMenu = function() return {} end,
        })
        ZenSpec.unload("modules/settings/sections/library_settings")
    end)

    after_each(function()
        ZenSpec.unload("modules/settings/sections/library_settings")
        for _i, name in ipairs(dependencies) do
            package.loaded[name] = saved_modules[name] or nil
        end
    end)

    it("invalidates the library cache when series grouping changes", function()
        local invalidations = 0
        local clears = 0
        local refreshes = 0
        local home = {
            invalidateLibraryCache = function()
                invalidations = invalidations + 1
            end,
        }
        package.loaded["common/shared_state"].get = function() return home end
        ZenSpec.replace("apps/filemanager/filemanager", {
            instance = {
                file_chooser = {
                    path = "/library",
                    _zen_clear_item_table_cache = function() clears = clears + 1 end,
                    changeToPath = function() refreshes = refreshes + 1 end,
                },
            },
        })

        local config = {
            browser_hide_up_folder = {},
            features = { automatic_series_grouping = true },
        }
        local items = require("modules/settings/sections/library_settings").build({
            config = config,
            plugin = { saveConfig = function() end },
            save_and_apply = function() end,
        })
        local folders
        for _i, item in ipairs(items) do
            if item.text == "Folders" then
                folders = item
                break
            end
        end

        assert.is_not_nil(folders)
        folders.sub_item_table[2].callback()

        assert.is_false(config.features.automatic_series_grouping)
        assert.are.equal(1, invalidations)
        assert.are.equal(1, clears)
        assert.are.equal(1, refreshes)
    end)

    it("rebuilds the library when mosaic title strips change", function()
        local saves = 0
        local refreshes = 0
        local restart_prompts = 0
        package.loaded["modules/settings/zen_settings_apply"].prompt_restart = function()
            restart_prompts = restart_prompts + 1
        end
        ZenSpec.replace("apps/filemanager/filemanager", {
            instance = {
                file_chooser = {
                    updateItems = function() refreshes = refreshes + 1 end,
                },
            },
        })

        local config = {
            browser_hide_up_folder = {},
            features = {},
            mosaic_title_strip = {},
        }
        local items = require("modules/settings/sections/library_settings").build({
            config = config,
            plugin = { saveConfig = function() saves = saves + 1 end },
            save_and_apply = function() end,
        })

        local function find_item(item_table, text)
            for _i, item in ipairs(item_table) do
                if item.text == text then return item end
                if type(item.sub_item_table) == "table" then
                    local found = find_item(item.sub_item_table, text)
                    if found then return found end
                end
            end
        end

        find_item(items, "Show title below cover (mosaic)").callback()
        find_item(items, "Show author below cover (mosaic)").callback()

        assert.is_true(config.mosaic_title_strip.show_title)
        assert.is_true(config.mosaic_title_strip.show_author)
        assert.are.equal(2, saves)
        assert.are.equal(2, refreshes)
        assert.are.equal(0, restart_prompts)
    end)
end)
