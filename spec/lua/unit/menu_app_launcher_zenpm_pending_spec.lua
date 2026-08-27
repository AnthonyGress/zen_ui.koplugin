describe("ZenPM launcher pending database", function()
    before_each(function()
        ZenSpec.unload("modules/menu/app_launcher/zenpm_pending")
        ZenSpec.unload("common/db_connection")
    end)

    after_each(function()
        ZenSpec.unload("modules/menu/app_launcher/zenpm_pending")
        ZenSpec.unload("common/db_connection")
    end)

    it("reads and clears only explicitly pending plugin installs", function()
        local rows = {
            { "new-plugin", "/plugins/new.koplugin", 1 },
            { "installed-plugin", "/plugins/installed.koplugin", 0 },
            { "", "/plugins/invalid.koplugin", 1 },
        }
        local row_index = 0
        local cleared = {}
        local select_stmt = {
            step = function()
                row_index = row_index + 1
                return rows[row_index]
            end,
            close = function() end,
        }
        local update_stmt = {
            bind = function(self, id)
                self.id = id
                return self
            end,
            step = function(self)
                cleared[#cleared + 1] = self.id
                return self
            end,
            clearbind = function(self) return self end,
            reset = function(self) return self end,
            close = function() end,
        }
        local connection = {
            exec = function() end,
            prepare = function(_self, sql)
                if sql:find("SELECT", 1, true) then return select_stmt end
                return update_stmt
            end,
            close = function() end,
        }
        ZenSpec.replace("common/db_connection", {
            open = function(path)
                assert.are.equal("/zenpm.sqlite3", path)
                return connection
            end,
        })

        local Pending = require("modules/menu/app_launcher/zenpm_pending")
        local pending, path, installed = Pending.read("/zenpm.sqlite3")
        assert.are.equal("/zenpm.sqlite3", path)
        assert.are.same({ {
            id = "new-plugin",
            install_path = "/plugins/new.koplugin",
        } }, pending)
        assert.are.same({
            ["installed-plugin"] = true,
            ["new-plugin"] = true,
        }, installed)

        assert.is_true(Pending.clear({
            ["new-plugin"] = true,
            ["ignored-plugin"] = false,
        }, "/zenpm.sqlite3"))
        assert.are.same({ "new-plugin" }, cleared)
    end)

    it("treats an older ZenPM database without the flag as empty", function()
        ZenSpec.replace("common/db_connection", {
            open = function()
                return {
                    exec = function() end,
                    prepare = function()
                        error("no such column: launcher_add_pending")
                    end,
                    close = function() end,
                }
            end,
        })

        local rows, path, installed = require(
            "modules/menu/app_launcher/zenpm_pending").read("/zenpm.sqlite3")
        assert.are.same({}, rows)
        assert.are.equal("/zenpm.sqlite3", path)
        assert.is_nil(installed)
    end)
end)
