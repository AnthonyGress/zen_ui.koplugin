local M = {}

function M.get(language)
    if language == nil then return nil end
    local original = tostring(language)
    local trimmed = original:match("^%s*(.-)%s*$")
    if trimmed == "" or trimmed:lower() == "n/a" then return language end

    local code = trimmed:gsub("-", "_")
    local ok_language, Language = pcall(require, "ui/language")
    if ok_language and Language and Language.getLanguageName then
        local name = Language:getLanguageName(code)
        if name ~= code then return name end
        local base = code:match("^([^_]+)")
        if base then
            name = Language:getLanguageName(base)
            if name ~= base then return name end
        end
    end

    local ok_iso, IsoLanguage = pcall(require, "ui/data/isolanguage")
    if ok_iso and IsoLanguage and IsoLanguage.getLocalizedLanguage then
        local lowered = code:lower()
        local name = IsoLanguage:getLocalizedLanguage(lowered)
        if name ~= lowered then return name end
    end
    return original
end

return M
