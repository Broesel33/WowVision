local graph = WowVision.graph
local GraphHost = graph.GraphHost

-- Capture one key combination through a shared keyboard-capturing frame. All
-- keys are blocked from the game and from our own bindings while it is up --
-- that is what capturing means. Modifiers speak as they build; releasing the
-- main key commits "ALT-CTRL-SHIFT-KEY"; Escape cancels. The combination is
-- the one held when the main key went DOWN: people let go of Alt a moment
-- before the letter, and a combination read at the release lost its Alt.
-- config: { label = string|function?, onCommit = function(mapping), onCancel = function? }
function GraphHost:openKeyCapture(config)
    local frame = self.captureFrame
    if frame == nil then
        frame = CreateFrame("Frame", "WowVisionGraphKeyCapture", UIParent)
        frame:EnableKeyboard(true)
        frame:SetPropagateKeyboardInput(false)
        frame:SetFrameStrata("DIALOG")

        local function normalize(key)
            if key == "LCTRL" or key == "RCTRL" then
                return "CTRL"
            end
            if key == "LSHIFT" or key == "RSHIFT" then
                return "SHIFT"
            end
            if key == "LALT" or key == "RALT" then
                return "ALT"
            end
            return key
        end

        -- A modifier counts as held when we saw it go down or the game says it
        -- is down (it may have been pressed before the capture opened).
        local function held(name, isDown)
            return frame.modifiers[name] or (isDown ~= nil and isDown() == true)
        end

        local function currentMapping()
            -- Modifier order is the one the WoW binding API requires.
            local parts = {}
            if held("ALT", IsAltKeyDown) then
                tinsert(parts, "ALT")
            end
            if held("CTRL", IsControlKeyDown) then
                tinsert(parts, "CTRL")
            end
            if held("SHIFT", IsShiftKeyDown) then
                tinsert(parts, "SHIFT")
            end
            if frame.mainKey ~= nil then
                tinsert(parts, frame.mainKey)
            end
            return table.concat(parts, "-")
        end

        frame.resetCapture = function()
            frame.modifiers = { CTRL = false, SHIFT = false, ALT = false }
            frame.mainKey = nil
            frame.mapping = nil
        end

        frame:SetScript("OnKeyDown", function(f, key)
            local entry = self._keyCapture
            if entry == nil then
                return
            end
            local k = normalize(key)
            if k == "ESCAPE" then
                self._keyCapture = nil
                f:Hide()
                if entry.onCancel ~= nil then
                    entry.onCancel()
                end
                return
            end
            if k == "CTRL" or k == "SHIFT" or k == "ALT" then
                f.modifiers[k] = true
            elseif f.mainKey == nil then
                f.mainKey = k
                f.mapping = currentMapping()
            end
            local mapping = f.mapping or currentMapping()
            if mapping ~= "" then
                self:_speak(mapping)
            end
        end)

        frame:SetScript("OnKeyUp", function(f, key)
            local entry = self._keyCapture
            if entry == nil then
                return
            end
            local k = normalize(key)
            if k == "CTRL" or k == "SHIFT" or k == "ALT" then
                f.modifiers[k] = false
                return
            end
            if f.mainKey == k then
                local mapping = f.mapping or currentMapping()
                self._keyCapture = nil
                f:Hide()
                if entry.onCommit ~= nil then
                    entry.onCommit(mapping)
                end
            end
        end)

        frame:Hide()
        self.captureFrame = frame
    end

    frame.resetCapture()
    self._keyCapture = config
    frame:Show()
    local label = config.label
    if type(label) == "function" then
        label = label()
    end
    if label ~= nil then
        self:_speak(label)
    end
end

-- Capture one controller input. The frame takes the pad buttons while it is
-- up (OnGamePadButtonDown swallows them, which is what capturing means).
-- The shoulders, the triggers and the right stick press can be modifiers
-- (core/ui/input/padLogic.lua): the input is the first other button pressed,
-- with the modifiers held as it went down, committed when it comes up; a
-- modifier button pressed and let go on its own is the input itself (the
-- right trigger held and the left shoulder let go: previous window).
-- Escape on the keyboard, ten seconds with nothing pressed, or combat
-- starting cancels; in combat it does not open.
-- config: { label = string|function?, onCommit = function(mapping), onCancel = function? }
local L = WowVision:getLocale()

