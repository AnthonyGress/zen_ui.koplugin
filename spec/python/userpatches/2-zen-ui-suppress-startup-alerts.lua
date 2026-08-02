-- Zen UI test harness: suppress KOReader first-run dialogs.
if G_reader_settings then
    if not G_reader_settings:has("quickstart_shown_version") then
        G_reader_settings:saveSetting("quickstart_shown_version", 2021070000)
    end
    if not G_reader_settings:has("color_rendering") then
        local Device = require("device")
        if Device:hasColorScreen() then
            G_reader_settings:makeTrue("color_rendering")
        end
    end
end
