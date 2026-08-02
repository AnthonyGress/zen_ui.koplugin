local M = {}

local ARTICLES = {
    a = true,
    an = true,
    the = true,
}

function M.key(title)
    local text = tostring(title or ""):gsub("^%s+", "")
    local first, rest = text:match("^([%a]+)%s+(.+)$")
    if first and rest and ARTICLES[first:lower()] then
        return rest:gsub("^%s+", "")
    end
    return text
end

return M
