local function apply_zen_mode()
    local FileManagerMenu = require("apps/filemanager/filemanagermenu")
    local ReaderMenu = require("apps/reader/modules/readermenu")

    local zen_plugin = rawget(_G, "__ZEN_UI_PLUGIN")

    local function is_enabled()
        local features = zen_plugin and zen_plugin.config and zen_plugin.config.features
        return type(features) == "table" and features.zen_mode == true
    end

    local blocked_exact = {
        ["filebrowser"] = true,
        ["file browser"] = true,
        ["settings"] = true,
        ["setting"] = true,
        ["tools"] = true,
        ["search"] = true,
        ["menu"] = true,
        ["navi"] = true,
    }

    local blocked_contains = {
        "filebrowser",
        "setting",
        "tools",
        "search",
        "menu",
        "typeset",
        "display",
        "book",
        "status",
        "frontlight",
        "network",
        "screen",
        "navigation",
    }

    local allow_exact = {
        ["quicksettings"] = true,
        ["quick settings"] = true,
    }

    local function normalize(value)
        if type(value) ~= "string" then
            return nil
        end
        local s = value:lower():gsub("%s+", " ")
        s = s:gsub("^%s+", ""):gsub("%s+$", "")
        return s
    end

    local function tab_values(tab)
        if type(tab) ~= "table" then
            return {}
        end

        local values = {}

        local function push(v)
            if type(v) == "string" then
                local n = normalize(v)
                if n and n ~= "" then
                    table.insert(values, n)
                end
            end
        end

        push(tab.text)

        if type(tab.text_func) == "function" then
            local ok, text = pcall(tab.text_func)
            if ok and type(text) == "string" then
                push(text)
            end
        end

        push(tab.name)
        push(tab.id)
        push(tab.icon)

        return values
    end

    local function should_keep_tab(tab)
        if not is_enabled() then
            return true
        end

        local values = tab_values(tab)
        if #values == 0 then
            return true
        end

        for _, value in ipairs(values) do
            if allow_exact[value] then
                return true
            end
        end

        for _, value in ipairs(values) do
            if blocked_exact[value] then
                return false
            end
            for _, token in ipairs(blocked_contains) do
                if value:find(token, 1, true) then
                    return false
                end
            end
        end

        return true
    end

    local function filter_tab_item_table(tab_item_table)
        if type(tab_item_table) ~= "table" then
            return tab_item_table
        end

        local filtered = {}
        for _, tab in ipairs(tab_item_table) do
            if should_keep_tab(tab) then
                table.insert(filtered, tab)
            end
        end

        return filtered
    end

    local orig_fm_setUpdateItemTable = FileManagerMenu.setUpdateItemTable
    FileManagerMenu.setUpdateItemTable = function(self)
        orig_fm_setUpdateItemTable(self)
        if self.tab_item_table then
            self.tab_item_table = filter_tab_item_table(self.tab_item_table)
        end
    end

    local orig_reader_setUpdateItemTable = ReaderMenu.setUpdateItemTable
    ReaderMenu.setUpdateItemTable = function(self)
        orig_reader_setUpdateItemTable(self)
        if self.tab_item_table then
            self.tab_item_table = filter_tab_item_table(self.tab_item_table)
        end
    end

    local ReaderConfig = require("apps/reader/modules/readerconfig")

    local orig_onShowConfigMenu = ReaderConfig.onShowConfigMenu
    ReaderConfig.onShowConfigMenu = function(self)
        if is_enabled() then
            local features = zen_plugin and zen_plugin.config and zen_plugin.config.features
            if not (type(features) == "table" and features.reader_bottom_menu == true) then
                return
            end
        end
        return orig_onShowConfigMenu(self)
    end
end

return apply_zen_mode
