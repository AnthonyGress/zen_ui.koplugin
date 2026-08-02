local ModalBorder = {}

-- FrameContainer reads this preference while painting its border.
local modal_paint_depth = 0

local function install_override()
    local settings = G_reader_settings
    if not settings or type(settings.nilOrTrue) ~= "function" then return false end
    if settings._zen_modal_border_override then return true end

    local orig_nil_or_true = settings.nilOrTrue
    settings.nilOrTrue = function(self, key, ...)
        if key == "anti_alias_ui" and modal_paint_depth > 0 then
            return false
        end
        return orig_nil_or_true(self, key, ...)
    end
    settings._zen_modal_border_override = true
    return true
end

function ModalBorder.apply(frame)
    if not frame or frame._zen_modal_border_override or type(frame.paintTo) ~= "function" then return end
    if not install_override() then return end

    local orig_paint_to = frame.paintTo
    frame._zen_modal_border_override = true
    frame.paintTo = function(self, ...)
        modal_paint_depth = modal_paint_depth + 1
        local results = { pcall(orig_paint_to, self, ...) }
        modal_paint_depth = modal_paint_depth - 1
        if not results[1] then error(results[2], 0) end
        return unpack(results, 2)
    end
end

return ModalBorder
