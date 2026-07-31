describe("app launcher plugin menu host", function()
    local shown_opts

    before_each(function()
        ZenSpec.unload("modules/menu/app_launcher/menu_host")
        ZenSpec.replace("common/ui/zen_arrange_list", {
            show = function(opts)
                shown_opts = opts
                return { shown = true }
            end,
        })
    end)

    after_each(function()
        ZenSpec.unload("common/ui/zen_arrange_list")
    end)

    it("shows plugin menus as non-arranging Zen lists", function()
        local MenuHost = require("modules/menu/app_launcher/menu_host")
        local item_table = {
            {
                text = "Send review as tags",
                checked_func = function() return false end,
                callback = function() end,
            },
            {
                text = "Choice A",
                radio = true,
                checked_func = function() return true end,
                callback = function() end,
            },
        }

        local host = MenuHost.show{
            title = "Wallabag",
            item_table = item_table,
        }

        assert.is_true(host.shown)
        assert.are.equal("Wallabag", shown_opts.title)
        assert.are.equal(item_table, shown_opts.item_table)
        assert.is_false(shown_opts.allow_arrange)
        assert.is_true(shown_opts.hide_footer_cancel)
        assert.is_true(shown_opts.menu_mode)
    end)
end)
