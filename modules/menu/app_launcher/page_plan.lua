local BookDetailsPage = require("modules/menu/app_launcher/book_details_page")
local BookSwitcherPage = require("modules/menu/app_launcher/book_switcher_page")

local M = {}

function M.build(button_page_count, config, library_context)
    button_page_count = math.max(0, math.floor(tonumber(button_page_count) or 0))
    local first, last = {}, {}
    local book_details_enabled = BookDetailsPage.isEnabled(config, library_context)
    local specials = {
        {
            kind = "book_switcher",
            enabled = BookSwitcherPage.isEnabled(config, library_context),
            first = type(config) == "table" and config.book_switcher_first == true
                and not (book_details_enabled and config.book_details_first == true),
        },
        {
            kind = "book_details",
            enabled = book_details_enabled,
            first = type(config) == "table" and config.book_details_first == true,
        },
    }
    for _i, page in ipairs(specials) do
        if page.enabled then
            local target = page.first and first or last
            target[#target + 1] = { kind = page.kind }
        end
    end

    local pages = first
    if button_page_count == 0 and #first == 0 and #last == 0 then
        button_page_count = 1
    end
    for index = 1, button_page_count do
        pages[#pages + 1] = { kind = "buttons", index = index }
    end
    for _i, page in ipairs(last) do pages[#pages + 1] = page end
    return pages
end

return M
