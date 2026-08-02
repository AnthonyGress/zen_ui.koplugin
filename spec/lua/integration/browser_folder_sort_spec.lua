describe("browser folder sort patch", function()
    local FileChooser
    local config

    before_each(function()
        config = { folder_sort = {} }
        FileChooser = {
            collates = { title = { id = "title" } },
            getCollate = function(self) return self.collates.title, "title" end,
            getSortingFunction = function(_, _, reverse)
                return function(a, b)
                    if reverse then return a.text > b.text end
                    return a.text < b.text
                end
            end,
            genItemTableFromPath = function()
                return {
                    { text = "A/", path = "/library/folder/A", attr = { mode = "directory", access = 1, modification = 1 } },
                    { text = "B/", path = "/library/folder/B", attr = { mode = "directory", access = 1, modification = 1 } },
                }
            end,
        }
        ZenSpec.replace("ui/widget/filechooser", FileChooser)
        ZenSpec.replace("config/manager", {
            get = function() return config end,
            load = function() return config end,
            save = function(value) config = value end,
        })
        ZenSpec.replace("ffi/util", { realpath = function(path) return path end })
        ZenSpec.replace("common/history_index", {
            load = function() return {} end,
            maxDescendantTimes = function() return {} end,
        })
        ZenSpec.replace("common/paths", {
            normPath = function(path) return path end,
            getHomeDir = function() return "/library" end,
        })
        ZenSpec.unload("modules/filebrowser/patches/browser_folder_sort")
        require("modules/filebrowser/patches/browser_folder_sort")()
    end)

    it("persists normalized overrides and applies reverse sorting outside home", function()
        local api = assert(_G.__ZEN_FOLDER_SORT)
        api.set("/library/folder/", "title", true)
        assert.are.same({ collate = "title", reverse = true }, api.get("/library/folder"))
        local items = FileChooser:genItemTableFromPath("/library/folder")
        assert.are.equal("B/", items[1].text)
        api.clear("/library/folder")
        assert.is_nil(api.get("/library/folder"))
    end)

    it("never applies an override to the configured home directory", function()
        local api = assert(_G.__ZEN_FOLDER_SORT)
        api.set("/library", "title", true)
        local items = FileChooser:genItemTableFromPath("/library")
        assert.are.equal("A/", items[1].text)
    end)
end)
