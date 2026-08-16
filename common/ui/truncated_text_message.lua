local InfoMessage = require("ui/widget/infomessage")
local Size = require("ui/size")
local UIManager = require("ui/uimanager")

local M = {}

local function show(text, anchor, align_to_row)
    local options = {
        text = text,
        show_icon = false,
    }
    if align_to_row then options.alignment = "left" end
    local message = InfoMessage:new(options)
    if anchor and anchor.y and anchor.h and message.movable then
        local gap = Size.padding.small
        local popup_anchor = {
            y = anchor.y - gap,
            h = anchor.h + gap * 2,
        }
        if align_to_row and anchor.x ~= nil and anchor.w ~= nil then
            popup_anchor.x = anchor.x
            popup_anchor.w = anchor.w
        end
        message.movable.anchor = popup_anchor
    end
    UIManager:show(message)
    return message
end

function M.show(text, anchor)
    return show(text, anchor, false)
end

function M.showMetadata(text, anchor)
    return show(text, anchor, true)
end

return M
