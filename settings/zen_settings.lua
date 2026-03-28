local settings_builder = require("settings/zen_settings_build")

local M = {}

function M.build(plugin)
    return settings_builder.build(plugin)
end

return M
