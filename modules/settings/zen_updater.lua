-- settings/zen_updater.lua
-- Checks the GitHub releases API for a newer Zen UI version, downloads the
-- release.zip asset, unpacks it in-place, and prompts for a KOReader restart.

local _ = require("gettext")
local logger = require("logger")

local GITHUB_API_URL      = "https://api.github.com/repos/AnthonyGress/zen_ui.koplugin/releases/latest"
local GITHUB_RELEASES_URL = "https://api.github.com/repos/AnthonyGress/zen_ui.koplugin/releases"

-- Resolve the plugin root directory from this file's own path so the module
-- works regardless of where KOReader is installed.
local PLUGIN_ROOT = (function()
    local src = debug.getinfo(1, "S").source or ""
    if src:sub(1, 1) == "@" then
        return src:sub(2):match("^(.*)/modules/settings/zen_updater%.lua$")
    end
end)()

local M = {}

-- Cached result (populated on first check_for_update call).
M._checked    = false
M._has_update = false
M._latest_ver = nil   -- latest version string without leading "v"
M._dl_url     = nil   -- download URL for release.zip

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

--- Parse major/minor/patch integers from version strings like "v1.2.3",
--- "1.2.3", or "1.2.3-beta1". Pre-release suffixes are stripped so that
--- "1.2.3-beta1" compares numerically equal to "1.2.3" (stable wins ties).
local function parse_semver(v)
    v = (v or ""):match("^v?(.+)$") or ""
    v = v:match("^([%d%.]+)") or ""  -- strip -prerelease / +build suffixes
    local maj, min, pat = v:match("^(%d+)%.(%d+)%.?(%d*)$")
    return tonumber(maj) or 0, tonumber(min) or 0, tonumber(pat) or 0
end

--- Returns true when version string a is strictly greater than b.
local function semver_gt(a, b)
    local a1, a2, a3 = parse_semver(a)
    local b1, b2, b3 = parse_semver(b)
    if a1 ~= b1 then return a1 > b1 end
    if a2 ~= b2 then return a2 > b2 end
    return a3 > b3
end

--- Read the current plugin version from _meta.lua.
local function get_current_version()
    if PLUGIN_ROOT then
        local ok, meta = pcall(dofile, PLUGIN_ROOT .. "/_meta.lua")
        if ok and type(meta) == "table" and meta.version then
            return meta.version
        end
    end
    local ok, meta = pcall(require, "_meta")
    if ok and type(meta) == "table" and meta.version then
        return meta.version
    end
    return "0.0.0"
end

--- Extract a string field value from a GitHub API JSON response.
--- Handles simple cases only (no nested depth needed for the fields we use).
local function json_str(json, key)
    return json:match('"' .. key .. '"%s*:%s*"([^"]*)"')
end

--- Best-effort HTTPS GET; returns the response body string or nil.
--- Uses ssl.https (LuaSec, bundled with KOReader).
local function https_get(url)
    local ok_ssl, https = pcall(require, "ssl.https")
    local ok_ltn, ltn12 = pcall(require, "ltn12")
    if not ok_ssl or not ok_ltn then
        logger.warn("ZenUpdater: ssl.https or ltn12 not available")
        return nil
    end

    logger.dbg("ZenUpdater: GET", url)
    local body = {}
    local ok_req, req_err = pcall(function()
        local _, code = https.request{
            url     = url,
            headers = { ["User-Agent"] = "zen_ui.koplugin" },
            sink    = ltn12.sink.table(body),
        }
        logger.dbg("ZenUpdater: HTTP response code", code)
        if code ~= 200 then
            body = nil
        end
    end)
    if not ok_req then
        logger.warn("ZenUpdater: https_get failed:", req_err)
        return nil
    end
    if not body then return nil end
    return table.concat(body)
end

--- Find the browser_download_url for the asset named "zen_ui.koplugin.zip" inside the
--- GitHub releases API JSON body. Returns nil if not found.
local function extract_asset_url(json)
    local assets = json:match('"assets"%s*:%s*(%b[])')
    if assets then
        for obj in assets:gmatch('%b{}') do
            if obj:find('"zen_ui%.koplugin%.zip"') then
                local url = json_str(obj, "browser_download_url")
                if url then return url end
            end
        end
    end
    return nil
end

--- Returns true only for a proper release asset download URL.
local function is_valid_asset_url(url)
    return type(url) == "string" and url:find("/releases/download/", 1, true) ~= nil
end

