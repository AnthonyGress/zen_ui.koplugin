describe("icon menu item fonts", function()
    local saved_modules
    local saved_icon_item
    local dependencies = {
        "ffi/blitbuffer",
        "ui/widget/container/bottomcontainer",
        "ui/widget/container/centercontainer",
        "ui/widget/checkmark",
        "device",
        "ui/font",
        "ui/widget/container/framecontainer",
        "ui/geometry",
        "ui/widget/horizontalgroup",
        "ui/widget/horizontalspan",
        "ui/widget/iconwidget",
        "ui/widget/container/leftcontainer",
        "ui/widget/linewidget",
        "ui/widget/overlapgroup",
        "ui/widget/radiomark",
        "ui/widget/container/rightcontainer",
        "ui/size",
        "ui/widget/textwidget",
        "ui/widget/container/underlinecontainer",
        "ui/widget/verticalgroup",
        "common/ui/zen_toggle",
    }

    before_each(function()
        saved_modules = {}
        saved_icon_item = package.loaded["common/ui/icon_menu_item"] or false
        for _i, name in ipairs(dependencies) do
            saved_modules[name] = package.loaded[name] or false
            ZenSpec.replace(name, {})
        end
        package.loaded.device.screen = {
            scaleBySize = function(_self, value) return value end,
        }
        ZenSpec.unload("common/ui/icon_menu_item")
    end)

    after_each(function()
        if saved_icon_item == false then
            package.loaded["common/ui/icon_menu_item"] = nil
        else
            package.loaded["common/ui/icon_menu_item"] = saved_icon_item
        end
        for name, original in pairs(saved_modules) do
            package.loaded[name] = original == false and nil or original
        end
    end)

    it("uses a native menu row's requested font face", function()
        local IconItem = require("common/ui/icon_menu_item")
        local system_face = { name = "system", orig_size = 20 }
        local own_face = { name = "Font A", orig_size = 20 }
        local requested_size
        IconItem.getSettingsFace = function() return system_face end

        local face = IconItem.getItemFace({
            font_func = function(size)
                requested_size = size
                return own_face
            end,
        })

        assert.are.equal(20, requested_size)
        assert.are.equal(own_face, face)
        assert.are.equal(system_face, IconItem.getItemFace({
            font_func = function() end,
        }))
    end)
end)
