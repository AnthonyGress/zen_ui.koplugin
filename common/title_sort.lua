local M = {}

local ARTICLES = {
    en = { a = true, an = true, the = true },
    es = { el = true, la = true, los = true, las = true,
        un = true, una = true, unos = true, unas = true },
    fr = { le = true, la = true, les = true, un = true, une = true, des = true },
    it = { il = true, lo = true, la = true, i = true, gli = true, le = true,
        un = true, uno = true, una = true, dei = true, degli = true, delle = true },
    nl = { de = true, het = true, een = true },
    pt = { o = true, a = true, os = true, as = true,
        um = true, uma = true, uns = true, umas = true },
    ro = { un = true, o = true, ["niște"] = true, ["nişte"] = true },
}

local function current_language()
    local settings = rawget(_G, "G_reader_settings")
    local language = settings and settings.readSetting
        and settings:readSetting("language") or "en"
    return tostring(language):lower():match("^([a-z]+)") or "en"
end

function M.key(title)
    local text = tostring(title or ""):gsub("^%s+", "")
    local language = current_language()
    local localized = ARTICLES[language]
    local first, rest = text:match("^(%S+)%s+(.+)$")
    first = first and first:lower()
    if first and rest and (ARTICLES.en[first] or localized and localized[first]) then
        return rest:gsub("^%s+", "")
    end
    if language == "fr" or language == "it" then
        rest = text:match("^[Ll]'(.+)$") or text:match("^[Ll]’(.+)$")
        if rest then return rest:gsub("^%s+", "") end
    end
    return text
end

return M
