-- Displays a slim 3-2-1 countdown bar at the bottom of the screen, then
-- takes a screenshot and shows the standard save dialog.
-- Uses toast = true so UIManager never stops event propagation at this widget;
-- taps/swipes pass through to the UI below.
--
-- Usage:
--   require("common/countdown_screenshot").run()

local BD               = require("ui/bidi")
local Blitbuffer       = require("ffi/blitbuffer")
local ButtonDialog     = require("ui/widget/buttondialog")
local CenterContainer  = require("ui/widget/container/centercontainer")
local DataStorage      = require("datastorage")
local Font             = require("ui/font")
local FrameContainer   = require("ui/widget/container/framecontainer")
local Geom             = require("ui/geometry")
local TextWidget       = require("ui/widget/textwidget")
local UIManager        = require("ui/uimanager")
local WidgetContainer  = require("ui/widget/container/widgetcontainer")
local Screen           = require("device").screen
local util             = require("util")
local _                = require("gettext")
local icons            = require("common/inline_icon_map")

local M = {}

-- Returns the LocalSend plugin instance if loaded, nil otherwise.
local function getLocalsendPlugin()
    local ok_f, FM = pcall(require, "apps/filemanager/filemanager")
    local ok_r, RU = pcall(require, "apps/reader/readerui")
    local ui = (ok_f and FM.instance) or (ok_r and RU.instance)
    return ui and ui.localsend or nil
end

-- Slim passthrough bar pinned to the bottom of the screen.
-- toast = true tells UIManager to forward events through this widget
-- without stopping propagation, so taps/swipes still reach the UI below.
local CountdownBar = WidgetContainer:extend{ toast = true }

function CountdownBar:init()
    local screen_w = Screen:getWidth()
    -- Match the zen status bar height (icon_size from status_bar.lua)
    local bar_h    = Screen:scaleBySize(35)
    self.dimen = Geom:new{ x = 0, y = 0, w = screen_w, h = bar_h }
    self[1] = FrameContainer:new{
        width      = screen_w,
        height     = bar_h,
        background = Blitbuffer.COLOR_BLACK,
        bordersize = 0,
        padding    = 0,
        CenterContainer:new{
            dimen = Geom:new{ w = screen_w, h = bar_h },
            TextWidget:new{
                text    = self.count,
                face    = Font:getFace("infofont", Screen:scaleBySize(13)),
                fgcolor = Blitbuffer.COLOR_WHITE,
            },
        },
    }
end

local function show_save_dialog(screenshot_name)
    local dialog
    -- Each button in its own row so all render at equal full width.
    local buttons = {
        {
            {
                text     = icons.display .. "  " .. _("View"),
                align    = "left",
                callback = function()
                    local ImageViewer = require("ui/widget/imageviewer")
                    UIManager:show(ImageViewer:new{
                        file            = screenshot_name,
                        modal           = true,
                        with_title_bar  = false,
                        buttons_visible = true,
                    })
                end,
            },
        },
    }
    --[[ Set as wallpaper (disabled)
    if Device:supportsScreensaver() then
        table.insert(buttons, {
            {
                text = icons.wallpaper .. "  " .. _("Set as wallpaper"),
                callback = function()
                    G_reader_settings:saveSetting("screensaver_type", "document_cover")
                    G_reader_settings:saveSetting("screensaver_document_cover", screenshot_name)
                    UIManager:close(dialog)
                end,
            },
        })
    end
    --]]
    local ls = getLocalsendPlugin()
    if ls then
        table.insert(buttons, {
            {
                text     = icons.send .. "  " .. _("Send with LocalSend"),
                align    = "left",
                callback = function()
                    UIManager:close(dialog)
                    ls:openFirewall()
                    -- Use the already-loaded sender module directly to pass the
                    -- filepath, bypassing the no-arg wrapper LocalSend:showFileSendFlow().
                    local lssender = package.loaded["localsend_sender"]
                    if lssender then
                        lssender.showFileSendFlow(ls, screenshot_name)
                    end
                end,
            },
        })
    end
    table.insert(buttons, {
        {
            text     = icons.delete .. "  " .. _("Delete"),
            align    = "left",
            callback = function()
                os.remove(screenshot_name)
                UIManager:close(dialog)
            end,
        },
    })
    dialog = ButtonDialog:new{
        title   = _("Screenshot saved to:") .. "\n\n" .. BD.filepath(screenshot_name) .. "\n",
        modal   = true,
        buttons = buttons,
    }
    UIManager:show(dialog)
    UIManager:setDirty(nil, "full")
end

-- Run the 3-2-1 countdown, take the screenshot, then show the save dialog.
function M.run()
    local current_bar

    local function close_bar()
        if current_bar then
            UIManager:close(current_bar)
            UIManager:setDirty(nil, "ui")
            current_bar = nil
        end
    end

    local function do_shot()
        close_bar()
        UIManager:scheduleIn(0.05, function()
            local screenshot_dir = DataStorage:getFullDataDir() .. "/screenshots"
            util.makePath(screenshot_dir)
            local name = os.date(screenshot_dir .. "/Screenshot_%Y-%m-%d_%H%M%S.png")
            Screen:shot(name)
            show_save_dialog(name)
        end)
    end

    local function show_count(n, next_fn)
        close_bar()
        current_bar = CountdownBar:new{ count = tostring(n) }
        UIManager:show(current_bar)
        UIManager:setDirty(current_bar, "ui")
        UIManager:scheduleIn(1, next_fn)
    end

    show_count(3, function()
        show_count(2, function()
            show_count(1, do_shot)
        end)
    end)
end

return M
