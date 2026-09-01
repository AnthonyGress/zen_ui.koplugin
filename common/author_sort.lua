local M = {}

local VALID = {
    authors = true,
    authors_last = true,
}

function M.normalize(mode)
    return VALID[mode] and mode or "authors"
end

function M.isMode(mode)
    return VALID[mode] == true
end

function M.key(name, mode)
    local text = tostring(name or ""):match("^%s*(.-)%s*$")
    local last, first = text:match("^([^,]+),%s*(.+)$")
    if not last then
        first, last = text:match("^(.-)%s+(%S+%s+%S+)$")
        if not last then first, last = text:match("^(.*)%s+(%S+)$") end
    end
    first, last = first or text, last or text
    if mode == "authors_last" then return last end
    -- ponytail: Final-two-word surnames; structured metadata is needed for universal parsing.
    return first
end

function M.less(a, b, mode)
    local ak = M.key(a, mode):lower()
    local bk = M.key(b, mode):lower()
    if ak ~= bk then return ak < bk end
    return tostring(a or ""):lower() < tostring(b or ""):lower()
end

function M.options(gettext)
    return {
        { key = "authors", text = gettext("First name") },
        { key = "authors_last", text = gettext("Last name") },
    }
end

function M.modeButtons(mode, gettext, on_select)
    mode = M.normalize(mode)
    local buttons = {}
    for _i, option in ipairs(M.options(gettext)) do
        local key = option.key
        local active = mode == key
        buttons[#buttons + 1] = {{
            text = "\u{F04BB}  " .. option.text .. (active and "  \u{2713}" or ""),
            align = "left",
            enabled = not active,
            callback = function() on_select(key) end,
        }}
    end
    return buttons
end

return M
