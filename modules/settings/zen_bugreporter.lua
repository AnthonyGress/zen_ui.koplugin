-- settings/zen_bugreporter.lua
-- "Report a Bug" flow: reads crash.log, prompts for title/description,
-- then POSTs a GitHub issue with the log embedded as a collapsible block.
-- Rate-limited to one successful submission per 30 minutes.

local JSON = require("json")
local _ = require("gettext")
local logger = require("logger")
local UIManager = require("ui/uimanager")

local PROXY_URL     = "https://zen-reporter.misty-mud-afb2.workers.dev/"
local MAX_CRASH_LOG = 60000
local MAX_TITLE     = 250  -- 256 - len("[BUG] ")
local MAX_BODY      = 65536

local M = {}

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------


--- POST JSON to url. Returns http_code, response_body_str.
local function https_post_json(url, payload_str)
    local ok_ssl, https = pcall(require, "ssl.https")
    local ok_ltn, ltn12 = pcall(require, "ltn12")
    if not ok_ssl or not ok_ltn then
        return nil, "ssl.https / ltn12 not available"
    end

    local resp = {}
    local _, code = https.request{
        url    = url,
        method = "POST",
        headers = {
            ["User-Agent"]     = "zen_ui.koplugin",
            ["Content-Type"]   = "application/json",
            ["Content-Length"] = tostring(#payload_str),
        },
        source = ltn12.source.string(payload_str),
        sink   = ltn12.sink.table(resp),
    }
    return code, table.concat(resp)
end

--- Read up to `max_chars` bytes from the end of a file. Returns string or nil.
local function read_log(path, max_chars)
    local f = io.open(path, "rb")
    if not f then return nil end
    local size = f:seek("end", 0)
    local offset = math.max(0, size - max_chars)
    f:seek("set", offset)
    local data = f:read("*a")
    f:close()
    if offset > 0 then
        data = "[truncated - showing last " .. max_chars .. " chars of " .. size .. " total]\n" .. data
    end
    return data
end

-- ---------------------------------------------------------------------------
-- Issue body builder (mirrors the existing bug_report.md template)
-- ---------------------------------------------------------------------------

local function build_issue_body(description, system_info, crash_log, github_username)
    local parts = {}

    parts[#parts+1] = "**Describe the bug**"
    parts[#parts+1] = (description ~= "" and description or "_No description provided._")
    parts[#parts+1] = ""

    parts[#parts+1] = "**Environment**"
    parts[#parts+1] = system_info
    parts[#parts+1] = ""

    -- Collapsible block keeps the issue readable when the log is large.
    parts[#parts+1] = "<details>"
    parts[#parts+1] = "<summary>crash.log</summary>"
    parts[#parts+1] = ""
    parts[#parts+1] = "```"
    parts[#parts+1] = crash_log or "_crash.log not found_"
    parts[#parts+1] = "```"
    parts[#parts+1] = "</details>"
    parts[#parts+1] = ""
    if github_username and github_username ~= "" then
        parts[#parts+1] = "**Reported by:** @" .. github_username
        parts[#parts+1] = ""
    end
    parts[#parts+1] = "_Submitted via Zen UI in-app bug reporter._"

    return table.concat(parts, "\n")
end

-- ---------------------------------------------------------------------------
-- Network submission
-- ---------------------------------------------------------------------------

local function submit_issue(title, body)
    local payload = JSON.encode({ title = title, body = body, labels = { "bug" } })

    logger.dbg("ZenBugReporter: POSTing to proxy:", PROXY_URL)
    local code, resp = https_post_json(PROXY_URL, payload)
    logger.dbg("ZenBugReporter: response code:", code)

    if code == 201 then
        local url = resp and resp:match('"url"%s*:%s*"([^"]+)"')
        return url or "https://github.com/AnthonyGress/zen_ui.koplugin/issues"
    elseif code == 429 then
        return nil, _("Too many requests. Please try again later.")
    else
        local msg = "HTTP " .. tostring(code)
        local gh_msg = resp and resp:match('"message"%s*:%s*"([^"]+)"')
        if gh_msg then msg = msg .. " - " .. gh_msg end
        return nil, msg
    end
end

-- ---------------------------------------------------------------------------
-- Public: show_dialog
-- ---------------------------------------------------------------------------

function M.show_dialog(ctx)
    -- Require debug logging to be on so crash.log is useful.
    if not (G_reader_settings and G_reader_settings:isTrue("debug_verbose")) then
        local ConfirmBox = require("ui/widget/confirmbox")
        UIManager:show(ConfirmBox:new{
            text        = _("Debug logging must be enabled to submit bug reports.")
                       .. "\n\n"
                       .. _("Enabling debug logging, restart required. Please reproduce the issue, then submit the report."),
            ok_text     = _("Restart now"),
            cancel_text = _("Cancel"),
            ok_callback = function()
                G_reader_settings:saveSetting("debug_verbose", true)
                G_reader_settings:flush()
                UIManager:restartKOReader()
            end,
        })
        return
    end

    -- Network check
    local ok_nm, NetworkMgr = pcall(require, "ui/network/manager")
    if ok_nm and NetworkMgr and type(NetworkMgr.isOnline) == "function" then
        if not NetworkMgr:isOnline() then
            local InfoMessage = require("ui/widget/infomessage")
            UIManager:show(InfoMessage:new{
                text = _("No network connection. Please connect to Wi-Fi and try again."),
            })
            return
        end
    end

    local ConfirmBox = require("ui/widget/confirmbox")
    UIManager:show(ConfirmBox:new{
        text    = _("crash.log will be embedded in a public GitHub issue. It may contain file paths and book titles.") .. ("\n\n") .. ("Continue?"),
        ok_text = _("Continue"),
        ok_callback = function()
            M._ask_title(ctx)
        end,
    })
end

function M._ask_title(ctx)
    local InputDialog = require("ui/widget/inputdialog")
    local dlg
    dlg = InputDialog:new{
        title       = _("Bug report title"),
        description = _("A short summary of what went wrong"),
        input       = "",
        input_hint  = _("Brief description of the bug"),
        buttons = {{
            {
                text = _("Cancel"),
                id   = "close",
                callback = function() UIManager:close(dlg) end,
            },
            {
                text             = _("Next"),
                is_enter_default = true,
                callback = function()
                    local title = dlg:getInputText()
                    if not title or title:match("^%s*$") then return end
                    title = title:match("^%s*(.-)%s*$")
                    UIManager:close(dlg)
                    M._ask_description(ctx, title)
                end,
            },
        }},
    }
    UIManager:show(dlg)
    dlg:onShowKeyboard()
end

function M._ask_description(ctx, bug_title)
    local InputDialog = require("ui/widget/inputdialog")
    local dlg
    dlg = InputDialog:new{
        title       = _("Bug description (optional)"),
        description = _("Steps to reproduce, expected vs. actual behavior"),
        input       = "",
        input_type  = "text",
        buttons = {{
            {
                text = _("Cancel"),
                id   = "close",
                callback = function() UIManager:close(dlg) end,
            },
            {
                text             = _("Submit"),
                is_enter_default = true,
                callback = function()
                    local desc = dlg:getInputText() or ""
                    desc = desc:match("^%s*(.-)%s*$") or ""
                    UIManager:close(dlg)
                    M._ask_github(ctx, bug_title, desc)
                end,
            },
        }},
    }
    UIManager:show(dlg)
    dlg:onShowKeyboard()
end

function M._ask_github(ctx, bug_title, description)
    local InputDialog = require("ui/widget/inputdialog")
    local dlg
    dlg = InputDialog:new{
        title       = _("GitHub username (optional)"),
        description = _("Enter your GitHub username to be tagged in the issue"),
        input       = "",
        input_hint  = _("username"),
        buttons = {{
            {
                text = _("Skip"),
                id   = "close",
                callback = function()
                    UIManager:close(dlg)
                    M._do_submit(ctx, bug_title, description, "")
                end,
            },
            {
                text             = _("Submit"),
                is_enter_default = true,
                callback = function()
                    local username = dlg:getInputText() or ""
                    username = username:match("^%s*(.-)%s*$") or ""
                    -- Strip leading @ if user typed it
                    username = username:match("^@?(.*)$") or ""
                    UIManager:close(dlg)
                    M._do_submit(ctx, bug_title, description, username)
                end,
            },
        }},
    }
    UIManager:show(dlg)
    dlg:onShowKeyboard()
end

function M._do_submit(ctx, bug_title, description, github_username)
    local InfoMessage = require("ui/widget/infomessage")

    -- Show "Submitting…" then do network work on the next tick so the UI updates first.
    local spinner = InfoMessage:new{ text = _("Submitting report…") }
    UIManager:show(spinner)

    UIManager:nextTick(function()
        -- Gather system info.
        local ok_u, sutils = pcall(require, "modules/settings/zen_settings_utils")
        local plugin = ctx and ctx.plugin
        local zen_ver  = ok_u and sutils.get_plugin_version(plugin)  or "?"
        local ko_ver   = ok_u and sutils.get_koreader_version()       or "?"
        local device   = ok_u and sutils.get_device_model_name()      or "?"
        local firmware = ok_u and sutils.get_device_firmware_display() or "?"
        local system_info = "- Zen UI: " .. zen_ver
                         .. "\n- KOReader: " .. ko_ver
                         .. "\n- Device: " .. device
                         .. (firmware ~= "n/a" and ("\n- Firmware: " .. firmware) or "")

        -- Read crash.log from the KOReader data directory.
        local ok_ds, DataStorage = pcall(require, "datastorage")
        local data_dir = ok_ds and DataStorage:getDataDir() or nil
        local crash_log = data_dir and read_log(data_dir .. "/crash.log", MAX_CRASH_LOG)

        local issue_title = ("[BUG] " .. bug_title):sub(1, MAX_TITLE + 6)
        local issue_body  = build_issue_body(description, system_info, crash_log, github_username)
        if #issue_body > MAX_BODY then
            issue_body = issue_body:sub(1, MAX_BODY - 16) .. "\n...[truncated]"
        end

        local issue_url, err = submit_issue(issue_title, issue_body)

        UIManager:close(spinner)

        if issue_url then
            local ConfirmBox = require("ui/widget/confirmbox")
            UIManager:show(ConfirmBox:new{
                text          = _("Bug report submitted!") .. "\n\n" .. issue_url,
                no_ok_button  = true,
                cancel_text   = _("OK"),
            })
        else
            UIManager:show(InfoMessage:new{
                text = _("Failed to submit report: ") .. (err or "unknown error"),
            })
        end
    end)
end

return M
