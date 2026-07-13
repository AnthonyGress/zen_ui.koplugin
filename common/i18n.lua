-- common/i18n.lua — Zen UI
-- Injects the plugin's .po translations directly into KOReader's GetText
-- tables so every code path (including modules that captured `local _ =
-- require("gettext")` before the plugin loaded) sees both KOReader's and
-- Zen UI's translations.  Also patches GetText_mt.__index.changeLang so
-- translations are re-injected whenever the user switches languages.
--
-- USAGE: call i18n.install() early in main.lua (before menus are built).
-- Call i18n.uninstall() in ZenUI:onCloseWidget / teardown.

local logger = require("common/zen_logger").new("i18n")

local _dir = (debug.getinfo(1, "S").source:match("^@(.+/)") or "./")

-- ---------------------------------------------------------------------------
-- Minimal .po parser — handles msgctxt, msgid, msgstr, multiline continuations
-- ---------------------------------------------------------------------------
local function parsePO(path)
    local f = io.open(path, "r")
    if not f then return nil end

    local translations = {}  -- [msgid] = msgstr
    local contexts     = {}  -- [msgctxt][msgid] = msgstr

    local ctx, id, str
    local in_id, in_str, in_ctx = false, false, false

    local function unescape(s)
        return s:gsub("\\n", "\n")
                :gsub("\\t", "\t")
                :gsub('\\"', '"')
                :gsub("\\\\", "\\")
    end

    local function flush()
        if id and id ~= "" and str and str ~= "" then
            if ctx and ctx ~= "" then
                if not contexts[ctx] then contexts[ctx] = {} end
                contexts[ctx][id] = str
            else
                translations[id] = str
            end
        end
        ctx, id, str = nil, nil, nil
        in_id, in_str, in_ctx = false, false, false
    end

    for line in f:lines() do
        line = line:match("^%s*(.-)%s*$")
        if line == "" or line:match("^#") then
            if line == "" then flush() end
        elseif line:match("^msgctxt%s+\"") then
            flush()
            ctx   = unescape(line:match('^msgctxt%s+"(.*)"') or "")
            in_ctx = true; in_id = false; in_str = false
        elseif line:match("^msgid%s+\"") then
            -- don't flush here if we just saw msgctxt; they belong together
            if not in_ctx then flush() end
            in_ctx = false
            id    = unescape(line:match('^msgid%s+"(.*)"') or "")
            in_id = true; in_str = false
        elseif line:match("^msgstr%s+\"") then
            str    = unescape(line:match('^msgstr%s+"(.*)"') or "")
            in_str = true; in_id = false; in_ctx = false
        elseif line:match('^"') then
            local cont = unescape(line:match('^"(.*)"') or "")
            if in_ctx and ctx  then ctx = ctx .. cont end
            if in_id  and id   then id  = id  .. cont end
            if in_str and str  then str = str .. cont end
        end
    end
    flush()
    f:close()

    local count = 0
    for _ in pairs(translations) do count = count + 1 end
    for _ in pairs(contexts)     do count = count + 1 end

    return translations, contexts, count
end

-- ---------------------------------------------------------------------------
-- Language detection — mirrors KOReader's own priority order
-- ---------------------------------------------------------------------------
local function detectLang()
    local lang = G_reader_settings and G_reader_settings:readSetting("language")
    if type(lang) == "string" and lang ~= "" then return lang end
    local lc = os.getenv("LANG") or os.getenv("LC_ALL") or os.getenv("LC_MESSAGES") or ""
    lang = lc:match("^([a-zA-Z_]+)")
    return lang or "en"
end

-- ---------------------------------------------------------------------------
-- Load .po translations for a given language string
-- ---------------------------------------------------------------------------
local function loadTranslationsForLang(lang)
    if not lang or lang == "en" or lang:match("^en_") then return nil, nil end

    local function try(name)
        local path = _dir .. "../locales/" .. name .. ".po"
        local t, c, n = parsePO(path)
        if t and n and n > 0 then
            logger.info("loaded " .. path .. " — " .. n .. " entries")
            return t, c
        end
        logger.warn("no translations in " .. path)
        return nil, nil
    end

    local t, c = try(lang)
    if t then return t, c end

    -- fallback: language prefix only (e.g. "pt" for "pt_BR")
    local prefix = lang:match("^([a-zA-Z]+)")
    if prefix and prefix ~= lang then
        logger.warn("falling back from " .. lang .. " to " .. prefix)
        return try(prefix)
    end
    logger.warn("no .po file found for lang=" .. lang)
    return nil, nil
end

-- ---------------------------------------------------------------------------
-- Inject Zen UI translations into the live GetText tables.
-- Called at startup and again after every changeLang().
-- ---------------------------------------------------------------------------
local function applyZenTranslations(GetText, lang)
    local translations, contexts = loadTranslationsForLang(lang)
    if not translations then
        logger.warn("skipping injection — no translations for lang=" .. (lang or "nil"))
        return
    end
    for msgid, msgstr in pairs(translations) do
        GetText.translation[msgid] = msgstr
    end
    for msgctxt, msgs in pairs(contexts or {}) do
        if not GetText.context[msgctxt] then
            GetText.context[msgctxt] = {}
        end
        for msgid, msgstr in pairs(msgs) do
            GetText.context[msgctxt][msgid] = msgstr
        end
    end
end

-- ---------------------------------------------------------------------------
-- install / uninstall
-- ---------------------------------------------------------------------------
local _installed       = false
local _orig_gettext    = nil
local _orig_changeLang = nil

local function install()
    if _installed then return end

    local GetText = package.loaded["gettext"]
    if not GetText then
        local ok, gt = pcall(require, "gettext")
        if not ok or not gt then
            logger.warn("cannot load gettext — translations disabled")
            return
        end
        GetText = gt
    end
    _orig_gettext = GetText

    -- Inject translations for the current language
    applyZenTranslations(GetText, detectLang())

    -- Patch changeLang so we re-inject after every language switch.
    -- GetText_mt.__index is the method table; we replace changeLang in-place.
    local mt = getmetatable(GetText)
    if mt and type(mt.__index) == "table" then
        local mt_index = mt.__index
        local orig_changeLang = mt_index.changeLang
        _orig_changeLang = orig_changeLang
        mt_index.changeLang = function(new_lang)
            local result = orig_changeLang(new_lang)
            if result == false then
                logger.warn("changeLang failed for lang=" .. (new_lang or "nil"))
            end
            applyZenTranslations(GetText, new_lang)
            return result
        end
    else
        logger.warn("cannot patch changeLang — unexpected gettext metatable shape")
    end

    _installed = true
    logger.info("installed for lang=" .. (detectLang() or "?"))
end

local function uninstall()
    if not _installed then return end
    if _orig_gettext and _orig_changeLang then
        local mt = getmetatable(_orig_gettext)
        if mt and type(mt.__index) == "table" then
            -- Restore original changeLang first
            mt.__index.changeLang = _orig_changeLang
            -- Reload clean KOReader translations without Zen UI overlay
            _orig_changeLang(_orig_gettext.current_lang)
        else
            logger.warn("uninstall — cannot restore changeLang, metatable changed")
        end
    else
        logger.warn("uninstall — missing saved state, may be partially installed")
    end
    _orig_changeLang = nil
    _orig_gettext    = nil
    _installed       = false
    logger.info("uninstalled")
end

return {
    install   = install,
    uninstall = uninstall,
    getLang   = detectLang,
}
