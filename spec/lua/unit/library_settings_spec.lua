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
        "ui/widget/confirmbox",
        "ui/widget/infomessage",
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

    it("rebuilds Home when the folder cover mode changes", function()
        local scheduled
        local saves = 0
        local refreshes = 0
        local rebuilds = 0
        package.loaded["ui/uimanager"].scheduleIn = function(_self, delay, callback)
            scheduled = { delay = delay, callback = callback }
        end
        package.loaded["common/shared_state"].get = function()
            return { rebuildActive = function() rebuilds = rebuilds + 1 end }
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
            browser_folder_cover = { cover_mode = "gallery" },
            features = {},
        }
        local plugin = { saveConfig = function() saves = saves + 1 end }
        local items = require("modules/settings/sections/library_settings").build({
            config = config,
            plugin = plugin,
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

        find_item(items, "First cover image").callback()

        assert.are.equal("normal", config.browser_folder_cover.cover_mode)
        assert.are.equal(1, saves)
        assert.are.equal(1, refreshes)
        assert.are.equal(0, rebuilds)
        assert.are.equal(0.25, scheduled.delay)

        scheduled.callback()
        assert.are.equal(1, rebuilds)
    end)

    it("rebuilds Home when spine lines or rounded corners change", function()
        local scheduled
        local saves = 0
        local refreshes = 0
        local rebuilds = 0
        package.loaded["ui/uimanager"].scheduleIn = function(_self, delay, callback)
            scheduled = { delay = delay, callback = callback }
        end
        package.loaded["common/shared_state"].get = function()
            return { rebuildActive = function() rebuilds = rebuilds + 1 end }
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
            browser_folder_cover = { show_spine_lines = false },
            features = { browser_cover_rounded_corners = true },
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

        find_item(items, "Show spine lines").callback()
        assert.are.equal(0.25, scheduled.delay)
        scheduled.callback()

        find_item(items, "Rounded cover corners").callback()
        assert.are.equal(0.25, scheduled.delay)
        scheduled.callback()

        assert.is_true(config.browser_folder_cover.show_spine_lines)
        assert.is_false(config.features.browser_cover_rounded_corners)
        assert.are.equal(2, saves)
        assert.are.equal(2, refreshes)
        assert.are.equal(2, rebuilds)
    end)

    it("resets the Library font to bundled Hyperreadable", function()
        local confirmation
        local saves = 0
        package.loaded["ui/uimanager"].show = function(_self, widget)
            confirmation = widget
        end
        package.loaded["ui/uimanager"].scheduleIn = function() end
        package.loaded["modules/settings/zen_settings_apply"].reinit_filemanager = function() end
        package.loaded["modules/settings/zen_settings_apply"].prompt_restart = function() end
        ZenSpec.replace("ui/widget/confirmbox", {
            new = function(_self, options) return options end,
        })
        ZenSpec.replace("apps/filemanager/filemanager", {})

        local config = {
            browser_hide_up_folder = {},
            features = {},
            library_font = { font_face = "/fonts/Custom-Regular.ttf", font_size = 24 },
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

        find_item(items, "Reset font").callback()
        confirmation.ok_callback()

        assert.are.equal(require("config/defaults").library_font.font_face, config.library_font.font_face)
        assert.are.equal(18, config.library_font.font_size)
        assert.are.equal(1, saves)
    end)

    it("shows the selected Library font path on hold without resetting it", function()
        local message
        local saves = 0
        package.loaded["ui/uimanager"].show = function(_self, widget)
            message = widget
        end
        ZenSpec.replace("ui/widget/infomessage", {
            new = function(_self, options) return options end,
        })

        local font_path = "/fonts/Custom-Regular.ttf"
        local config = {
            browser_hide_up_folder = {},
            features = {},
            library_font = { font_face = font_path, font_size = 24 },
        }
        local items = require("modules/settings/sections/library_settings").build({
            config = config,
            plugin = { saveConfig = function() saves = saves + 1 end },
            save_and_apply = function() end,
        })

        local font_item
        for _i, item in ipairs(items) do
            if type(item.sub_item_table) == "table" then
                for _j, sub_item in ipairs(item.sub_item_table) do
                    if sub_item.text == "Reset font" then
                        for _k, sibling in ipairs(item.sub_item_table) do
                            if sibling.hold_callback then font_item = sibling end
                        end
                        break
                    end
                end
            end
        end
        assert.is_not_nil(font_item)
        font_item.hold_callback()

        assert.are.equal(font_path, message.text)
        assert.is_false(message.show_icon)
        assert.are.equal(font_path, config.library_font.font_face)
        assert.are.equal(0, saves)
    end)
end)
