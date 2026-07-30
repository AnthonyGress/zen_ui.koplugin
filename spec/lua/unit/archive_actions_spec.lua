describe("archive actions", function()
    local saved
    local moves
    local locations
    local shown
    local archive_path

    before_each(function()
        ZenSpec.unload("common/archive_actions")
        saved = {
            archive_dir_path = "/archive/",
            library_archive_original_dirs = {},
        }
        moves = {}
        locations = {}
        shown = {}
        archive_path = "/archive"
        _G.G_reader_settings = {
            readSetting = function(_, key)
                if key == "home_dir" then return "/library/" end
            end,
        }

        ZenSpec.replace("datastorage", {
            getSettingsDir = function() return "/settings" end,
        })
        ZenSpec.replace("docsettings", {
            updateLocation = function(source, destination)
                locations[#locations + 1] = { source, destination }
            end,
        })
        ZenSpec.replace("apps/filemanager/filemanager", {
            moveFile = function(source, destination)
                moves[#moves + 1] = { source, destination }
                return true
            end,
        })
        ZenSpec.replace("ui/widget/infomessage", {
            new = function(_, options) return options end,
        })
        ZenSpec.replace("ui/widget/confirmbox", {
            new = function(_, options) return options end,
        })
        ZenSpec.replace("luasettings", {
            open = function()
                return {
                    readSetting = function(_, key) return saved[key] end,
                    saveSetting = function(_, key, value) saved[key] = value end,
                    flush = function() end,
                }
            end,
        })
        ZenSpec.replace("ui/uimanager", {
            show = function(_, widget) shown[#shown + 1] = widget end,
            close = function() end,
            nextTick = function(_, fn) fn() end,
            setDirty = function() end,
        })
        ZenSpec.replace("ui/widget/pathchooser", {
            new = function(_, options) return options end,
        })
        ZenSpec.replace("libs/libkoreader-lfs", {
            attributes = function(path, attribute)
                local modes = {
                    ["/archive/"] = "directory",
                    ["/library/"] = "directory",
                    ["/library/book.epub"] = "file",
                    ["/archive/book.epub"] = "file",
                }
                if path == "/archive/book.epub" and #moves == 0 then
                    return nil
                end
                local mode = modes[path]
                return attribute and mode or (mode and { mode = mode })
            end,
        })
        ZenSpec.replace("common/paths", {
            getArchiveDir = function() return archive_path end,
            normPath = function(path) return path:gsub("//+", "/"):gsub("/$", "") end,
        })
        ZenSpec.replace("util", {
            splitFilePathName = function(path)
                return path:match("^(.-)([^/]+)$")
            end,
        })
        ZenSpec.replace("readhistory", {
            updateItem = function() end,
        })
        ZenSpec.replace("readcollection", {
            updateItem = function() end,
        })
    end)

    after_each(function()
        _G.G_reader_settings = nil
        _G.__ZEN_UI_REFRESH_SETTINGS = nil
    end)

    it("moves a library book to the stock archive and remembers its folder", function()
        local ArchiveActions = require("common/archive_actions")
        local fm = {
            file_chooser = {},
            onRefresh = function() end,
        }
        local row = ArchiveActions.contextRow(
            fm, "/library/book.epub", true)

        assert.is_table(row)
        row[1].callback()
        assert.are.same({
            { "/library/book.epub", "/archive/" },
        }, moves)
        assert.are.same({
            { "/library/book.epub", "/archive/book.epub" },
        }, locations)
        assert.are.equal(
            "/library/",
            saved.library_archive_original_dirs["/archive/book.epub"])
    end)

    it("saves a newly chosen archive and requests a live settings refresh", function()
        archive_path = nil
        local refreshes = 0
        _G.__ZEN_UI_REFRESH_SETTINGS = function() refreshes = refreshes + 1 end
        local ArchiveActions = require("common/archive_actions")
        local fm = {
            file_chooser = {},
            onRefresh = function() end,
        }
        local row = ArchiveActions.contextRow(
            fm, "/library/book.epub", true)

        row[1].callback()
        shown[1].ok_callback()
        shown[2].onConfirm("/archive")

        assert.are.equal("/archive/", saved.archive_dir_path)
        assert.are.equal(1, refreshes)
    end)
end)
