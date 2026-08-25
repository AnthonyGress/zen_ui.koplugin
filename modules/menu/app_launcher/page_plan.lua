local BookDetailsPage = require("modules/menu/app_launcher/book_details_page")
local BookSwitcherPage = require("modules/menu/app_launcher/book_switcher_page")

local M = {}

M.DEFAULT_ORDER = { "book_details", "book_switcher", "buttons" }

function M.normalizeOrder(order, fallback)
    local normalized = {}
    local seen = {}
    local valid = { book_details = true, book_switcher = true, buttons = true }
    local function append(items)
        for _i, kind in ipairs(type(items) == "table" and items or {}) do
            if valid[kind] and not seen[kind] then
                normalized[#normalized + 1] = kind
                seen[kind] = true
            end
        end
    end
    append(order)
    append(fallback)
    append(M.DEFAULT_ORDER)
    return normalized
end

function M.build(button_page_count, config, library_context)
    button_page_count = math.max(0, math.floor(tonumber(button_page_count) or 0))
    config = type(config) == "table" and config or {}
    local enabled = {
        book_switcher = BookSwitcherPage.isEnabled(config, library_context),
        book_details = BookDetailsPage.isEnabled(config, library_context),
    }
    local pages = {}
    for _i, kind in ipairs(M.normalizeOrder(config.page_order)) do
        if kind == "buttons" then
            for index = 1, button_page_count do
                pages[#pages + 1] = { kind = "buttons", index = index }
            end
        elseif enabled[kind] then
            pages[#pages + 1] = { kind = kind }
        end
    end

    if #pages == 0 then pages[1] = { kind = "buttons", index = 1 } end
    return pages
end

return M
