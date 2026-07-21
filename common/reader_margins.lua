local M = {}

function M.applyZenDefaults(settings)
    settings:saveSetting("copt_h_page_margins", {30, 30})
    settings:saveSetting("copt_sync_t_b_page_margins", 1)
    settings:saveSetting("copt_t_page_margin", 30)
    settings:saveSetting("copt_b_page_margin", 30)
end

return M
