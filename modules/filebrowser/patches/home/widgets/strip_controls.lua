local Background = require("common/ui/background")
local Blitbuffer = require("ffi/blitbuffer")
local ButtonModel = require("common/nav_button_model")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local InputContainer = require("ui/widget/container/inputcontainer")
local LineWidget = require("ui/widget/linewidget")
local TextWidget = require("ui/widget/textwidget")
local WidgetResources = require("common/widget_resources")
local icons = require("common/inline_icon_map")

local M = {}

local function visible_entries(controls)
    local entries = {}
    local seen = {}
    for _i, id in ipairs(controls.order or {}) do
        if #entries >= 7 then break end
        local entry = not seen[id] and controls.show_buttons[id] == true
            and ButtonModel.find(controls, id) or nil
        if entry then
            entries[#entries + 1] = entry
            seen[id] = true
        end
    end
    return entries
end

local function fit_face(labels, width, maximum, minimum)
    local size = maximum or Device.screen:scaleBySize(10)
    minimum = minimum or Device.screen:scaleBySize(7)
    while size > minimum do
        local face = Font:getFace("smallinfofont", size)
        local fits = true
        for _i, label in ipairs(labels) do
            local probe = TextWidget:new{ text = label, face = face }
            local needed = probe:getSize().w
            WidgetResources.free(probe)
            if needed > width - Device.screen:scaleBySize(6) then
                fits = false
                break
            end
        end
        if fits then return face end
        size = size - 1
    end
    return Font:getFace("smallinfofont", minimum)
end

local function control_widget(content, width, height, tap_callback, hold_callback)
    if not Device:isTouchDevice() then return content end
    local ges_events = {
        TapStripControl = {
            GestureRange:new{ ges = "tap", range = Geom:new{
                x = 0, y = 0, w = Device.screen:getWidth(), h = Device.screen:getHeight(),
            } },
        },
    }
    if type(hold_callback) == "function" then
        ges_events.HoldStripControl = {
            GestureRange:new{ ges = "hold", range = Geom:new{
                x = 0, y = 0, w = Device.screen:getWidth(), h = Device.screen:getHeight(),
            } },
        }
    end
    local input = InputContainer:new{
        dimen = Geom:new{ w = width, h = height },
        ges_events = ges_events,
    }
    input.onTapStripControl = function(self, _arg, ges)
        if not (self.dimen and ges and ges.pos and self.dimen:contains(ges.pos)) then
            return false
        end
        tap_callback()
        return true
    end
    if type(hold_callback) == "function" then
        input.onHoldStripControl = function(self, _arg, ges)
            if not (self.dimen and ges and ges.pos and self.dimen:contains(ges.pos)) then
                return false
            end
            return hold_callback() == true
        end
    end
    input[1] = content
    return input
end

function M.build(opts)
    local controls = opts.controls
    local entries = visible_entries(controls)
    local height = opts.height
    local border_size = math.max(2, Device.screen:scaleBySize(1))
    local inner_width = math.max(1, opts.width - border_size * 2)
    local inner_height = math.max(1, height - border_size * 2)
    local divider_size = math.max(1, Device.screen:scaleBySize(1))
    local divider_width = math.max(0, #entries - 1) * divider_size
    local search_count = 0
    for _i, entry in ipairs(entries) do
        if entry.id == "search" then search_count = search_count + 1 end
    end
    local label_count = #entries - search_count
    local search_padding_x = Device.screen:scaleBySize(4)
    local search_width = label_count == 0 and inner_width
        or math.min(inner_height + search_padding_x * 2, inner_width)
    local button_area = math.max(0,
        inner_width - search_width * search_count - divider_width)
    local button_width = label_count > 0 and math.floor(button_area / label_count) or 0
    local remainder = label_count > 0 and button_area - button_width * label_count or 0
    local labels = {}
    for _i, entry in ipairs(entries) do
        if entry.id ~= "search" then
            labels[#labels + 1] = ButtonModel.label(controls, entry)
        end
    end
    local face = fit_face(labels, math.max(1, button_width))
    local row = HorizontalGroup:new{ align = "center" }
    local targets = {}
    local radius = Device.screen:scaleBySize(4)
    local side_padding = Device.screen:scaleBySize(4)
    local label_index = 0

    for index, entry in ipairs(entries) do
        local is_search = entry.id == "search"
        if not is_search then label_index = label_index + 1 end
        local cell_width = is_search and search_width
            or button_width + (label_index <= remainder and 1 or 0)
        local active = entry.id == opts.active_id
        local content
        if is_search then
            content = CenterContainer:new{
                dimen = Geom:new{ w = cell_width, h = inner_height },
                TextWidget:new{
                    text = icons.search,
                    face = Font:getFace("smallinfofont", Device.screen:scaleBySize(11)),
                    padding = 0,
                },
            }
        else
            local label = entry.id == opts.active_id and opts.active_group
                or labels[label_index]
            local label_face = face
            if entry.id == opts.active_id and opts.active_group then
                local base_size = face.orig_size or face.size or Device.screen:scaleBySize(10)
                label_face = fit_face({ label }, cell_width, base_size,
                    math.max(Device.screen:scaleBySize(7), base_size - 1))
            end
            content = FrameContainer:new{
                width = cell_width,
                height = inner_height,
                padding = 0,
                bordersize = 0,
                background = active and Blitbuffer.COLOR_BLACK
                    or Background.tile_bg(Blitbuffer.COLOR_WHITE),
                CenterContainer:new{
                    dimen = Geom:new{ w = cell_width, h = inner_height },
                    TextWidget:new{
                        text = label,
                        face = label_face,
                        padding = 0,
                        max_width = math.max(1, cell_width - side_padding * 2),
                        truncate_with_ellipsis = true,
                        fgcolor = active and Blitbuffer.COLOR_WHITE or Blitbuffer.COLOR_BLACK,
                    },
                },
            }
        end
        local activate = function()
            if ButtonModel.isSource(entry) then
                return opts.on_source(entry)
            end
            return opts.on_action(entry)
        end
        local context = type(opts.on_hold) == "function" and function()
            return opts.on_hold(entry)
        end or nil
        local widget = control_widget(
            content, cell_width, inner_height, activate, context)
        if type(opts.prepare_focus) == "function" then
            local target = {
                key = "strip-control:" .. tostring(entry.id),
                subrow = 0,
                col = index,
                width = cell_width,
                height = inner_height,
                focus_color = active and Blitbuffer.COLOR_WHITE
                    or Blitbuffer.COLOR_BLACK,
                activate = activate,
                context = context,
            }
            widget = opts.prepare_focus(target, widget)
            targets[#targets + 1] = target
        end
        row[#row + 1] = widget
        if index < #entries then
            row[#row + 1] = LineWidget:new{
                dimen = Geom:new{ w = divider_size, h = inner_height },
                background = Blitbuffer.COLOR_BLACK,
            }
        end
    end
    local outer = FrameContainer:new{
        width = opts.width,
        height = height,
        padding = 0,
        bordersize = border_size,
        color = Blitbuffer.COLOR_BLACK,
        radius = radius,
        background = Background.tile_bg(Blitbuffer.COLOR_WHITE),
        row,
    }
    return outer, targets
end

return M
