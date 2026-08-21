describe("app launcher model", function()
    local saved_configs

    before_each(function()
        saved_configs = {}
        ZenSpec.unload("modules/menu/app_launcher/model")
        ZenSpec.replace("modules/menu/app_launcher/store", {
            load = function()
                return saved_configs.loaded
            end,
            save = function(cfg)
                saved_configs.saved = cfg
                return cfg
            end,
        })
    end)

    after_each(function()
        ZenSpec.unload("pluginloader")
    end)

    it("sanitizes invalid root and folder entries before saving", function()
        local valid_action = { id = "action", type = "action", label = "Open", action = {} }
        local valid_plugin = {
            id = "plugin", type = "plugin", label = "Sync",
            plugin = { key = "sync", method = "run" },
        }
        local valid_koreader_menu = {
            id = "menu", type = "koreader_menu", label = "Network",
            koreader_menu = { id = "network", title = "Network" },
        }
        local folder_koreader_menu = {
            id = "folder_menu", type = "koreader_menu", label = "Tools",
            koreader_menu = { id = "tools", title = "Tools" },
        }
        saved_configs.loaded = {
            entries = {
                valid_action,
                valid_koreader_menu,
                { id = "bad_menu", type = "koreader_menu", label = "Bad" },
                { id = "bad_action", type = "action", label = "Bad" },
                {
                    id = "folder", type = "folder", label = "Tools",
                    children = {
                        valid_plugin,
                        folder_koreader_menu,
                        { id = "nested", type = "folder", label = "Nested", children = {} },
                    },
                },
            },
            next_id = 7,
        }

        local cfg = require("modules/menu/app_launcher/model").ensure()

        assert.are.same({ valid_action, valid_koreader_menu, {
            id = "folder", type = "folder", label = "Tools",
            children = { valid_plugin, folder_koreader_menu },
        } }, cfg.entries)
        assert.are.equal(cfg, saved_configs.saved)
    end)

    it("allocates monotonic ids and finds nested entries", function()
        local Model = require("modules/menu/app_launcher/model")
        local cfg = { next_id = "4" }
        local child = { id = "child", type = "action", label = "Child", action = {} }
        local folder = { id = "folder", type = "folder", label = "Folder", children = { child } }
        local entries = { folder }

        assert.are.equal("al_5", Model.next_id(cfg))
        local list, index, found, parent = Model.find_by_id(entries, "child")
        assert.are.equal(folder.children, list)
        assert.are.equal(1, index)
        assert.are.equal(child, found)
        assert.are.equal(folder, parent)
    end)

    it("preserves folder shortcuts and specific tags at root and inside folders", function()
        local fiction = {
            id = "fiction", type = "folder_shortcut", label = "Fiction",
            folder = "/library/Fiction",
        }
        local science = {
            id = "science", type = "tag", label = "Science", tag = "Science",
        }
        saved_configs.loaded = {
            entries = {
                fiction,
                { id = "tools", type = "folder", label = "Tools", children = { science } },
            },
        }

        local cfg = require("modules/menu/app_launcher/model").ensure()

        assert.are.equal(fiction, cfg.entries[1])
        assert.are.equal(science, cfg.entries[2].children[1])
        assert.is_nil(saved_configs.saved)
    end)

    it("moves entries within lists, into folders, and back to root", function()
        local Model = require("modules/menu/app_launcher/model")
        local first = { id = "first", type = "action", label = "First", action = {} }
        local second = { id = "second", type = "action", label = "Second", action = {} }
        local folder = { id = "folder", type = "folder", label = "Folder", children = {} }
        local entries = { first, second, folder }

        assert.is_true(Model.move_by(entries, "second", -1))
        assert.are.equal(second, entries[1])
        assert.is_false(Model.move_by(entries, "second", -1))
        assert.is_true(Model.move_to_folder(entries, "first", "folder"))
        assert.are.same({ first }, folder.children)
        assert.is_false(Model.move_to_folder(entries, "folder", "folder"))
        assert.is_true(Model.move_to_root(entries, "first"))
        assert.are.equal(first, entries[#entries])
        assert.is_false(Model.move_to_root(entries, "second"))
        assert.is_true(Model.remove_by_id(entries, "second"))
        assert.is_false(Model.remove_by_id(entries, "missing"))
    end)

    it("omits buttons disabled in launcher settings", function()
        local Model = require("modules/menu/app_launcher/model")
        local first = { id = "first", enabled = true }
        local disabled = { id = "disabled", enabled = false }
        local default_enabled = { id = "default" }

        assert.are.same({ first, default_enabled },
            Model.enabled_entries({ first, disabled, default_enabled }))
    end)

    it("adds enabled ZenPM once without replacing an existing launcher entry", function()
        ZenSpec.replace("pluginloader", {
            loadPlugins = function()
                return { { name = "zenpm" } }
            end,
        })
        local Model = require("modules/menu/app_launcher/model")
        saved_configs.loaded = { entries = {}, next_id = 3 }

        assert.is_true(Model.ensure_zenpm_launcher_entry())
        assert.are.same({ {
            id = "al_4",
            type = "plugin",
            label = "ZenPM",
            icon = "zenpm",
            plugin = { key = "zenpm", method = "open" },
        } }, saved_configs.loaded.entries)
        assert.is_true(saved_configs.loaded.zenpm_launcher_added)

        saved_configs.saved = nil
        assert.is_false(Model.ensure_zenpm_launcher_entry())
        assert.is_nil(saved_configs.saved)
    end)

    it("keeps an existing ZenPM launcher entry and records the integration", function()
        ZenSpec.replace("pluginloader", {
            loadPlugins = function()
                return { { name = "zenpm" } }
            end,
        })
        local Model = require("modules/menu/app_launcher/model")
        local existing = {
            id = "al_7",
            type = "plugin",
            label = "My ZenPM",
            plugin = { key = "zenpm", method = "onOpenZenPM" },
        }
        saved_configs.loaded = { entries = { existing }, next_id = 7 }

        assert.is_true(Model.ensure_zenpm_launcher_entry())
        assert.are.same({ existing }, saved_configs.loaded.entries)
        assert.is_true(saved_configs.loaded.zenpm_launcher_added)
    end)

    it("waits to record the integration until ZenPM is enabled", function()
        ZenSpec.replace("pluginloader", {
            loadPlugins = function()
                return { { name = "other_plugin" } }
            end,
        })
        local Model = require("modules/menu/app_launcher/model")
        saved_configs.loaded = { entries = {}, next_id = 3 }

        assert.is_false(Model.ensure_zenpm_launcher_entry())
        assert.are.same({}, saved_configs.loaded.entries)
        assert.is_nil(saved_configs.loaded.zenpm_launcher_added)
        assert.is_nil(saved_configs.saved)
    end)
end)

describe("app launcher action filter", function()
    before_each(function()
        ZenSpec.unload("modules/menu/app_launcher/action_filter")
    end)

    it("recognizes reader-only dispatcher actions", function()
        local settingsList = {
            reader_action = { reader = true },
            rolling_action = { rolling = true },
            library_action = { category = "none" },
        }
        local function registerAction()
            return settingsList
        end
        local Dispatcher = { registerAction = registerAction }
        local Filter = require("modules/menu/app_launcher/action_filter")

        assert.is_true(Filter.is_reader_action_key(Dispatcher, "reader_action"))
        assert.is_true(Filter.is_reader_action_key(Dispatcher, "rolling_action"))
        assert.is_false(Filter.is_reader_action_key(Dispatcher, "library_action"))
        assert.is_true(Filter.has_reader_action(Dispatcher, { settings = {}, reader_action = {} }))
        assert.is_false(Filter.has_reader_action(Dispatcher, { settings = {}, library_action = {} }))
        assert.is_false(Filter.has_reader_action(Dispatcher, "invalid"))
    end)

    it("detects actions that are no longer registered", function()
        local settingsList = {
            available_action = { category = "none" },
        }
        local function registerAction()
            return settingsList
        end
        local Dispatcher = { registerAction = registerAction }
        local Filter = require("modules/menu/app_launcher/action_filter")

        assert.is_true(Filter.has_registered_action(Dispatcher, {
            available_action = {},
        }))
        assert.is_true(Filter.has_registered_action(Dispatcher, {
            missing_action = {},
            available_action = {},
        }))
        assert.is_false(Filter.has_registered_action(Dispatcher, {
            missing_action = {},
        }))
        assert.is_false(Filter.has_registered_action(Dispatcher, { settings = {} }))
    end)

    it("removes reader dispatcher sections in place", function()
        local Filter = require("modules/menu/app_launcher/action_filter")
        local items = {
            { text = "Reader" },
            { text = "Keep" },
            { text = "Fixed layout documents (pdf, djvu, pics…)" },
            { text = "Reflowable documents (epub, fb2, txt…)" },
        }

        assert.are.equal(items, Filter.filter_dispatch_menu(items))
        assert.are.same({ { text = "Keep" } }, items)
        assert.are.equal("invalid", Filter.filter_dispatch_menu("invalid"))
    end)
end)
