describe("Home widget content settings", function()
    local arrange_options
    local arrange_history
    local home_page
    local remembered_routes
    local shown

    local function item_text(item)
        return item.text or (item.text_func and item.text_func())
    end

    local function find_item(items, text)
        for _i, item in ipairs(items) do
            if item_text(item) == text then return item end
        end
    end

    local function has_item_prefix(items, prefix)
        for _i, item in ipairs(items) do
            local text = item_text(item)
            if type(text) == "string" and text:sub(1, #prefix) == prefix then
                return true
            end
        end
        return false
    end

    before_each(function()
        arrange_options = nil
        arrange_history = {}
        remembered_routes = {}
        shown = {}
        home_page = {
            strip_memory = {
                active_id = "recent",
                source = { kind = "recent" },
            },
            rows = {
                order = { "featured", "strip" },
                enabled = { featured = true, strip = true },
            },
            modules = {
                featured = {
                    default_source = { kind = "recent" },
                    path = "/books/selected.epub",
                    show_module_title = true,
                },
                quotes = { show_module_title = true },
                reading_goals = { show_module_title = true },
                stats_triplet = { show_module_title = true },
                strip = {
                    show_module_title = true,
                    controls = {
                        enabled = false,
                        labels = {},
                        order = { "recent", "favorites" },
                        show_buttons = { recent = true, favorites = true },
                        custom_buttons = {},
                    },
                    default_source = { kind = "recent" },
                    sources = {
                        custom = { paths = {} },
                        recent = {},
                        tag = {},
                    },
                },
            },
            goals = {},
            quotes = {},
        }

        ZenSpec.replace("gettext", function(text) return text end)
        ZenSpec.replace("ffi/util", {
            template = function(text) return text end,
        })
        ZenSpec.replace("ui/uimanager", {
            scheduleIn = function() end,
            show = function(_self, widget) shown[#shown + 1] = widget end,
        })
        ZenSpec.replace("ui/widget/confirmbox", {
            new = function(_self, opts) return opts end,
        })
        ZenSpec.replace("config/preset_store", {
            getSettings = function() return home_page end,
            saveSettings = function() end,
            isBuiltin = function() return false end,
            list = function()
                return { { name = "My preset" } }
            end,
        })
        ZenSpec.replace("modules/filebrowser/patches/home/home_presets", {
            DEFAULT_PRESET_NAME = "Zen Default",
            CUSTOM_PRESET_NAME = "Custom preset",
            getBuiltinPresets = function()
                return { { name = "Zen Default", builtin = true } }
            end,
            ensurePresetState = function() end,
            normalizeFeaturedConfig = function() end,
            normalizeStripConfig = function() end,
            normalizeLayoutGrid = function() end,
            isBuiltinPresetName = function() return false end,
            defaultHomePage = function()
                return {
                    modules = {
                        strip = {
                            controls = {
                                labels = {},
                                next_custom_id = 0,
                                order = {
                                    "page_left", "recent", "search", "tags", "page_right",
                                },
                                show_buttons = {
                                    page_left = true,
                                    recent = true,
                                    search = true,
                                    tags = true,
                                    page_right = true,
                                },
                                custom_buttons = {},
                            },
                        },
                    },
                }
            end,
        })
        ZenSpec.replace("modules/filebrowser/patches/home/home_quotes", {
            hasCustomQuotes = function() return false end,
        })
        ZenSpec.replace("modules/filebrowser/patches/home/components/registry", {
            CAPACITY_UNITS = 10,
            normalizeRows = function(rows) return rows end,
            list = function()
                return {
                    { id = "featured", label = "Featured book" },
                    { id = "strip", label = "Book strip" },
                }
            end,
            get = function(id) return { id = id, label = id, size = 2 } end,
            totalUnits = function() return 4 end,
            sizeUnits = function() return 2 end,
        })
        ZenSpec.replace("modules/filebrowser/patches/library_font", {
            getFontName = function() return "default" end,
        })
        ZenSpec.replace("common/reading_goals", {
            normalize = function(goals) return goals end,
            settingsItems = function() return {} end,
        })
        ZenSpec.replace("common/inline_icon_map", setmetatable({}, {
            __index = function(_self, key) return key end,
        }))
        ZenSpec.replace("common/ui/icon_menu_item", {
            decorate = function(item) return item end,
        })
        ZenSpec.replace("common/nav_button_model", {
            builtins = function()
                return {
                    { id = "recent", label = "Recent", source = true },
                    { id = "favorites", label = "Favorites", source = true },
                }
            end,
            find = function(_controls, id)
                for _i, entry in ipairs(require("common/nav_button_model").builtins()) do
                    if entry.id == id then return entry end
                end
            end,
            firstVisibleSource = function(controls)
                local model = require("common/nav_button_model")
                for _i, id in ipairs(controls.order or {}) do
                    if controls.show_buttons[id] == true then
                        local entry = model.find(controls, id)
                        if entry and entry.source == true then
                            return { kind = id }, id
                        end
                    end
                end
            end,
            label = function(_controls, entry) return entry.label end,
        })
        ZenSpec.replace("common/dispatcher_menu", {})
        ZenSpec.replace("modules/menu/app_launcher/native_menu", {})
        ZenSpec.replace("modules/menu/app_launcher/plugin_scan", {})
        ZenSpec.replace("common/ui/zen_arrange_list", {
            show = function(opts)
                arrange_options = opts
                arrange_history[#arrange_history + 1] = opts
            end,
        })
        ZenSpec.replace("modules/settings/zen_settings_page", {
            rememberStandaloneArrangeRoute = function(path, opener, arrange_path)
                remembered_routes[#remembered_routes + 1] = {
                    path = path,
                    opener = opener,
                    arrange_path = arrange_path,
                }
                return true
            end,
        })
        ZenSpec.replace("apps/filemanager/filemanager", {})
        ZenSpec.unload("modules/settings/sections/library_settings/home_settings")

        require("modules/settings/sections/library_settings/home_settings").build({
            config = {},
            settings_apply = {},
        })
    end)

    it("shows Featured book settings only for custom content", function()
        local settings = require("modules/settings/sections/library_settings/home_settings")
        local plugin = { config = {} }
        assert.is_true(settings.openWidgetSettings("featured", plugin))
        assert.are.equal(plugin, arrange_options.plugin)

        local items = arrange_options.item_table
        assert.are.equal("Content: Recently read", item_text(items[1]))
        assert.is_nil(find_item(items, "Show widget title"))
        assert.is_false(has_item_prefix(items, "Book: "))
        assert.is_nil(find_item(items, "Clear book"))

        local parent = { updateItems = function() end }
        find_item(items[1].sub_item_table_func(parent), "Custom").callback()

        assert.are.equal("Content: Custom", item_text(parent.item_table[1]))
        assert.is_true(has_item_prefix(parent.item_table, "Book: "))
        assert.is_not_nil(find_item(parent.item_table, "Clear book"))

        find_item(parent.item_table[1].sub_item_table_func(parent), "Recently read").callback()
        assert.is_false(has_item_prefix(parent.item_table, "Book: "))
        assert.is_nil(find_item(parent.item_table, "Clear book"))
    end)

    it("keeps featured description wrapping disabled by default", function()
        local settings = require("modules/settings/sections/library_settings/home_settings")
        assert.is_true(settings.openWidgetSettings("featured"))

        local item = find_item(arrange_options.item_table, "Wrap description text")
        assert.is_table(item)
        assert.is_false(item.checked_func())

        item.callback()
        assert.is_true(home_page.modules.featured.wrap_description_text)
        assert.is_true(item.checked_func())
    end)

    it("keeps the plugin when Widgets is opened from the settings page", function()
        local plugin = { config = {} }
        local section = require("modules/settings/sections/library_settings/home_settings").build({
            plugin = plugin,
            config = {},
            settings_apply = {},
        })

        section.sub_item_table[1].callback({})

        assert.are.equal(plugin, arrange_options.plugin)
    end)

    it("uses radio buttons to mark the active Home preset", function()
        home_page.active_preset = "Zen Default"
        local section = require("modules/settings/sections/library_settings/home_settings").build({
            config = {},
            settings_apply = {},
        })

        local presets = find_item(section.sub_item_table, "Presets").sub_item_table_func()
        local builtin = find_item(presets, "Zen Default")
        local custom = find_item(presets, "My preset")

        assert.is_true(builtin.radio)
        assert.is_true(builtin.checked_func())
        assert.is_true(custom.radio)
        assert.is_false(custom.checked_func())
        assert.is_nil(find_item(presets, "* Zen Default"))
    end)

    it("removes widget-title settings and legacy values", function()
        local settings = require("modules/settings/sections/library_settings/home_settings")
        for _i, id in ipairs({ "featured", "strip", "reading_goals", "stats_triplet", "quotes" }) do
            assert.is_nil(home_page.modules[id].show_module_title)
            assert.is_true(settings.openWidgetSettings(id))
            assert.is_nil(find_item(arrange_options.item_table, "Show widget title"))
        end
    end)

    it("shows Strip filters and custom books only for their content", function()
        local settings = require("modules/settings/sections/library_settings/home_settings")
        assert.is_true(settings.openWidgetSettings("strip"))

        local items = arrange_options.item_table
        assert.are.equal("Content: Recent", item_text(items[1]))
        assert.is_nil(find_item(items, "Show widget title"))
        assert.is_nil(find_item(items, "Order"))
        assert.is_not_nil(find_item(items, "Recent filters"))
        assert.is_nil(find_item(items, "Custom books"))

        local parent = { updateItems = function() end }
        find_item(items[1].sub_item_table_func(parent), "Custom books").callback()

        assert.is_nil(home_page.strip_memory)
        assert.is_nil(find_item(parent.item_table, "Recent filters"))
        assert.is_not_nil(find_item(parent.item_table, "Custom books"))

        find_item(parent.item_table[1].sub_item_table_func(parent), "Favorites").callback()
        assert.is_nil(find_item(parent.item_table, "Recent filters"))
        assert.is_nil(find_item(parent.item_table, "Custom books"))
    end)

    it("uses the first visible source tab instead of a Content option", function()
        local strip = home_page.modules.strip
        strip.controls.enabled = true
        strip.controls.order = { "recent", "favorites" }
        strip.default_source = { kind = "favorites" }

        local settings = require("modules/settings/sections/library_settings/home_settings")
        assert.is_true(settings.openWidgetSettings("strip"))

        local items = arrange_options.item_table
        assert.is_false(has_item_prefix(items, "Content: "))
        assert.is_not_nil(find_item(items, "Controls"))
        assert.is_not_nil(find_item(items, "Recent filters"))
    end)

    it("exposes strip control font face, size, and weight settings", function()
        local settings = require("modules/settings/sections/library_settings/home_settings")
        assert.is_true(settings.openWidgetSettings("strip"))

        local controls = find_item(arrange_options.item_table, "Controls")
        local controls_items = controls.sub_item_table_func()
        local font = find_item(controls_items, "Font: default, 10, regular")
        assert.is_not_nil(font)

        local font_items = font.sub_item_table_func()
        assert.is_not_nil(find_item(font_items, "Font size: 10"))
        assert.is_not_nil(find_item(font_items, "Font: default"))
        assert.is_not_nil(find_item(font_items, "Bold"))
        assert.is_not_nil(find_item(font_items, "Use default style"))
    end)

    it("confirms before deleting a Strip control tab and returns to Tabs", function()
        local settings = require("modules/settings/sections/library_settings/home_settings")
        home_page.strip_memory = {
            active_id = "favorites",
            source = { kind = "favorites" },
        }
        assert.is_true(settings.openWidgetSettings("strip"))

        local controls = find_item(arrange_options.item_table, "Controls")
        local controls_items = controls.sub_item_table_func()
        local inherited_resume = {
            opener = { text = "Widgets", occurrence = 1 },
            path = { "strip", "Controls" },
        }
        find_item(controls_items, "Tabs").callback({
            _zen_settings_resume = inherited_resume,
        })

        assert.are.equal(2, #arrange_history)
        assert.are.equal(inherited_resume.opener, arrange_options.settings_resume.opener)
        assert.are.same({ "strip", "Controls", "Tabs" },
            arrange_options.settings_resume.path)
        local favorites = find_item(arrange_options.item_table, "Favorites")
        local backs = 0
        find_item(favorites.sub_item_table, "Delete").callback({
            backToUpperMenu = function() backs = backs + 1 end,
        })

        assert.are.same({ "recent", "favorites" },
            home_page.modules.strip.controls.order)
        assert.are.equal(0, backs)
        assert.are.equal("Delete this tab?", shown[1].text)
        assert.are.equal("Delete", shown[1].ok_text)

        shown[1].ok_callback()

        assert.are.same({ "recent" }, home_page.modules.strip.controls.order)
        assert.is_nil(home_page.modules.strip.controls.show_buttons.favorites)
        assert.is_nil(home_page.strip_memory)
        assert.are.equal(1, backs)
    end)

    it("resets Strip control tabs without changing control display settings", function()
        local strip = home_page.modules.strip
        strip.controls.enabled = true
        strip.controls.labels = { favorites = "Saved" }
        strip.controls.next_custom_id = 4
        strip.controls.order = { "favorites", "hs_4" }
        strip.controls.show_buttons = { favorites = true, hs_4 = true }
        strip.controls.custom_buttons = {
            { id = "hs_4", type = "tag", tag = "Science" },
        }
        strip.controls.text_style = {
            font_face = "custom", font_size = 13, bold = true,
        }

        local settings = require("modules/settings/sections/library_settings/home_settings")
        assert.is_true(settings.openWidgetSettings("strip"))
        local controls = find_item(arrange_options.item_table, "Controls")
        local controls_items = controls.sub_item_table_func()
        local updates = 0
        find_item(controls_items, "Reset to defaults").callback({
            updateItems = function() updates = updates + 1 end,
        })

        assert.are.same({ "favorites", "hs_4" }, strip.controls.order)
        assert.are.equal("Reset Controls to defaults?", shown[1].text)
        assert.are.equal("Reset", shown[1].ok_text)

        shown[1].ok_callback()

        assert.are.same({
            "page_left", "recent", "search", "tags", "page_right", "hs_4",
        }, strip.controls.order)
        assert.are.same({
            page_left = true,
            recent = true,
            search = true,
            tags = true,
            page_right = true,
            hs_4 = false,
        }, strip.controls.show_buttons)
        assert.are.same({}, strip.controls.labels)
        assert.are.same({
            { id = "hs_4", type = "tag", tag = "Science" },
        }, strip.controls.custom_buttons)
        assert.are.equal(4, strip.controls.next_custom_id)
        assert.is_true(strip.controls.enabled)
        assert.are.same({
            font_face = "custom", font_size = 13, bold = true,
        }, strip.controls.text_style)
        assert.is_nil(home_page.strip_memory)
        assert.are.equal(1, updates)
    end)

    it("remembers Strip Controls and Tabs when opened from standalone settings", function()
        local settings = require("modules/settings/sections/library_settings/home_settings")
        assert.is_true(settings.openWidgetSettings("strip"))

        local controls = find_item(arrange_options.item_table, "Controls")
        find_item(controls.sub_item_table_func(), "Tabs").callback({})

        local remembered = remembered_routes[#remembered_routes]
        assert.are.equal("Widgets", remembered.opener)
        assert.are.same({ "strip", "Controls", "Tabs" }, remembered.arrange_path)
    end)
end)
