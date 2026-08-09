describe("truncated text message", function()
    local saved_modules
    local shown
    local module_names = {
        "ui/widget/infomessage",
        "ui/size",
        "ui/uimanager",
        "common/ui/truncated_text_message",
    }

    before_each(function()
        saved_modules = {}
        for _i, name in ipairs(module_names) do
            saved_modules[name] = package.loaded[name] or false
        end
        shown = nil
        ZenSpec.replace("ui/widget/infomessage", {
            new = function(_self, options)
                options.movable = {}
                return options
            end,
        })
        ZenSpec.replace("ui/size", { padding = { small = 4 } })
        ZenSpec.replace("ui/uimanager", {
            show = function(_self, message) shown = message end,
        })
        ZenSpec.unload("common/ui/truncated_text_message")
    end)

    after_each(function()
        ZenSpec.unload("common/ui/truncated_text_message")
        for _i, name in ipairs(module_names) do
            package.loaded[name] = saved_modules[name] or nil
        end
    end)

    it("keeps InfoMessage styling and anchors it above the row", function()
        local message = require("common/ui/truncated_text_message").show(
            "Full label",
            { y = 300, h = 64 }
        )

        assert.are.equal(message, shown)
        assert.are.equal("Full label", message.text)
        assert.is_false(message.show_icon)
        assert.are.same({ y = 296, h = 72 }, message.movable.anchor)
    end)
end)
