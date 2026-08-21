local M = {}

function M.disableKoreaderAltStatusBar(settings, reader)
    settings = settings or rawget(_G, "G_reader_settings")
    if settings and type(settings.saveSetting) == "function" then
        settings:saveSetting("copt_status_line", 1)
        settings:saveSetting("alt_status_bar", false)
    end

    if reader == nil then
        local ok_reader, ReaderUI = pcall(require, "apps/reader/readerui")
        reader = ok_reader and ReaderUI and ReaderUI.instance
    end
    local configurable = reader and reader.document and reader.document.configurable
    if not (reader and reader.rolling and configurable) then return false end

    configurable.status_line = 1
    if type(reader.handleEvent) == "function" then
        local Event = require("ui/event")
        reader:handleEvent(Event:new("SetStatusLine", 1))
    elseif type(reader.rolling.onSetStatusLine) == "function" then
        reader.rolling:onSetStatusLine(1)
    end
    return true
end

return M