--- Download a file via HTTPS to dest_path, following up to 5 redirects.
--- Returns true on success, or false + error message on failure.
local function https_download(url, dest_path, depth)
    depth = depth or 0
    if depth > 5 then return false, "too many redirects" end

    local ok_ssl, https = pcall(require, "ssl.https")
    local ok_ltn, ltn12 = pcall(require, "ltn12")
    if not ok_ssl or not ok_ltn then
        return false, "ssl.https not available"
    end

    -- Resolve any redirect chain via HEAD requests (avoids writing partial data).
    local resolved_url = url
    for _ = 1, 5 do
        local _, r_code, r_headers = https.request{
            url     = resolved_url,
            method  = "HEAD",
            headers = { ["User-Agent"] = "zen_ui.koplugin" },
            sink    = ltn12.sink.null(),
        }
        if (r_code == 301 or r_code == 302 or r_code == 307 or r_code == 308)
            and r_headers and r_headers.location then
            resolved_url = r_headers.location
        else
            break
        end
    end

    -- Perform the actual download.
    local f, ferr = io.open(dest_path, "wb")
    if not f then return false, ferr end

    local _, dl_code = https.request{
        url     = resolved_url,
        headers = { ["User-Agent"] = "zen_ui.koplugin" },
        sink    = ltn12.sink.file(f),
    }
    -- ltn12.sink.file closes f on EOF; pcall guards against double-close.
    pcall(f.close, f)

    if dl_code ~= 200 then
        os.remove(dest_path)
        return false, "HTTP " .. tostring(dl_code)
    end
    return true
end

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------

local CHECK_INTERVAL = 24 * 3600  -- seconds between automatic checks
local GS_KEY_TIME    = "zen_ui_last_update_check"
local GS_KEY_AVAIL   = "zen_ui_update_available"
local GS_KEY_VER     = "zen_ui_latest_version"
local GS_KEY_URL     = "zen_ui_update_dl_url"
local GS_KEY_CHANNEL = "zen_ui_update_channel"

--- Load or write persisted update state via G_reader_settings.
local function get_gs()
    local ok, gs = pcall(function() return G_reader_settings end)
    return (ok and gs) or nil
end

local function get_channel()
    local gs = get_gs()
    if gs then
        local ch = gs:readSetting(GS_KEY_CHANNEL)
        if ch == "beta" then return "beta" end
    end
    return "stable"
end

local function persist_state(now)
    local gs = get_gs()
    if not gs then return end
    gs:saveSetting(GS_KEY_TIME,  now)
    gs:saveSetting(GS_KEY_AVAIL, M._has_update)
    gs:saveSetting(GS_KEY_VER,   M._latest_ver or "")
    gs:saveSetting(GS_KEY_URL,   M._dl_url or "")
    pcall(gs.flush, gs)
end

--- Clear all persisted update state (called after a successful install).
local function clear_update_state()
    M._has_update = false
    M._latest_ver = nil
    M._dl_url     = nil
    local gs = get_gs()
    if gs then
        gs:saveSetting(GS_KEY_AVAIL, false)
        gs:saveSetting(GS_KEY_VER,   "")
        gs:saveSetting(GS_KEY_URL,   "")
        pcall(gs.flush, gs)
    end
end

local function load_cached_state()
    local gs = get_gs()
    if not gs then return end
    M._has_update = gs:readSetting(GS_KEY_AVAIL) == true
    local ver = gs:readSetting(GS_KEY_VER)
    M._latest_ver = (type(ver) == "string" and ver ~= "") and ver or nil
    local url = gs:readSetting(GS_KEY_URL)
    -- Reject stale zipball/tarball URLs from before the asset-only fix.
    M._dl_url = is_valid_asset_url(url) and url or nil
    -- Discard stale notifications when the installed version already matches
    -- or exceeds the cached release (e.g. after a successful update).
    if M._has_update and not semver_gt(M._latest_ver or "", get_current_version()) then
        clear_update_state()
    end
end

