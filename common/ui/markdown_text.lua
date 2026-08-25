-- Compact Markdown formatting for KOReader TextBoxWidget text.

local M = {}

M.PTF_HEADER = "\u{FFF1}"
local PTF_BOLD_START = "\u{FFF2}"
local PTF_BOLD_END = "\u{FFF3}"

function M.bold(text)
    if type(text) ~= "string" or text == "" then return "" end
    return PTF_BOLD_START .. text .. PTF_BOLD_END
end

local function underscore_emphasis(value, marker)
    local output = {}
    local position = 1
    while position <= #value do
        local start = value:find(marker, position, true)
        if not start then
            output[#output + 1] = value:sub(position)
            break
        end

        local before = start == 1 and "" or value:sub(start - 1, start - 1)
        local ending = value:find(marker, start + #marker, true)
        if before:match("[%w]") or not ending then
            output[#output + 1] = value:sub(position, start + #marker - 1)
            position = start + #marker
        else
            local text = value:sub(start + #marker, ending - 1)
            local after = value:sub(ending + #marker, ending + #marker)
            if text == "" or text:match("^%s") or text:match("%s$") or after:match("[%w]") then
                output[#output + 1] = value:sub(position, start + #marker - 1)
                position = start + #marker
            else
                output[#output + 1] = value:sub(position, start - 1)
                output[#output + 1] = M.bold(text)
                position = ending + #marker
            end
        end
    end
    return table.concat(output)
end

local function render_inline(value)
    value = tostring(value or "")
    value = value:gsub("<!%-%-.-%-%->", ""):gsub("<[^>]->", "")
    value = value:gsub("!%[([^%]]*)%]%([^%)]+%)", "%1")
    value = value:gsub("%[([^%]]+)%]%(([^%)]+)%)", function(label, target)
        return label .. " (" .. (target:match("^%s*([^%s]+)") or target) .. ")"
    end)
    value = value:gsub("`([^`]+)`", "%1")
    value = value:gsub("%*%*%*([^*]+)%*%*%*", M.bold)
    value = value:gsub("%*%*([^*]+)%*%*", M.bold)
    value = underscore_emphasis(value, "__")
    value = value:gsub("%*([^*]+)%*", M.bold)
    return underscore_emphasis(value, "_")
end

function M.render_fragment(markdown)
    markdown = tostring(markdown or ""):gsub("\r\n", "\n"):gsub("\r", "\n")
    local lines = {}
    local in_code = false
    for raw in (markdown .. "\n"):gmatch("(.-)\n") do
        if raw:match("^%s*```") then
            in_code = not in_code
        elseif in_code then
            lines[#lines + 1] = raw
        else
            local hashes, heading = raw:match("^%s*(#+)%s+(.+)$")
            local indent, item = raw:match("^(%s*)[-+*]%s+(.+)$")
            local ordered_indent, number, ordered_item = raw:match("^(%s*)(%d+)[%.)]%s+(.+)$")
            if hashes then
                heading = heading:gsub("%s+#+%s*$", "")
                lines[#lines + 1] = M.bold(render_inline(heading))
            elseif indent then
                lines[#lines + 1] = indent .. "\u{2022} " .. render_inline(item)
            elseif number then
                lines[#lines + 1] = ordered_indent .. number .. ". " .. render_inline(ordered_item)
            elseif raw:match("^%s*[-*_]%s*[-*_]%s*[-*_][%s-*_]*$") then
                lines[#lines + 1] = ""
            else
                local quote = raw:match("^%s*>%s?(.*)$")
                lines[#lines + 1] = quote and ("\u{2502} " .. render_inline(quote))
                    or render_inline(raw)
            end
        end
    end
    return table.concat(lines, "\n")
end

function M.render(markdown)
    return M.PTF_HEADER .. M.render_fragment(markdown)
end

function M.format_list(title, items)
    if type(items) ~= "table" or #items == 0 then return nil end
    local lines = { "# " .. tostring(title or ""), "" }
    for _i, item in ipairs(items) do
        if type(item) == "string" and item ~= "" then
            lines[#lines + 1] = "- " .. item
        end
    end
    if #lines == 2 then return nil end
    return M.render(table.concat(lines, "\n"))
end

return M
