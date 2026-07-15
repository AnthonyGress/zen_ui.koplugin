describe("updater repository redirects", function()
    local original_https
    local original_ltn12
    local original_archiver
    local requests

    before_each(function()
        original_https = package.loaded["ssl.https"]
        original_ltn12 = package.loaded["ltn12"]
        original_archiver = package.loaded["ffi/archiver"]
        requests = {}

        ZenSpec.replace("ffi/archiver", {})
        ZenSpec.replace("config/manager", {
            load = function() return { updater = { update_channel = "stable" } } end,
            save = function() end,
        })
        ZenSpec.replace("ltn12", {
            sink = {
                table = function(target)
                    return function(chunk)
                        if chunk then target[#target + 1] = chunk end
                        return 1
                    end
                end,
            },
        })
        ZenSpec.replace("ssl.https", {
            request = function(request)
                requests[#requests + 1] = request.url
                assert.is_false(request.redirect)
                if #requests == 1 then
                    return 1, 301, {
                        location = "https://api.github.com/repositories/1194031944/releases?per_page=100",
                    }, "HTTP/1.1 301 Moved Permanently"
                end
                request.sink([[
                    [{
                        "url":"https://api.github.com/repos/AnthonyGress/zen-ui/releases/12345",
                        "tag_name":"v999.0.0",
                        "prerelease":false,
                        "body":"Renamed repository release",
                        "published_at":"2026-07-12T00:00:00Z",
                        "assets":[{
                            "name":"zen_ui.koplugin.zip",
                            "browser_download_url":"https://github.com/AnthonyGress/zen-ui/releases/download/v999.0.0/zen_ui.koplugin.zip",
                            "digest":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
                        }]
                    }]
                ]])
                return 1, 200, {}, "HTTP/1.1 200 OK"
            end,
        })
        ZenSpec.unload("modules/settings/zen_updater")
    end)

    after_each(function()
        package.loaded["ssl.https"] = original_https
        package.loaded["ltn12"] = original_ltn12
        package.loaded["ffi/archiver"] = original_archiver
        ZenSpec.unload("modules/settings/zen_updater")
        ZenSpec.unload("config/manager")
    end)

    it("follows the GitHub API rename and accepts assets from the canonical repository", function()
        local updater = require("modules/settings/zen_updater")

        assert.are.equal("ok", updater.check_for_update())
        assert.are.equal(2, #requests)
        assert.are.equal(
            "https://api.github.com/repositories/1194031944/releases?per_page=100",
            requests[2]
        )
        assert.are.equal("999.0.0", updater.latest_version())
        assert.is_true(updater.has_update())
    end)
end)