--- Perform an actual network check; returns true on success.
local function do_network_check()
    local channel = get_channel()
    local current = get_current_version()
    logger.dbg("ZenUpdater: do_network_check channel=", channel, "current=", current)
    local tag, dl_url

    if channel == "beta" then
        -- Fetch latest stable and latest prerelease; use whichever is newer.
        -- Stable wins when versions are equal.
        local stable_tag, stable_url
        local stable_body = https_get(GITHUB_API_URL)
        if stable_body then
            stable_tag = json_str(stable_body, "tag_name")
            stable_url = extract_asset_url(stable_body)
        end
        logger.dbg("ZenUpdater: stable_tag=", stable_tag, "asset_url=", stable_url)

        local beta_tag, beta_url
        local list_body = https_get(GITHUB_RELEASES_URL .. "?per_page=10")
        if list_body then
            for obj in list_body:gmatch('%b{}') do
                if obj:find('"prerelease"%s*:%s*true') then
                    beta_tag = json_str(obj, "tag_name")
                    if beta_tag then
                        beta_url = extract_asset_url(obj)
                        break
                    end
                end
            end
        end
        logger.dbg("ZenUpdater: beta_tag=", beta_tag, "asset_url=", beta_url)

        -- Prefer beta only when strictly newer than stable.
        if beta_tag and semver_gt(beta_tag, stable_tag or "0.0.0") then
            logger.dbg("ZenUpdater: using beta (newer than stable)")
            tag    = beta_tag
            dl_url = beta_url
        elseif stable_tag then
            logger.dbg("ZenUpdater: using stable (beta not strictly newer)")
            tag    = stable_tag
            dl_url = stable_url
        else
            logger.dbg("ZenUpdater: no stable found, falling back to beta")
            tag    = beta_tag
            dl_url = beta_url
        end
    else
        local body = https_get(GITHUB_API_URL)
        if not body then
            logger.warn("ZenUpdater: no response from releases/latest")
            return false
        end
        tag    = json_str(body, "tag_name")
        dl_url = extract_asset_url(body)
        logger.dbg("ZenUpdater: stable tag=", tag, "asset_url=", dl_url)
    end

    if not tag then
        logger.warn("ZenUpdater: no tag found in API response")
        return false
    end
    M._latest_ver = tag:match("^v?(.+)$") or tag
    M._dl_url     = dl_url
    M._has_update = semver_gt(tag, current)
    logger.dbg("ZenUpdater: latest=", M._latest_ver, "has_update=", tostring(M._has_update))
    return true
end

--- Check for updates at most once every 24 h (throttled via G_reader_settings).
--- Silently falls back to the last cached result when offline or throttled.
function M.check_for_update()
    if M._checked then
        logger.dbg("ZenUpdater: already checked this session, skipping")
        return
    end
    M._checked = true

    local gs  = get_gs()
    local now = os.time()
    local last = gs and gs:readSetting(GS_KEY_TIME) or 0
    logger.dbg("ZenUpdater: check_for_update now=", now, "last=", last, "interval=", CHECK_INTERVAL)

    if type(last) == "number" and (now - last) < CHECK_INTERVAL then
        logger.dbg("ZenUpdater: within throttle window, loading cached state")
        load_cached_state()
        logger.dbg("ZenUpdater: cached has_update=", tostring(M._has_update), "latest=", tostring(M._latest_ver))
        return
    end

    -- Attempt a live check; if it fails, fall back to cached state.
    if not do_network_check() then
        logger.warn("ZenUpdater: live check failed, loading cached state")
        load_cached_state()
        return
    end

    persist_state(now)
end

--- Returns true when a newer release has been detected.
function M.has_update()
    return M._has_update == true
end

--- Returns the latest release version string (without leading "v"), or nil.
function M.latest_version()
    return M._latest_ver
end

--- Download the latest release.zip, unpack it over the plugin directory, and
--- prompt the user to restart KOReader.
function M.run_update(plugin)
    local UIManager   = require("ui/uimanager")
    local InfoMessage = require("ui/widget/infomessage")
    local ConfirmBox  = require("ui/widget/confirmbox")

    local plugin_root = PLUGIN_ROOT
        or (plugin and type(plugin.path) == "string" and plugin.path ~= "" and plugin.path)
        or ""

    if plugin_root == "" then
        UIManager:show(InfoMessage:new{
            text = _("Cannot determine the plugin installation path."),
        })
        return
    end

    local ver_label = M._latest_ver and ("v" .. M._latest_ver) or _("latest")
    -- The zip contains zen_ui.koplugin/ at root; unzip to the plugins dir.
    local plugins_dir = plugin_root:match("^(.*)/[^/]+$") or plugin_root

    UIManager:show(ConfirmBox:new{
        text = _("Update to Zen UI ") .. ver_label .. "?",
        ok_text     = _("Update"),
        cancel_text = _("Cancel"),
        ok_callback = function()
            local progress = InfoMessage:new{ text = _("Updating Zen UI…") }
            UIManager:show(progress)
            UIManager:forceRePaint()

            UIManager:scheduleIn(0.1, function()
                -- Fetch the asset URL if not cached; deferred so the progress
                -- dialog is visible before any blocking network call.
                if not is_valid_asset_url(M._dl_url) then
                    do_network_check()
                end

                if not is_valid_asset_url(M._dl_url) then
                    UIManager:close(progress)
                    UIManager:show(InfoMessage:new{
                        text = _("No zen_ui.koplugin.zip asset found for this release. Check the GitHub release page."),
                    })
                    return
                end

                -- Download outside the plugin dir (we will delete it next).
                local zip_path = plugins_dir .. "/zen_ui_update.zip"

                local ok, err = https_download(M._dl_url, zip_path)

                if not ok then
                    UIManager:close(progress)
                    UIManager:show(InfoMessage:new{
                        text = _("Download failed: ") .. (err or _("unknown error")),
                    })
                    return
                end

                -- Remove the old plugin dir entirely so renamed/moved files
                -- from previous versions don't persist. Lua modules are already
                -- loaded in memory so this is safe at runtime.
                local rm_rc = os.execute(string.format("rm -rf %q", plugin_root))
                if rm_rc ~= 0 and rm_rc ~= true then
                    os.remove(zip_path)
                    UIManager:close(progress)
                    UIManager:show(InfoMessage:new{
                        text = _("Failed to remove the existing plugin. Update aborted."),
                    })
                    return
                end

                -- Unzip into the plugins dir; creates a fresh zen_ui.koplugin/.
                local unzip_rc = os.execute(string.format("unzip -q %q -d %q", zip_path, plugins_dir))
                os.remove(zip_path)

                if unzip_rc ~= 0 and unzip_rc ~= true then
                    UIManager:close(progress)
                    UIManager:show(InfoMessage:new{
                        text = _("Failed to unpack the update. You may need to reinstall manually."),
                    })
                    return
                end

                -- Clear the notification so it doesn't re-appear after restart.
                clear_update_state()

                UIManager:close(progress)
                UIManager:show(InfoMessage:new{
                    text = _("Zen UI updated. Restarting…"),
                })
                UIManager:forceRePaint()
                UIManager:scheduleIn(1, function()
                    UIManager:broadcastEvent(require("ui/event"):new("Restart"))
                end)
            end)
        end,
    })
