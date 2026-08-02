local M = {}

M.SIDE_PADDING = 4

local function positive_integer(value)
    return math.max(1, math.floor(tonumber(value) or 0))
end

-- Keep every button cell the same width while adapting to the available row width.
function M.equalCellWidth(available_width, cell_count)
    return positive_integer((tonumber(available_width) or 0) / positive_integer(cell_count))
end

-- TextWidget has no horizontal padding, so a label can use its entire cell.
function M.maxWidth(cell_width, side_padding)
    local inset = math.max(0, math.floor(tonumber(side_padding) or 0))
    return positive_integer((tonumber(cell_width) or 0) - inset * 2)
end

return M
