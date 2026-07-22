describe("database connection", function()
    local files
    local opened

    before_each(function()
        files = {}
        opened = {}
        ZenSpec.unload("common/db_connection")
        ZenSpec.replace("datastorage", {
            getDataDir = function() return "/data" end,
            getSettingsDir = function() return "/settings" end,
        })
        ZenSpec.replace("libs/libkoreader-lfs", {
            attributes = function(path, attribute)
                if attribute == "mode" and files[path] then return "file" end
            end,
        })
        ZenSpec.replace("lua-ljsqlite3/init", {
            open = function(path)
                opened[#opened + 1] = path
                return { path = path }
            end,
        })
        ZenSpec.replace("common/zen_logger", {
            new = function() return { warn = function() end } end,
        })
    end)

    it("prefers the data database and falls back to settings", function()
        local DB = require("common/db_connection")
        assert.are.equal("/data/statistics.sqlite3", DB.getStatsDbPath())
        files["/settings/statistics.sqlite3"] = true
        assert.are.equal("/settings/statistics.sqlite3", DB.getStatsDbPath())
        files["/data/statistics.sqlite3"] = true
        assert.are.equal("/data/statistics.sqlite3", DB.getStatsDbPath())
    end)

    it("opens only existing database files", function()
        local DB = require("common/db_connection")
        local conn, err = DB.open("/missing.sqlite3")
        assert.is_nil(conn)
        assert.matches("file not found", err, nil, true)

        files["/books.sqlite3"] = true
        conn, err = DB.open("/books.sqlite3")
        assert.is_nil(err)
        assert.are.equal("/books.sqlite3", conn.path)
        assert.are.same({ "/books.sqlite3" }, opened)
    end)

    it("returns the SQLite error without raising", function()
        ZenSpec.replace("lua-ljsqlite3/init", {
            open = function() error("invalid database") end,
        })
        files["/broken.sqlite3"] = true
        local DB = require("common/db_connection")
        local conn, err = DB.open("/broken.sqlite3")
        assert.is_nil(conn)
        assert.matches("invalid database", err, nil, true)
    end)
end)