end

--- Returns a menu item for the top of the Zen UI settings page when an update
--- is available, or nil when no update has been detected.
function M.build_update_available_item(plugin)
    if not M._has_update then return nil end
    local ver_label = M._latest_ver and ("v" .. M._latest_ver) or _("latest")
    return {
        _zen_update_banner = true,  -- marker so root_items.callback can remove it
        text          = _("\u{F01B} Update available: ") .. ver_label,
        keep_menu_open = true,
        callback      = function()
            M.run_update(plugin)
        end,
    }
end

--- Returns the "Check for updates" menu item for the About section.
--- When a newer version has already been detected the text changes to reflect
--- the pending update and tapping it launches the download flow directly.
function M.build_update_now_item(plugin)
    return {
        text_func = function()
            if M._has_update then
                local ver_label = M._latest_ver and ("v" .. M._latest_ver) or _("latest")
                return _("\u{F01B} Update available: ") .. ver_label
            end
            return _("Check for updates")
        end,
        keep_menu_open = true,
        callback = function()
            local UIManager   = require("ui/uimanager")
            local InfoMessage = require("ui/widget/infomessage")

            -- Reset all in-memory state and clear the throttle timestamp so
            -- the next check_for_update() call goes straight to the network.
            M._checked    = false
            M._has_update = false
            M._latest_ver = nil
            M._dl_url     = nil
            local gs = get_gs()
            if gs then
                gs:saveSetting(GS_KEY_TIME, 0)
                pcall(gs.flush, gs)
            end

            -- Show feedback immediately so there are no artifacts while the
            -- blocking network call runs on Kobo's slower SSL stack.
            local checking = InfoMessage:new{ text = _("Checking for updates…") }
            UIManager:show(checking)
            UIManager:forceRePaint()

            UIManager:scheduleIn(0.1, function()
                M.check_for_update()
                UIManager:close(checking)

                if M._has_update then
                    M.run_update(plugin)
                else
                    UIManager:show(InfoMessage:new{
                        text    = _("Zen UI is up to date."),
                        timeout = 3,
                    })
                end
            end)
        end,
    }
end

--- Returns the active update channel: "stable" (default) or "beta".
function M.get_channel()
    return get_channel()
end

--- Set the update channel and reset cached state so the next check uses it.
function M.set_channel(ch)
    local gs = get_gs()
    if not gs then return end
    gs:saveSetting(GS_KEY_CHANNEL, ch == "beta" and "beta" or "stable")
    pcall(gs.flush, gs)
    -- Invalidate cache so next check_for_update() goes to the network.
    M._checked    = false
    M._has_update = false
    M._latest_ver = nil
    M._dl_url     = nil
    gs:saveSetting(GS_KEY_TIME, 0)
    pcall(gs.flush, gs)
end

--- Returns a radio-style "Update channel" sub-menu item for the About section.
function M.build_channel_item()
    return {
        text = _("Update channel"),
        sub_item_table = {
            {
                text = _("Stable"),
                checked_func = function() return get_channel() == "stable" end,
                callback = function() M.set_channel("stable") end,
            },
            {
                text = _("Beta"),
                checked_func = function() return get_channel() == "beta" end,
                callback = function() M.set_channel("beta") end,
            },
        },
    }
end

return M
