local _ = require("gettext")

local M = {}

local _settings_list = nil

local function dispatcher_settings_list(Dispatcher)
    if _settings_list ~= nil then
        return _settings_list or nil
    end
    _settings_list = false
    if not (Dispatcher and type(Dispatcher.registerAction) == "function") then
        return nil
    end
    local i = 1
    while true do
        local name, value = debug.getupvalue(Dispatcher.registerAction, i)
        if not name then break end
        if name == "settingsList" then
            _settings_list = value
            break
        end
        i = i + 1
    end
    return _settings_list or nil
end

function M.is_reader_action_key(Dispatcher, key)
    local settings_list = dispatcher_settings_list(Dispatcher)
    local action = settings_list and settings_list[key]
    return type(action) == "table"
        and (action.reader == true or action.rolling == true or action.paging == true)
end

function M.has_reader_action(Dispatcher, actions)
    if type(actions) ~= "table" then return false end
    for key, _value in pairs(actions) do
        if key ~= "settings" and M.is_reader_action_key(Dispatcher, key) then
            return true
        end
    end
    return false
end

function M.has_registered_action(Dispatcher, actions)
    if type(actions) ~= "table" then return false end
    local settings_list = dispatcher_settings_list(Dispatcher)
    local has_action = false
    for key, value in pairs(actions) do
        if key ~= "settings" then
            local name = type(key) == "number" and value or key
            if type(name) == "string" then
                has_action = true
                if not settings_list or settings_list[name] then
                    return true
                end
            end
        end
    end
    return not settings_list and has_action
end

function M.filter_dispatch_menu(items)
    if type(items) ~= "table" then return items end
    local hidden_sections = {
        [_("Reader")] = true,
        [_("Reflowable documents (epub, fb2, txt…)")] = true,
        [_("Fixed layout documents (pdf, djvu, pics…)")] = true,
    }
    for i = #items, 1, -1 do
        local item = items[i]
        if type(item) == "table" and hidden_sections[item.text] then
            table.remove(items, i)
        end
    end
    return items
end

return M