local PAD_MODIFIER_BUTTONS = {
    PADLSHOULDER = true,
    PADRSHOULDER = true,
    PADLTRIGGER = true,
    PADRTRIGGER = true,
    PADRSTICK = true,
}
local PAD_CAPTURE_TIMEOUT = 10
-- The buttons the held right stick press turns into HOLD inputs.
local HOLD_TARGETS = {}
for _, key in ipairs(WowVision.padLogic.HOLD_KEYS) do
    HOLD_TARGETS[key] = true
end

function GraphHost:openPadCapture(config)
    local frame = self.padCaptureFrame
    if frame == nil then
        frame = CreateFrame("Frame", "WowVisionGraphPadCapture", UIParent)
        frame:SetFrameStrata("DIALOG")
        frame:EnableKeyboard(true)
        frame:SetPropagateKeyboardInput(false)

        -- The input for a main button, with the buttons held now as its
        -- modifiers, by the router's own rule (padLogic.heldModKey).
        local padLogic = WowVision.padLogic
        local function isHeld(button)
            return frame.held[button] == true
        end
        local function mappingFor(main)
            local layerOn = isHeld("PADLSHOULDER") and isHeld("PADRSHOULDER")
            local hold = main ~= padLogic.HOLD_KEY and isHeld(padLogic.HOLD_KEY) and HOLD_TARGETS[main] == true
            local modKey = padLogic.heldModKey(isHeld, main, layerOn, hold)
            return padLogic.normalize(modKey == "" and main or (modKey .. "-" .. main))
        end

        local function finish(commit)
            local entry = self._padCapture
            self._padCapture = nil
            -- (protected; combat starting cancels a capture first)
            if not InCombatLockdown() then
                frame:EnableGamePadButton(false)
            end
            frame:Hide()
            if entry == nil then
                return
            end
            if commit ~= nil then
                if entry.onCommit ~= nil then
                    entry.onCommit(commit)
                end
            else
                self:_speak(L["Cancelled"])
                if entry.onCancel ~= nil then
                    entry.onCancel()
                end
            end
        end
        frame.finish = finish

        frame:SetScript("OnGamePadButtonDown", function(f, button)
            if self._padCapture == nil then
                return
            end
            f.lastInput = GetTime()
            f.held[button] = true
            if f.main == nil and not PAD_MODIFIER_BUTTONS[button] then
                f.main = button
                f.mapping = mappingFor(button)
            end
            if f.mapping ~= nil then
                self:_speak(WowVision.pad.inputText(f.mapping))
            else
                self:_speak(WowVision.pad.inputText(button))
            end
            -- Only the last button to go down can be a modifier on its own.
            f.lastDown = button
        end)

        frame:SetScript("OnGamePadButtonUp", function(f, button)
            if self._padCapture == nil or not f.held[button] then
                return
            end
            f.lastInput = GetTime()
            if f.main == nil and PAD_MODIFIER_BUTTONS[button] and f.lastDown == button then
                -- Pressed and let go on its own: the modifier is the input.
                f.mapping = mappingFor(button)
                f.held[button] = nil
                finish(f.mapping)
                return
            end
            f.held[button] = nil
            if button == f.main then
                finish(f.mapping)
            end
        end)

        frame:SetScript("OnKeyDown", function(_, key)
            if key == "ESCAPE" then
                finish(nil)
            end
        end)

        -- The last moment the capture can give the buttons back.
        frame:RegisterEvent("PLAYER_REGEN_DISABLED")
        frame:SetScript("OnEvent", function()
            if self._padCapture ~= nil then
                finish(nil)
            end
        end)

        frame:SetScript("OnUpdate", function(f)
            if self._padCapture ~= nil and GetTime() - f.lastInput > PAD_CAPTURE_TIMEOUT then
                finish(nil)
            end
        end)

        frame:Hide()
        self.padCaptureFrame = frame
    end

    -- Taking the buttons is protected.
    if InCombatLockdown() then
        self:_speak(L["Not in combat"])
        return
    end
    frame.held = {}
    frame.main = nil
    frame.mapping = nil
    frame.lastDown = nil
    frame.lastInput = GetTime()
    self._padCapture = config
    frame:Show()
    frame:EnableGamePadButton(true)
    local label = config.label
    if type(label) == "function" then
        label = label()
    end
    local prompt = L["Press a controller button"]
    if label ~= nil then
        prompt = label .. ". " .. prompt
    end
    self:_speak(prompt)
end
