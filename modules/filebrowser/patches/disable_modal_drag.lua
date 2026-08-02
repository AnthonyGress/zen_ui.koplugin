local function apply_disable_modal_drag()
    --[[
        Prevents every MovableContainer from being dragged.
        Sets unmovable=true on init (suppresses ges_events) and no-ops
        all onMovable* methods at the class level (for direct-call widgets).
    ]]
    local MovableContainer = require("ui/widget/container/movablecontainer")

    if MovableContainer._zen_no_drag_patched then return end
    MovableContainer._zen_no_drag_patched = true

    -- 1. Force unmovable on every new instance so init() skips ges_events.
    local orig_init = MovableContainer.init
    MovableContainer.init = function(self, ...)
        self.unmovable = true
        return orig_init(self, ...)
    end

    -- 2. No-op all movement methods so direct calls from widgets like
    --    TextViewer also have no effect.
    local noop = function() end
    MovableContainer.onMovableTouch       = noop
    MovableContainer.onMovableSwipe       = noop
    MovableContainer.onMovableHold        = noop
    MovableContainer.onMovableHoldPan     = noop
    MovableContainer.onMovableHoldRelease = noop
    MovableContainer.onMovablePan         = noop
    MovableContainer.onMovablePanRelease  = noop
end

return apply_disable_modal_drag
