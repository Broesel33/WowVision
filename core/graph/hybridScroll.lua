local graph = WowVision.graph
local nodes = graph.nodes
local ControlId = graph.ControlId
local kinds = graph.kinds

-- The button-pool scroll adapter (HybridScrollFrame and kin): a fixed pool of
-- row buttons over an API-enumerable list, like the quest log. Focusing an
-- entry scrolls it to a calibrated position, which re-stamps the button pool
-- synchronously; the landing is then VERIFIED by finding the button whose
-- index matches, and the scroll rolls back if none does. Buttons rebind as
-- the pool scrolls, so an index-to-button mapping is only ever trusted
-- immediately after verifying it.
--
-- TAINT: our SetValue runs the frame's update handler (which stamps row
-- fields like button.index) inside OUR insecure stack, so every scroll
-- taints the pool's stamps until Blizzard's own code re-runs the update --
-- and the tainted OFFSET field then re-taints even Blizzard's own secure
-- refreshes, persistently. Defenses, in order:
--   1. An already-visible verified target skips the scroll write entirely
--      (findButton IS the verification, so the mapping guarantee holds).
--   2. Rows at the visible edge shadow the arrow key with a SECURE click
--      of the scrollbar's real arrow button (helpers.edgeBindings): the
--      hardware keypress scrolls through Blizzard's own handler, keeping
--      the offset and every re-stamped field clean -- and HEALING any
--      prior taint, since the secure write re-blesses the slots. The
--      postClick then moves focus normally; the target row is visible by
--      then, so defense 1 skips the insecure write.
--   3. Home/End jumps fire ONE macrotext of repeated secure arrow clicks
--      (the slider clamps at its ends, so slack clicks are free) when the
--      whole distance fits the macro budget.
--   4. When an insecure SetValue was unavoidable (a jump too far for the
--      macro budget), the list is marked poisoned and EVERY row's arrows
--      go secure until the next arrow press heals the offset, whatever
--      row it happens on.
--   5. onScrolled lets callers trigger a secure re-stamp (an event that
--      makes Blizzard refresh the list itself) after a fallback scroll.
--
-- config:
--   scrollFrame  the scroll frame (required; needs a scrollBar and a pool in
--                .buttons, else the scroll child's children)
--   count        function -> number of logical entries (required)
--   emit         function(builder, index, helpers) -- emit the entry's nodes
--                (required). helpers = { onFocus, onFocusTick, target, id,
--                edgeBindings }. Concat edgeBindings (may be nil) into the
--                row vtable's bindings so edge rows scroll securely.
--   key          stable prefix for default ids (default "hybrid")
--   label        announcement context wrapped around the entries
--   id           function(index) -> ControlId; default structural key:index
--   rowHeight    pixels per row; defaults to the frame's buttonHeight, else
--                the first pooled button's height
--   buttons      function -> the button pool, for frames whose pool is not
--                discoverable (FauxScrollFrames with named sibling buttons)
--   indexOf      function(button) -> the button's LOGICAL index, for pools
--                whose IDs are pool-relative (TBC-era Faux rows carry slot
--                ids; logical index is id plus the frame's scroll offset)
--   offsetOf     function(index) -> the entry's pixel offset from the top,
--                for variable-height lists (the friends list mixes 34px
--                rows with 16px dividers); overrides the rowHeight math
--   onScrolled   function() called after this adapter actually moved the
--                scrollbar (tainting the pool's stamps -- see above); use
--                it to request a secure refresh of the list
function nodes.hybridScrollList(builder, config)
    local scrollFrame = config.scrollFrame
    if scrollFrame == nil then
        error("hybridScrollList requires a scrollFrame")
    end
    if config.count == nil or config.emit == nil then
        error("hybridScrollList requires count and emit")
    end

    local keyPrefix = tostring(config.key or "hybrid")

    -- An empty list is still a place to land.
    local total = config.count()
    if total == nil or total <= 0 then
        if config.label ~= nil then
            builder:pushContext(keyPrefix, config.label)
        end
        builder:addItem(
            ControlId.structural(keyPrefix .. ":empty"),
            nodes.text({ label = WowVision:getLocale()["Empty"] })
        )
        if config.label ~= nil then
            builder:popContext()
        end
        return builder
    end

    local function buttonsOf()
        if config.buttons ~= nil then
            return config.buttons()
        end
        if scrollFrame.buttons ~= nil then
            return scrollFrame.buttons
        end
        local scrollChild = scrollFrame.GetScrollChild ~= nil and scrollFrame:GetScrollChild() or nil
        if scrollChild ~= nil then
            return { scrollChild:GetChildren() }
        end
        return {}
    end

    local function rowHeight()
        if config.rowHeight ~= nil then
            return config.rowHeight
        end
        if scrollFrame.buttonHeight ~= nil then
            return scrollFrame.buttonHeight
        end
        local buttons = buttonsOf()
        if buttons[1] ~= nil then
            return buttons[1]:GetHeight()
        end
        return 16
    end

    local function indexOfButton(button)
        if config.indexOf ~= nil then
            return config.indexOf(button)
        end
        return button.index or button:GetID()
    end

    local function findButton(index)
        for _, button in ipairs(buttonsOf()) do
            if button:IsShown() and indexOfButton(button) == index then
                return button
            end
        end
        return nil
    end

    local function scrollBarOf()
        if scrollFrame.scrollBar ~= nil then
            return scrollFrame.scrollBar
        end
        if scrollFrame.ScrollBar ~= nil then
            return scrollFrame.ScrollBar
        end
        -- FauxScrollFrames name their bar as a global with no key.
        if scrollFrame.GetName ~= nil and scrollFrame:GetName() ~= nil then
            return _G[scrollFrame:GetName() .. "ScrollBar"]
        end
        return nil
    end

    local function scrollToIndex(index)
        -- Already visible and verified: skip the scroll write (and the
        -- taint it would plant).
        if findButton(index) ~= nil then
            return
        end
        local scrollBar = scrollBarOf()
        if scrollBar == nil then
            return
        end
        local scrollChild = scrollFrame.GetScrollChild ~= nil and scrollFrame:GetScrollChild() or nil
        local buttons = buttonsOf()
        if scrollChild == nil or buttons[1] == nil then
            return
        end
        local childTop = scrollChild:GetTop()
        local buttonTop = buttons[1]:GetTop()
        if childTop == nil or buttonTop == nil then
            return
        end
        local original = scrollBar:GetValue()
        -- The pool's pixel baseline within the scroll child. Hybrid pools are
        -- parented to the child and ride it, so the measured gap is constant;
        -- Faux-style static pools sit still while the child slides under
        -- them, so the measured gap shifts by the current scroll value.
        local baseline = childTop - buttonTop
        if buttons[1]:GetParent() ~= scrollChild then
            baseline = baseline + original
        end
        local pixels
        if config.offsetOf ~= nil then
            pixels = config.offsetOf(index)
        else
            pixels = rowHeight() * (index - 1)
        end
        scrollBar:SetValue(baseline + pixels)
        local landed = findButton(index) ~= nil
        if not landed then
            scrollBar:SetValue(original)
        end
        -- The pool was re-stamped in our stack: the offset and row fields
        -- are tainted until a secure arrow click rewrites them. Flag it so
        -- rows force secure arrows until then, and give the caller its
        -- chance to schedule a secure re-stamp.
        scrollFrame.__wvScrollTainted = true
        if config.onScrolled ~= nil then
            pcall(config.onScrolled)
        end
    end

    if config.label ~= nil then
        builder:pushContext(keyPrefix, config.label)
    end

    -- Which logical indices are visible right now, computed once per render
    -- for the edge-binding checks below.
    local visible = {}
    for _, button in ipairs(buttonsOf()) do
        if button ~= nil and button:IsShown() then
            local ok, buttonIndex = pcall(indexOfButton, button)
            if ok and buttonIndex ~= nil then
                visible[buttonIndex] = true
            end
        end
    end

    -- The scrollbar's real arrow buttons, for secure edge scrolling.
    -- Hybrid arrows only scroll on the DOWN press ("/click name btn 1");
    -- Faux-era arrows respond to a plain click.
    local scrollBar = scrollBarOf()
    local clickSuffix = scrollFrame.buttons ~= nil and " LeftButton 1" or " LeftButton"
    local function arrowScript(which)
        if scrollBar == nil then
            return nil
        end
        local arrow = scrollBar[which]
        if arrow == nil and scrollBar.GetName ~= nil and scrollBar:GetName() ~= nil then
            arrow = _G[scrollBar:GetName() .. which]
        end
        if arrow == nil or arrow.GetName == nil or arrow:GetName() == nil then
            return nil
        end
        return "/click " .. arrow:GetName() .. clickSuffix
    end

    -- An insecure scroll happened and no secure arrow click has run since:
    -- force secure arrows on every row until one heals the offset.
    local poisoned = scrollFrame.__wvScrollTainted == true

    -- Pixels one arrow click covers, for sizing Home/End macros.
    local function stepPixels()
        if scrollFrame.buttons ~= nil then
            return scrollFrame.stepSize or scrollFrame.buttonHeight or rowHeight()
        end
        if scrollBar == nil then
            return rowHeight()
        end
        return scrollBar.scrollStep or (scrollBar:GetHeight() / 2)
    end

    -- Home/End as ONE secure keypress: enough arrow clicks to cover the
    -- whole distance, plus slack -- the slider clamps at its ends, so
    -- overshooting lands exactly. Returns nil when already there, when the
    -- macro budget cannot fit the trip (the insecure fallback then runs
    -- and poison mode takes over), or when the bar is unusable.
    local function jumpSpec(which, keymap)
        local line = arrowScript(which)
        if line == nil or scrollBar == nil or scrollBar.GetValue == nil then
            return nil
        end
        local value = scrollBar:GetValue()
        local minValue, maxValue = scrollBar:GetMinMaxValues()
        local distance
        if which == "ScrollUpButton" then
            distance = value - (minValue or 0)
        else
            distance = (maxValue or 0) - value
        end
        if distance <= 0 then
            return nil
        end
        local step = stepPixels()
        if step == nil or step <= 0 then
            return nil
        end
        local clicks = math.ceil(distance / step) + 2
        local text = string.rep(line .. "\n", clicks)
        if #text > 1000 then
            return nil
        end
        return {
            binding = keymap,
            type = "Script",
            script = text,
            postClick = function()
                scrollFrame.__wvScrollTainted = nil
                WowVision.graphHost:onKey(keymap)
            end,
        }
    end

    local homeSpec = not visible[1] and jumpSpec("ScrollUpButton", "home") or nil
    local endSpec = not visible[total] and jumpSpec("ScrollDownButton", "end") or nil

    for index = 1, total do
        local capturedIndex = index

        local id
        if config.id ~= nil then
            id = config.id(capturedIndex)
        else
            id = ControlId.structural(keyPrefix .. ":" .. capturedIndex)
        end

        local onFocus = function()
            pcall(scrollToIndex, capturedIndex)
        end

        -- Stateless per-tick re-align: if the entry scrolled out from under
        -- focus, pull it back. The host's click-drift watch handles
        -- re-engaging bindings when the frame mapping shifts.
        local onFocusTick = function()
            if findButton(capturedIndex) == nil then
                pcall(scrollToIndex, capturedIndex)
            end
        end

        local target = function()
            return findButton(capturedIndex)
        end

        -- Edge rows (and every row while poisoned) shadow the arrow keys
        -- with a secure click of the real scroll arrow; postClick then
        -- moves focus on the same keypress.
        local edgeBindings = nil
        if index > 1 and (poisoned or not visible[index - 1]) then
            local script = arrowScript("ScrollUpButton")
            if script ~= nil then
                edgeBindings = edgeBindings or {}
                tinsert(edgeBindings, {
                    binding = "up",
                    type = "Script",
                    script = script,
                    postClick = function()
                        scrollFrame.__wvScrollTainted = nil
                        WowVision.graphHost:onKey("up")
                    end,
                })
            end
        end
        if index < total and (poisoned or not visible[index + 1]) then
            local script = arrowScript("ScrollDownButton")
            if script ~= nil then
                edgeBindings = edgeBindings or {}
                tinsert(edgeBindings, {
                    binding = "down",
                    type = "Script",
                    script = script,
                    postClick = function()
                        scrollFrame.__wvScrollTainted = nil
                        WowVision.graphHost:onKey("down")
                    end,
                })
            end
        end
        if homeSpec ~= nil then
            edgeBindings = edgeBindings or {}
            tinsert(edgeBindings, homeSpec)
        end
        if endSpec ~= nil then
            edgeBindings = edgeBindings or {}
            tinsert(edgeBindings, endSpec)
        end

        config.emit(builder, capturedIndex, {
            onFocus = onFocus,
            onFocusTick = onFocusTick,
            target = target,
            id = id,
            edgeBindings = edgeBindings,
        })
    end

    if config.label ~= nil then
        builder:popContext()
    end
    return builder
end
