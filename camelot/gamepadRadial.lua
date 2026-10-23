-- Blizzard's gamepad main menu (GamepadRadial, the Start button in the
-- world) as a WowVision window. Sighted players see a wheel of eight
-- slices and pick one with the right stick; the shoulders turn its three
-- pages, the D-pad holds sit and the emotes, B closes it.
--
-- Here the slices are a grid of two rows. The upper row is the wheel's
-- right half clockwise from the top (north, north-east, east, south-east),
-- the lower row its left half going on (south, south-west, west,
-- north-west). The left stick moves in the grid while the wheel is open and
-- does not walk; A (and Enter) runs the slice. Every other pad key stays
-- with the wheel (padKeys), so the shoulders, the D-pad, B and Start work as
-- Blizzard made them.
--
-- A slice runs through the game: the micro menu button behind it is
-- clicked, or the game's own key command runs (bags, social). Tracking opens
-- the scanner and chat the chat window, WowVision's own windows for them.
-- Buffs is not supported yet. Anything else (clock, calendar, PvP, the
-- emotes) runs the slice's own action, as the wheel would.
--
-- WowVision never closes the wheel itself: its hide runs Blizzard's binding
-- manager, and run from addon code that would taint it. B or Start closes
-- it, as for everyone.
local module = WowVision.base.windows:createModule("gamepadRadial")
local L = module.L
module:setLabel(L["Gamepad Main Menu"])

local graph = WowVision.graph
local nodes = graph.nodes
local kinds = graph.kinds
local ControlId = graph.ControlId

local WINDOW = "gamepadRadial"

