local ZenArrangeList = require("common/ui/zen_arrange_list")

local M = {}

function M.show(opts)
    opts = opts or {}
    return ZenArrangeList.show{
        title = opts.title or "",
        item_table = opts.item_table or {},
        allow_arrange = false,
        hide_footer_cancel = true,
        menu_mode = true,
    }
end

return M
