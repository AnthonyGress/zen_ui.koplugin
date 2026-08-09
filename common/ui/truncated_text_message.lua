local InfoMessage = require("ui/widget/infomessage")
local Size = require("ui/size")
local UIManager = require("ui/uimanager")

local M = {}

function M.show(text, anchor)
    local message = InfoMessage:new{
        text = text,
        show_icon = false,
    }
    if anchor and anchor.y and anchor.h and message.movable then
        local gap = Size.padding.small
        message.movable.anchor = {
            y = anchor.y - gap,
            h = anchor.h + gap * 2,
        }
    end
    UIManager:show(message)
    return message
end

return M
