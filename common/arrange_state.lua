-- Pure arrange-list state helpers shared by the widget and its specs.
local M = {}

M.SUBMENU_CARET = " \u{25B8}"

function M.itemOrderKey(item)
    if type(item) ~= "table" then return item end
    local key = item.orig_item
    if key == nil then key = item.orig_entry end
    if type(key) == "table" then
        return key.id or key.key or key.name or key.text or key.label
    end
    return key or item.text
end

function M.hasRearrangedItems(original, current)
    if type(original) ~= "table" or type(current) ~= "table" then return false end
    if #original ~= #current then return true end
    for i, item in ipairs(current) do
        if M.itemOrderKey(item) ~= M.itemOrderKey(original[i]) then return true end
    end
    return false
end

function M.stripSubmenuCaret(text)
    if type(text) ~= "string" then return text end
    local ascii_caret = " >"
    local old_caret = string.char(226, 150, 184)
    if text:sub(-#M.SUBMENU_CARET) == M.SUBMENU_CARET then
        return text:sub(1, -#M.SUBMENU_CARET - 1)
    end
    if text:sub(-#ascii_caret) == ascii_caret then
        return text:sub(1, -#ascii_caret - 1)
    end
    if text:sub(-#old_caret) == old_caret then
        return (text:sub(1, -#old_caret - 1):gsub("%s+$", ""))
    end
    return text
end

function M.stripValueSuffix(text)
    if type(text) ~= "string" then return text end
    local value_start = text:find(": ", 1, true)
    if value_start and value_start > 1 then return text:sub(1, value_start - 1) end
    return text
end

return M
