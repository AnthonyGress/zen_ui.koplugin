describe("settings utilities", function()
    local Utils

    before_each(function()
        ZenSpec.replace("device", {})
        ZenSpec.replace("ui/uimanager", {})
        ZenSpec.unload("modules/settings/zen_settings_utils")
        Utils = require("modules/settings/zen_settings_utils")
    end)

    it("normalizes values and reads and writes nested paths", function()
        assert.are.equal("42", Utils.normalize_value(42))
        assert.are.equal("value", Utils.normalize_value("  value  "))
        assert.is_nil(Utils.normalize_value("   "))
        assert.is_nil(Utils.normalize_value({}))
        assert.are.equal("first", Utils.first_non_empty("", nil, "first", "second"))

        local config = {}
        Utils.set_path(config, { "reader", "clock", "enabled" }, true)
        assert.is_true(Utils.get_path(config, { "reader", "clock", "enabled" }))
        assert.is_nil(Utils.get_path(config, { "reader", "missing" }))
    end)

    it("toggles a feature and invokes the supplied apply callback", function()
        local config = { features = { navbar = false } }
        local applied
        local item = Utils.make_enable_feature_item("navbar", "Navbar", config, function(feature)
            applied = feature
        end)

        assert.is_false(item.checked_func())
        item.callback()
        assert.is_true(item.checked_func())
        assert.are.equal("navbar", applied)
        item.callback()
        assert.is_false(item.checked_func())
    end)

    it("orders preferred items first while preserving all remaining items", function()
        local alpha = { text = "Alpha" }
        local beta = { text = "Beta" }
        local duplicate_beta = { text = "Beta", id = "duplicate" }
        local unnamed = { separator = true }

        local ordered = Utils.order_items_by_text(
            { alpha, beta, duplicate_beta, unnamed },
            { "Beta", "Missing", "Alpha" }
        )

        assert.are.same({ beta, alpha, duplicate_beta, unnamed }, ordered)
    end)

    it("reorders the first matching nested submenu", function()
        local one = { text = "One" }
        local two = { text = "Two" }
        local menu = {{
            text = "Outer",
            sub_item_table = {{
                text = "Target",
                sub_item_table = { one, two },
            }},
        }}

        assert.is_true(Utils.reorder_nested_items_by_text(menu, "Target", { "Two", "One" }))
        assert.are.same({ two, one }, menu[1].sub_item_table[1].sub_item_table)
        assert.is_false(Utils.reorder_nested_items_by_text(menu, "Missing", {}))
    end)

    it("formats time and resolves the active file manager directory", function()
        assert.are.equal("03:07", Utils.fmt_time(3, 7))
        ZenSpec.replace("apps/filemanager/filemanager", {
            instance = { file_chooser = { path = "/books/current" } },
        })
        assert.are.equal("/books/current", Utils.get_current_dir())

        ZenSpec.replace("apps/filemanager/filemanager", { instance = nil })
        G_reader_settings:saveSetting("lastdir", "/books/last")
        assert.are.equal("/books/last", Utils.get_current_dir())
    end)
end)
