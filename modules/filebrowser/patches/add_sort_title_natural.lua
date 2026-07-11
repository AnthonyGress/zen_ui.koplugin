--- LICENSE see https://github.com/tachibana-shin/natord-plus-lua
local function is_digit(code)
    return code and code >= 48 and code <= 57
end

local function is_space(code)
    return code and (code == 32 or code == 9 or code == 13 or code == 10)
end

local function compare_left(a, b, ai, bi)
    while true do
        local ca = a:byte(ai)
        local cb = b:byte(bi)
        local da = is_digit(ca)
        local db = is_digit(cb)

        if not da and not db then return 0, ai, bi end
        if not da then return -1, ai, bi end
        if not db then return 1, ai, bi end

        if ca < cb then return -1, ai, bi end
        if ca > cb then return 1, ai, bi end

        ai = ai + 1
        bi = bi + 1
    end
end

local function compare_right(a, b, ai, bi)
    local bias = 0
    while true do
        local ca = a:byte(ai)
        local cb = b:byte(bi)
        local da = is_digit(ca)
        local db = is_digit(cb)

        if not da and not db then return bias, ai, bi end
        if not da then return -1, ai, bi end
        if not db then return 1, ai, bi end

        if ca < cb then
            if bias == 0 then bias = -1 end
        elseif ca > cb then
            if bias == 0 then bias = 1 end
        end

        ai = ai + 1
        bi = bi + 1
    end
end

local function natord(a, b, ignore_case)
    a = a or ""
    b = b or ""
    local ai, bi = 1, 1
    local lenA, lenB = #a, #b
    local after_digit = false

    while true do
        local ca = a:byte(ai)
        local cb = b:byte(bi)

        while ai <= lenA and is_space(ca) do
            ai = ai + 1
            ca = a:byte(ai)
        end
        while bi <= lenB and is_space(cb) do
            bi = bi + 1
            cb = b:byte(bi)
        end

        if is_digit(ca) and is_digit(cb) then
            local fractional
            if ca == 48 or cb == 48 then -- Ký tự '0'
                fractional, ai, bi = compare_left(a, b, ai, bi)
            else
                fractional, ai, bi = compare_right(a, b, ai, bi)
            end
            if fractional ~= 0 then return fractional end

            after_digit = true
        else
            if not ca and not cb then return 0 end
            if not ca then return -1 end
            if not cb then return 1 end

            if after_digit then
                if ca == 46 and cb ~= 46 and is_digit(a:byte(ai + 1)) then
                    return 1
                elseif cb == 46 and ca ~= 46 and is_digit(b:byte(bi + 1)) then
                    return -1
                end
            end

            if ignore_case then
                if ca >= 65 and ca <= 90 then ca = ca + 32 end
                if cb >= 65 and cb <= 90 then cb = cb + 32 end
            end

            if ca < cb then return -1 end
            if ca > cb then return 1 end

            ai = ai + 1
            bi = bi + 1
            after_digit = false
        end
    end
end

local function apply_add_sort_title_natural()
    local BookList = require("ui/widget/booklist")
    local title_sort = require("common/title_sort")
    local _ = require("gettext")

    local title_collate = BookList.collates.title
    if title_collate and not title_collate._zen_article_sort_patched then
        local orig_init_sort_func = title_collate.init_sort_func
        title_collate.init_sort_func = function(...)
            local fallback = type(orig_init_sort_func) == "function"
                and orig_init_sort_func(...) or nil
            return function(a, b)
                local ad = a and a.doc_props or {}
                local bd = b and b.doc_props or {}
                local at = ad.display_title or ad.title
                    or (a and (a.text or a.path or a.file)) or ""
                local bt = bd.display_title or bd.title
                    or (b and (b.text or b.path or b.file)) or ""
                local ak = title_sort.key(at):lower()
                local bk = title_sort.key(bt):lower()
                if ak == bk and fallback then return fallback(a, b) end
                return ak < bk
            end
        end
        title_collate._zen_article_sort_patched = true
    end

    BookList.collates.title_natural = {
        text = _("Title natural"),
        menu_order = 100,
        item_func = function(item, ui)
            local doc_props = ui.bookinfo:getDocProps(item.path or item.file)
            item.doc_props = doc_props
        end,
        init_sort_func = function()
            return function(a, b)
                local at = a and a.doc_props and a.doc_props.display_title or ""
                local bt = b and b.doc_props and b.doc_props.display_title or ""
                local cmp = natord(title_sort.key(at), title_sort.key(bt), true)
                if cmp == 0 then cmp = natord(at, bt, true) end
                return cmp < 0
            end
        end,
    }
end

return apply_add_sort_title_natural
