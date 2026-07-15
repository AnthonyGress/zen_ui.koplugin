local M = {}

function M.nextMinuteDelay(time_table)
    local second = type(time_table) == "table" and tonumber(time_table.sec) or 0
    second = second or 0
    local delay = 60 - second
    if delay <= 0 or delay > 60 then return 60 end
    return delay
end

return M
