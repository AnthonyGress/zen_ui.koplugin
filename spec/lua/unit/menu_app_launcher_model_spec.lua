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

    it("sanitizes invalid root and folder entries before saving", function()
        local valid_action = { id = "action", type = "action", label = "Open", action = {} }
        local valid_plugin = {
            id = "plugin", type = "plugin", label = "Sync",
            plugin = { key = "sync", method = "run" },
        }
        saved_configs.loaded = {
            entries = {
                valid_action,
                { id = "bad_action", type = "action", label = "Bad" },
                {
                    id = "folder", type = "folder", label = "Tools",
                    children = {
                        valid_plugin,
                        { id = "nested", type = "folder", label = "Nested", children = {} },
                    },
                },
            },
            next_id = 7,
        }

        local cfg = require("modules/menu/app_launcher/model").ensure()

        assert.are.same({ valid_action, {
            id = "folder", type = "folder", label = "Tools", children = { valid_plugin },
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
