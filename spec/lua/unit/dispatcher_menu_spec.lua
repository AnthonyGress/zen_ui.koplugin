local DispatcherMenu = require("common/dispatcher_menu")

describe("dispatcher menu persistence", function()
    local function menu()
        return {
            refreshes = 0,
            updateItems = function(self)
                self.refreshes = self.refreshes + 1
            end,
        }
    end

    it("saves a synchronous action toggle immediately", function()
        local caller = {}
        local saves = 0
        local items = {{
            callback = function()
                caller.updated = true
            end,
        }}
        DispatcherMenu.wrap(items, caller, function() saves = saves + 1 end)

        items[1].callback(menu())

        assert.are.equal(1, saves)
        assert.is_false(caller.updated)
    end)

    it("saves an asynchronous dispatcher update when it refreshes", function()
        local caller = {}
        local saves = 0
        local pending
        local host = menu()
        local items = {{
            callback = function(touch_menu)
                pending = function()
                    caller.updated = true
                    touch_menu:updateItems()
                end
            end,
        }}
        DispatcherMenu.wrap(items, caller, function() saves = saves + 1 end)

        items[1].callback(host)
        assert.are.equal(0, saves)
        pending()

        assert.are.equal(1, host.refreshes)
        assert.are.equal(1, saves)
        assert.is_false(caller.updated)
    end)

    it("flushes a pending selection on Back or close", function()
        local caller = {}
        local saves = 0
        local host = menu()
        local items = {{ callback = function() end }}
        DispatcherMenu.wrap(items, caller, function() saves = saves + 1 end)
        items[1].callback(host)
        caller.updated = true

        assert.is_true(DispatcherMenu.flush(host))
        assert.are.equal(1, saves)
        assert.is_false(caller.updated)
    end)

    it("wraps dynamically generated action choices", function()
        local caller = {}
        local saves = 0
        local items = {{
            sub_item_table_func = function()
                return {{ callback = function() caller.updated = true end }}
            end,
        }}
        DispatcherMenu.wrap(items, caller, function() saves = saves + 1 end)

        local choices = items[1].sub_item_table_func()
        choices[1].callback(menu())

        assert.are.equal(1, saves)
    end)
end)
