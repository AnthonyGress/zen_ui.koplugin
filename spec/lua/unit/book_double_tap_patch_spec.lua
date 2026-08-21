describe("Double-tap book item patch", function()
    local StandardItem
    local ListItem
    local MosaicItem
    local opened
    local accepted
    local resets
    local saved_modules

    before_each(function()
        opened = 0
        accepted = false
        resets = 0
        saved_modules = {}
        for _i, name in ipairs({
            "apps/filemanager/filemanager",
            "common/book_open_tap",
            "common/cover_utils",
            "listmenu",
            "mosaicmenu",
            "ui/widget/menu",
        }) do
            saved_modules[name] = package.loaded[name]
        end

        local function item_class()
            return {
                onTapSelect = function()
                    opened = opened + 1
                    return true
                end,
            }
        end
        StandardItem = item_class()
        ListItem = item_class()
        MosaicItem = item_class()

        ZenSpec.replace("common/book_open_tap", {
            reset = function() resets = resets + 1 end,
            shouldOpen = function()
                local result = accepted
                accepted = true
                return result
            end,
        })
        ZenSpec.replace("common/cover_utils", {
            getUpvalue = function(fn) return fn() end,
        })
        ZenSpec.replace("ui/widget/menu", {
            updateItems = function() return StandardItem end,
        })
        ZenSpec.replace("listmenu", {
            _updateItemsBuildUI = function() return ListItem end,
        })
        ZenSpec.replace("mosaicmenu", {
            _zen_mosaic_item_class = MosaicItem,
        })
        ZenSpec.replace("apps/filemanager/filemanager", { instance = nil })
        ZenSpec.unload("modules/filebrowser/patches/book_double_tap")
        require("modules/filebrowser/patches/book_double_tap")()
    end)

    after_each(function()
        ZenSpec.unload("modules/filebrowser/patches/book_double_tap")
        for name, module in pairs(saved_modules) do
            package.loaded[name] = module
        end
    end)

    it("consumes the first real tap and opens on the second", function()
        local item = {
            entry = { is_file = true, path = "/books/one.epub" },
            menu = {},
        }

        assert.is_true(StandardItem.onTapSelect(item, nil, { time = 1 }))
        assert.are.equal(0, opened)
        assert.is_true(StandardItem.onTapSelect(item, nil, { time = 1.2 }))
        assert.are.equal(1, opened)
    end)

    it("leaves synthetic keyboard taps and selection mode unchanged", function()
        local item = {
            entry = { is_file = true, path = "/books/one.epub" },
            menu = {},
        }
        StandardItem.onTapSelect(item, nil, {})
        assert.are.equal(1, opened)
        assert.are.equal(1, resets)

        item.menu.ui = { selected_files = {} }
        StandardItem.onTapSelect(item, nil, { time = 1 })
        assert.are.equal(2, opened)
        assert.are.equal(2, resets)
    end)

    it("patches classic, list, and mosaic item classes", function()
        assert.is_true(StandardItem._zen_book_double_tap_patched)
        assert.is_true(ListItem._zen_book_double_tap_patched)
        assert.is_true(MosaicItem._zen_book_double_tap_patched)
    end)
end)