-- Slice numbers (Blizzard's SegmentList: 1 east, counter-clockwise).
local ROWS = {
    { 3, 2, 1, 8 },
    { 7, 6, 5, 4 },
}

-- Slices by the key Blizzard's pages use for them.
local COMMANDS = { bags = "OPENALLBAGS", social = "TOGGLEFRIENDSTAB" }
local WINDOWS = { tracking = "scanner", chat = "chat" }
local UNSUPPORTED = { buffs = true }
local BUTTONS = { calendar = "GameTimeFrame", time = "TimeManagerClockButton" }

local function call(handler, method)
    local fn = handler[method]
    if type(fn) ~= "function" then
        return nil
    end
    local ok, value = pcall(fn, handler)
    if ok then
        return value
    end
    return nil
end

-- The slice's name as the wheel shows it, greyed out or pressed.
local function slotLabel(handler)
    return function()
        local text = nodes.plainText(call(handler, "GetLabel")) or ""
        if not call(handler, "IsEnabled") then
            return text .. ", " .. L["Disabled"]
        end
        if call(handler, "IsDown") then
            return text .. ", " .. L["opened"]
        end
        return text
    end
end

local function secureNode(label, spec)
    spec.binding = "leftClick"
    return {
        controlType = graph.controlTypes.button,
        announcements = { { text = label, kind = kinds.label } },
        bindings = { spec },
    }
end

local function slotNode(radial, index)
    local segment = radial.SegmentList ~= nil and radial.SegmentList[index] or nil
    local handler = segment ~= nil and segment.handler or nil
    if handler == nil then
        return nodes.text({ label = L["Empty"] })
    end
    local page = radial.currentPage
    local key = page ~= nil and page.buttons ~= nil and page.buttons[index] or nil
    local label = slotLabel(handler)
    if UNSUPPORTED[key] then
        return nodes.button({
            label = label,
            onActivate = function()
                WowVision:speak(L["Not supported yet"])
            end,
        })
    end
    if WINDOWS[key] ~= nil then
        local window = WINDOWS[key]
        return nodes.button({
            label = label,
            onActivate = function()
                WowVision.UIHost:openWindow(window)
            end,
        })
    end
    if COMMANDS[key] ~= nil then
        return secureNode(label, { type = "Command", command = COMMANDS[key] })
    end
    local button = handler.button
    if button == nil and BUTTONS[key] ~= nil then
        button = _G[BUTTONS[key]]
    end
    if type(button) == "table" and button.Click ~= nil then
        return secureNode(label, { type = "Click", emulatedKey = "LeftButton", target = button })
    end
    return nodes.button({
        label = label,
        onActivate = function()
            call(handler, "Trigger")
        end,
    })
end

-- "Main Menu, page 2 of 3"; the emote wheel has no pages.
local function pageLabel(radial)
    local header = radial.HeaderText ~= nil and nodes.plainText(radial.HeaderText:GetText()) or nil
    header = header or L["Gamepad Main Menu"]
    local index = radial.currentMainMenuPageIndex
    if index ~= nil and radial.mainMenuPages ~= nil then
        return header .. ", " .. string.format(L["Page %d of %d"], index, #radial.mainMenuPages)
    end
    return header
end

-- A page of its own per context and per id: turning a page lands on the new
-- page's slices, and the announcer reads the new page's name.
local function render(builder, screen)
    local radial = GamepadRadial
    if radial == nil or not radial:IsShown() or radial.currentPage == nil then
        return
    end
    local pageKey = tostring(radial.currentMainMenuPageIndex or radial.currentPage.header or "custom")
    builder:beginStop("radial")
    builder:pushContext("radial:" .. pageKey, pageLabel(radial))
    for _, row in ipairs(ROWS) do
        builder:startRow()
        for _, index in ipairs(row) do
            builder:addItem(ControlId.structural(pageKey .. ":" .. index), slotNode(radial, index))
        end
        builder:endRow()
    end
    builder:popContext()
end

module:registerWindow({
    type = "FrameWindow",
    name = WINDOW,
    frameName = "GamepadRadial",
    graphScreen = { render = render, padKeys = { PAD1 = true } },
})

-- The left stick, while the wheel's window has the focus: one step per push,
-- the next one after the stick came back to the middle. The handler takes
-- the stick from the game (the character does not walk), the way the wheel
-- takes the right stick; any other stick, or the stick while the window is
-- not focused, goes on to the game. Taking the stick is protected, so it
-- switches out of combat only.
local STEP = 0.6
local CENTER = 0.3

local function radialFocused()
    local host = WowVision.graphHost
    local stack = host ~= nil and host:focusedStack() or nil
    return stack ~= nil and stack.config ~= nil and stack.config.key == WINDOW
end

local stickFrame = CreateFrame("Frame")
local armed = true
local stickOn = false
WowVision.pad.addStateSource("WowVision wheel stick", function()
    return stickFrame:IsGamePadStickEnabled()
end)

stickFrame:SetScript("OnGamepadStick", function(_, stick, x, y)
    if stick ~= "Movement" or not radialFocused() then
        return true
    end
    local length = math.sqrt(x * x + y * y)
    if length < CENTER then
        armed = true
        return false
    end
    if armed and length >= STEP then
        armed = false
        local key
        if math.abs(x) > math.abs(y) then
            key = x > 0 and "right" or "left"
        else
            key = y > 0 and "up" or "down"
        end
        WowVision.pad.log("left stick %s", key)
        WowVision.graphHost:onKey(key)
    end
    return false
end)

-- Compared with the frame's own state, never an assumed one: the frame is
-- taking the sticks from the start once it has its stick script (pad log
-- 2026-10-23: taken at login with the wheel closed, both sticks dead until
-- the wheel had been opened and closed once).
local function syncStick()
    local want = GamepadRadial ~= nil and GamepadRadial:IsShown() or false
    local ok, enabled = pcall(stickFrame.IsGamePadStickEnabled, stickFrame)
    if ok then
        stickOn = enabled == true
    end
    if want == stickOn or InCombatLockdown() then
        return
    end
    stickOn = want
    armed = true
    local ok, err = pcall(stickFrame.EnableGamePadStick, stickFrame, want)
    WowVision.pad.log("left stick taken %s%s", tostring(want), ok and "" or (", failed: " .. tostring(err)))
end

local hooked = false
local function hookRadial()
    if hooked or GamepadRadial == nil then
        return
    end
    hooked = true
    GamepadRadial:HookScript("OnShow", syncStick)
    GamepadRadial:HookScript("OnHide", syncStick)
    syncStick()
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:SetScript("OnEvent", function()
    hookRadial()
    syncStick()
end)
syncStick()
