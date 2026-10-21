-- Gamepad probe (developer tool, /wv padprobe): checks in game what
-- controller support for WowVision would rest on. Separate from every
-- module; it can be left out without anything noticing. WoW: Forever only:
-- the gamepad interface is Forever's Blizzard_Gamepad addons.
--
-- /wv padprobe         interface mode, controller, gamepad settings, which
--                      pad button runs which gamepad command, and what every
--                      pad button (alone and with Shift, Ctrl, Alt) is bound
--                      to right now
-- /wv padprobe watch   toggles: every pad button press is spoken and logged
--                      with the pad buttons held at that moment, the modifier
--                      keys the game reports, what the key runs, and the
--                      gamepad states (bar modifiers, targeting, shortcut
--                      layer, D-pad focus); Blizzard's gamepad switches
--                      (radial, UI focus, ping, modifiers, D-pad focus) are
--                      logged as they fire
-- /wv padprobe claim   toggles, out of combat only: the probe binds the right
--                      stick press (alone and with Shift, Ctrl, Alt) and,
--                      while the hostile targeting shoulder or the shortcut
--                      layer is held or a window has the UI focus, the D-pad
--                      (alone and with Shift, Ctrl); a press that reaches one
--                      of these bindings is spoken. When Blizzard binds one of
--                      these keys over the probe, the probe binds it once more
--                      and logs whether that wins. A probe press during a
--                      targeting shoulder hold marks the hold as used
--                      (Blizzard's ConsumeModifier), so letting go does not
--                      target the next unit.
--
-- Both watch and claim say "UI focus on" and "UI focus off" when Blizzard's
-- D-pad focus takes or leaves the pad buttons, and log and say every blocked
-- action (ADDON_ACTION_BLOCKED, ADDON_ACTION_FORBIDDEN): calling
-- ConsumeModifier from addon code may taint Blizzard's targeting.
--
-- Watching never blocks a button: it asks IsKeyDown every frame, the way
-- Blizzard's own class flyout does (OnGamePadButtonDown would swallow the
-- press). Results go to chat and WowVisionDump.gamepadProbe (saved at the
-- next /reload).

local secrets = WowVision.secrets

local CLAIM_BUTTON = "WowVisionGamepadProbeClaim"
local MAX_LINES = 600
local MAX_RUNS = 6

-- The pad buttons by their key names, in the order the logs list them.
local PAD_KEYS = {
    "PAD1",
    "PAD2",
    "PAD3",
    "PAD4",
    "PAD5",
    "PAD6",
    "PADDUP",
    "PADDDOWN",
    "PADDLEFT",
    "PADDRIGHT",
    "PADLSHOULDER",
    "PADRSHOULDER",
    "PADLTRIGGER",
    "PADRTRIGGER",
    "PADLSTICK",
    "PADRSTICK",
    "PADBACK",
    "PADFORWARD",
    "PADSYSTEM",
    "PADSOCIAL",
    "PADPADDLE1",
    "PADPADDLE2",
    "PADPADDLE3",
    "PADPADDLE4",
    "PADLSTICKUP",
    "PADLSTICKDOWN",
    "PADLSTICKLEFT",
    "PADLSTICKRIGHT",
    "PADRSTICKUP",
    "PADRSTICKDOWN",
    "PADRSTICKLEFT",
    "PADRSTICKRIGHT",
}

local LABELS = {
    PAD1 = "bottom face button",
    PAD2 = "right face button",
    PAD3 = "left face button",
    PAD4 = "top face button",
    PADDUP = "D-pad up",
    PADDDOWN = "D-pad down",
    PADDLEFT = "D-pad left",
    PADDRIGHT = "D-pad right",
    PADLSHOULDER = "left shoulder",
    PADRSHOULDER = "right shoulder",
    PADLTRIGGER = "left trigger",
    PADRTRIGGER = "right trigger",
    PADLSTICK = "left stick press",
    PADRSTICK = "right stick press",
    PADBACK = "back button",
    PADFORWARD = "menu button",
    PADSYSTEM = "system button",
    PADSOCIAL = "share button",
}

-- Modifier prefixes in the order the binding API writes them.
local PREFIXES = { "", "SHIFT-", "CTRL-", "ALT-", "CTRL-SHIFT-", "ALT-SHIFT-", "ALT-CTRL-" }

-- Blizzard's gamepad commands (Blizzard_Gamepad, Blizzard_GamepadActionBars
-- and Blizzard_GamepadTargeting Bindings.xml) plus a few plain ones.
local COMMANDS = {
    "OPENRADIAL",
    "TOGGLEUIFOCUS",
    "TOGGLEPINGSYSTEM",
    "GAMEPADLEFTMOD",
    "GAMEPADRIGHTMOD",
    "GAMEPADLEFTTARGETMODIFIER",
    "GAMEPADRIGHTTARGETMODIFIER",
    "GAMEPADACTIONBUTTON1",
    "GAMEPADACTIONBUTTON2",
    "GAMEPADACTIONBUTTON3",
    "GAMEPADACTIONBUTTON4",
    "GAMEPADACTIONBUTTON5",
    "GAMEPADACTIONBUTTON6",
    "GAMEPADACTIONBUTTON7",
    "GAMEPADACTIONBUTTON8",
    "INTERACTSOFTTARGET",
    "TOGGLEAUTORUN",
    "JUMP",
    "TOGGLEGAMEMENU",
}

local SETTINGS = {
    "InputDeviceInterfaceStyle",
    "GamePadEnable",
    "GamePadEmulateShift",
    "GamePadEmulateCtrl",
    "GamePadEmulateAlt",
    "GamePadEmulateEsc",
    "GamepadHudModifierUsesToggle",
    "GamepadSwapTargetModifiers",
    "GamepadUsePartyTargeting",
    "GamepadShowPersistentInputLegend",
    "ActionButtonUseKeyDown",
}

-- The probe's own bindings: key, then the name the click carries (no dash,
-- so the binding's click name stays plain).
local R3_CLAIMS = {
    { key = "PADRSTICK", name = "R3" },
    { key = "SHIFT-PADRSTICK", name = "ShiftR3" },
    { key = "CTRL-PADRSTICK", name = "CtrlR3" },
    { key = "ALT-PADRSTICK", name = "AltR3" },
}

local DPAD_CLAIMS = {}
for _, entry in ipairs({
    { key = "PADDUP", name = "DUp" },
    { key = "PADDDOWN", name = "DDown" },
    { key = "PADDLEFT", name = "DLeft" },
    { key = "PADDRIGHT", name = "DRight" },
}) do
    tinsert(DPAD_CLAIMS, entry)
    tinsert(DPAD_CLAIMS, { key = "SHIFT-" .. entry.key, name = "Shift" .. entry.name })
    tinsert(DPAD_CLAIMS, { key = "CTRL-" .. entry.key, name = "Ctrl" .. entry.name })
end

local CLAIM_KEYS = {}
for _, entry in ipairs(R3_CLAIMS) do
    CLAIM_KEYS[entry.name] = entry.key
end
for _, entry in ipairs(DPAD_CLAIMS) do
    CLAIM_KEYS[entry.name] = entry.key
end

-- Output ------------------------------------------------------------------

local function chat(text)
    for line in tostring(text):gmatch("[^\n]+") do
        print("WowVision pad probe: " .. line)
    end
end

local function say(text)
    chat(text)
    WowVision:speak(text)
end

local function newRun(name)
    WowVisionDump = WowVisionDump or {}
    local runs = WowVisionDump.gamepadProbe or {}
    local run = { name = name, at = date("%Y-%m-%d %H:%M:%S"), lines = {} }
    tinsert(runs, run)
    while #runs > MAX_RUNS do
        tremove(runs, 1)
    end
    WowVisionDump.gamepadProbe = runs
    return run
end

local function addLine(run, text)
    if #run.lines < MAX_LINES then
        tinsert(run.lines, string.format("%.2f %s", GetTime(), text))
    elseif #run.lines == MAX_LINES then
        tinsert(run.lines, "log full")
    end
    chat(text)
end

local function report(name, lines)
    local run = newRun(name)
    for _, line in ipairs(lines) do
        addLine(run, line)
    end
end

-- Reading the game --------------------------------------------------------

local function call(fn, ...)
    if type(fn) ~= "function" then
        return nil
    end
    local ok, value = pcall(fn, ...)
    if ok then
        return value
    end
    return nil
end

local function yesNo(value)
    if value == nil then
        return "unknown"
    end
    return value and "yes" or "no"
end

local function label(key)
    return LABELS[key] or key
end

-- "ALT-PADRSTICK" as "Alt right stick press".
local function spokenKey(keyString)
    local words = {}
    for modifier in keyString:gmatch("(%u+)%-") do
        tinsert(words, modifier:sub(1, 1) .. modifier:sub(2):lower())
    end
    local base = keyString:match("([^%-]+)$") or keyString
    tinsert(words, label(base))
    return table.concat(words, " ")
end

-- PADLSTICKUP and the like: the stick pushed, not pressed.
local function isStickDirection(key)
    return key:match("STICK%u+$") ~= nil
end

local function keyDown(key)
    return call(IsKeyDown, key) == true
end

-- Every pad key name: the list above plus whatever the controller maps.
local padKeysCache
local function padKeys()
    if padKeysCache ~= nil then
        return padKeysCache
    end
    local keys, seen = {}, {}
    for _, key in ipairs(PAD_KEYS) do
        tinsert(keys, key)
        seen[key] = true
    end
    if C_GamePad ~= nil and C_GamePad.ButtonIndexToBinding ~= nil then
        for i = 0, 63 do
            local key = call(C_GamePad.ButtonIndexToBinding, i)
            if type(key) == "string" and key ~= "" and not seen[key] then
                tinsert(keys, key)
                seen[key] = true
            end
        end
    end
    padKeysCache = keys
    return keys
end

-- The pad buttons held right now, except one, as labels.
local function heldLabels(except)
    local held = {}
    for _, key in ipairs(padKeys()) do
        if key ~= except and not isStickDirection(key) and keyDown(key) then
            tinsert(held, label(key))
        end
    end
    return held
end

local function gameModifiers()
    local parts = {}
    if IsAltKeyDown() then
        tinsert(parts, "alt")
    end
    if IsControlKeyDown() then
        tinsert(parts, "ctrl")
    end
    if IsShiftKeyDown() then
        tinsert(parts, "shift")
    end
    return parts
end

-- The key string the binding system matches for this press.
local function gameKey(key)
    local prefix = ""
    if IsAltKeyDown() then
        prefix = prefix .. "ALT-"
    end
    if IsControlKeyDown() then
        prefix = prefix .. "CTRL-"
    end
    if IsShiftKeyDown() then
        prefix = prefix .. "SHIFT-"
    end
    return prefix .. key
end

local function action(key)
    local value = call(GetBindingAction, key, true)
    if value == nil or value == "" then
        return nil
    end
    return value
end

local function describeFrame(frame)
    if frame == nil then
        return "nothing"
    end
    local name = call(frame.GetDebugName, frame) or call(frame.GetName, frame) or "unnamed frame"
    local text = call(frame.GetText, frame)
    if text ~= nil and not secrets.isSecret(text) and text ~= "" then
        name = name .. " '" .. text .. "'"
    end
    return name
end

local function styleName()
    if C_InputInterfaceStyle == nil then
        return "no interface style API"
    end
    local style = call(C_InputInterfaceStyle.GetCurrentStyle)
    if style == nil then
        return "unknown"
    end
    if Enum ~= nil and Enum.InputDeviceInterfaceType ~= nil then
        for name, value in pairs(Enum.InputDeviceInterfaceType) do
            if value == style then
                return name
            end
        end
    end
    return tostring(style)
end

local function targetingName(flag)
    local states = GamepadTargetingState
    if states ~= nil then
        for name, value in pairs(states) do
            if value == flag then
                return name:lower()
            end
        end
    end
    return tostring(flag)
end

local function isHostileHeld()
    local gm, states = GamepadMode, GamepadTargetingState
    if gm == nil or states == nil then
        return false
    end
    return call(gm.IsTargetingModifierDown, states.HOSTILE) == true
end

local function isLayerOn()
    local gm = GamepadMode
    return gm ~= nil and call(gm.IsHUDBindingModifierDown) == true
end

local function padStateText()
    local gm = GamepadMode
    if gm == nil then
        return "gamepad interface code not loaded"
    end
    local states = GamepadTargetingState or {}
    local parts = {
        "left bar modifier " .. yesNo(call(gm.IsLeftModifierDown)),
        "right bar modifier " .. yesNo(call(gm.IsRightModifierDown)),
        "friendly targeting " .. yesNo(call(gm.IsTargetingModifierDown, states.FRIENDLY)),
        "hostile targeting " .. yesNo(call(gm.IsTargetingModifierDown, states.HOSTILE)),
        "shortcut layer " .. yesNo(call(gm.IsHUDBindingModifierDown)),
    }
    local nav = SmartNavigation
    if nav ~= nil then
        local navState = "off"
        if nav.enabled then
            navState = nav.bindingActive and "on" or "idle"
        end
        tinsert(parts, "D-pad focus " .. navState)
        if nav.currentButton ~= nil then
            tinsert(parts, "focused " .. describeFrame(nav.currentButton))
        end
    end
    return table.concat(parts, ", ")
end

-- Snapshot ----------------------------------------------------------------

local function settingLine(name)
    local ok, value, default = pcall(C_CVar.GetCVarInfo, name)
    if not ok or value == nil then
        return name .. ": no such setting"
    end
    return name .. ": " .. tostring(value) .. ", game default " .. tostring(default)
end

local function snapshot()
    local lines = {}
    tinsert(lines, "interface style " .. styleName() .. ", in combat " .. yesNo(InCombatLockdown()))
    if C_GamePad ~= nil then
        tinsert(lines, "controller support enabled " .. yesNo(call(C_GamePad.IsEnabled)))
        local state = call(C_GamePad.GetDeviceMappedState)
        if state ~= nil then
            tinsert(
                lines,
                string.format(
                    "controller %s, labels %s, %s buttons, %s axes, %s sticks",
                    tostring(state.name),
                    tostring(state.labelStyle),
                    tostring(state.buttonCount),
                    tostring(state.axisCount),
                    tostring(state.stickCount)
                )
            )
        else
            tinsert(lines, "no controller seen")
        end
    else
        tinsert(lines, "no C_GamePad API")
    end
    for _, name in ipairs(SETTINGS) do
        tinsert(lines, settingLine(name))
    end
    for _, command in ipairs(COMMANDS) do
        -- The second argument as Blizzard's GamepadMode.IsBindingDown passes it.
        local ok, keys = pcall(function()
            return { GetBindingKey(command, true) }
        end)
        if not ok then
            keys = {}
        end
        tinsert(lines, command .. ": " .. (#keys > 0 and table.concat(keys, ", ") or "no key"))
    end
    local bound = 0
    for _, key in ipairs(padKeys()) do
        for _, prefix in ipairs(PREFIXES) do
            local value = action(prefix .. key)
            if value ~= nil then
                bound = bound + 1
                tinsert(lines, prefix .. key .. " runs " .. value)
            end
        end
    end
    tinsert(lines, bound .. " pad key combinations bound")
    tinsert(lines, "pad keys known: " .. table.concat(padKeys(), " "))
    tinsert(lines, padStateText())
    report("snapshot", lines)
    WowVision:speak("Gamepad snapshot, " .. #lines .. " lines in chat")
end

-- Watch and claim share one frame that polls every frame.

local watching = false
local claiming = false
local watchRun, claimRun
local downAt = {}
local lastStyle
local dpadClaimed = false
local combatNoted = false
local pollFrame, claimButton, r3Owner, dpadOwner
local hooked = false
local lastUiFocus
-- Per claimed key: "retried" after binding it again, then "won" or "lost".
local takeBack = {}

-- Blizzard's D-pad focus has the pad buttons (its input stack binds them).
local function uiFocusOn()
    local nav = SmartNavigation
    return nav ~= nil and nav.enabled == true and nav.bindingActive == true
end

local function note(text)
    if watchRun ~= nil then
        addLine(watchRun, text)
    elseif claimRun ~= nil then
        addLine(claimRun, text)
    else
        chat(text)
    end
end

local function onPadDown(key)
    local held = heldLabels(key)
    local modifiers = gameModifiers()
    local pressed = gameKey(key)
    local parts = { "down " .. key .. " (" .. label(key) .. ")" }
    tinsert(parts, "held: " .. (#held > 0 and table.concat(held, ", ") or "none"))
    tinsert(parts, "game modifiers: " .. (#modifiers > 0 and table.concat(modifiers, " ") or "none"))
    tinsert(parts, pressed .. " runs " .. (action(pressed) or "nothing"))
    if pressed ~= key then
        tinsert(parts, key .. " alone runs " .. (action(key) or "nothing"))
    end
    tinsert(parts, padStateText())
    addLine(watchRun, table.concat(parts, "; "))
    local spoken = label(key)
    if #held > 0 then
        spoken = spoken .. ", with " .. table.concat(held, ", ")
    end
    WowVision:speak(spoken)
end

local function onPadUp(key)
    addLine(watchRun, string.format("up %s after %.2f s", key, GetTime() - downAt[key]))
end

local function pollKeys()
    for _, key in ipairs(padKeys()) do
        if not isStickDirection(key) then
            local down = keyDown(key)
            if down and downAt[key] == nil then
                downAt[key] = GetTime()
                onPadDown(key)
            elseif not down and downAt[key] ~= nil then
                onPadUp(key)
                downAt[key] = nil
            end
        end
    end
    local style = styleName()
    if style ~= lastStyle then
        lastStyle = style
        addLine(watchRun, "interface style now " .. style)
    end
end

-- Bind the D-pad to the probe while the hostile shoulder or the shortcut
-- layer is held. Override bindings cannot change in combat; that is one of
-- the things this shows.
local function updateDpadClaim()
    local want = claiming and (isHostileHeld() or isLayerOn() or uiFocusOn())
    if want == dpadClaimed then
        combatNoted = false
        return
    end
    if InCombatLockdown() then
        if not combatNoted then
            combatNoted = true
            note("D-pad claim change skipped: in combat")
        end
        return
    end
    combatNoted = false
    if want then
        for _, entry in ipairs(DPAD_CLAIMS) do
            SetOverrideBindingClick(dpadOwner, true, entry.key, CLAIM_BUTTON, entry.name)
        end
        local why = "hostile targeting"
        if isLayerOn() then
            why = "shortcut layer"
        elseif uiFocusOn() then
            why = "UI focus"
        end
        note("D-pad bound to the probe (" .. why .. ")")
    else
        ClearOverrideBindings(dpadOwner)
        for _, entry in ipairs(DPAD_CLAIMS) do
            takeBack[entry.key] = nil
        end
        note("D-pad given back")
    end
    dpadClaimed = want
end

-- Blizzard's input stack binds every pad key when a window takes the UI
-- focus. Bind a taken key to the probe once more and see on the next frame
-- whose binding it runs: whether the binding set last wins.
local function checkTakeBack(owner, entries)
    for _, entry in ipairs(entries) do
        local state = takeBack[entry.key]
        local current = action(entry.key)
        if current == "CLICK " .. CLAIM_BUTTON .. ":" .. entry.name then
            if state == "retried" then
                takeBack[entry.key] = "won"
                note(entry.key .. " is the probe's again after binding it once more")
            end
        elseif state == nil then
            if not InCombatLockdown() then
                SetOverrideBindingClick(owner, true, entry.key, CLAIM_BUTTON, entry.name)
                takeBack[entry.key] = "retried"
                note(entry.key .. " was taken by " .. (current or "nothing") .. ", bound to the probe once more")
            end
        elseif state == "retried" then
            takeBack[entry.key] = "lost"
            note(entry.key .. " still runs " .. (current or "nothing") .. " after binding it once more")
        end
    end
end

local function onUpdate()
    local focus = uiFocusOn()
    if focus ~= lastUiFocus then
        lastUiFocus = focus
        takeBack = {}
        note(focus and "UI focus on" or "UI focus off")
        WowVision:speak(focus and "UI focus on" or "UI focus off")
    end
    if watching then
        pollKeys()
    end
    if claiming or dpadClaimed then
        updateDpadClaim()
    end
    if claiming then
        checkTakeBack(r3Owner, R3_CLAIMS)
        if dpadClaimed then
            checkTakeBack(dpadOwner, DPAD_CLAIMS)
        end
    end
end

local function ensureFrames()
    if pollFrame ~= nil then
        return
    end
    pollFrame = CreateFrame("Frame")
    claimButton = CreateFrame("Button", CLAIM_BUTTON, UIParent)
    claimButton:RegisterForClicks("AnyDown", "AnyUp")
    claimButton:SetScript("OnClick", function(_, which, down)
        if down == false then
            return
        end
        local held = heldLabels(nil)
        local modifiers = gameModifiers()
        note(
            "probe binding reached: "
                .. tostring(CLAIM_KEYS[which] or which)
                .. "; held: "
                .. (#held > 0 and table.concat(held, ", ") or "none")
                .. "; game modifiers: "
                .. (#modifiers > 0 and table.concat(modifiers, " ") or "none")
                .. "; "
                .. padStateText()
        )
        WowVision:speak("Probe got " .. spokenKey(tostring(CLAIM_KEYS[which] or which)))
        -- Without this, letting go of the shoulder targets the next unit
        -- (TargetLogic EndTargeting): the probe press is not a Blizzard one.
        local gm, logic = GamepadMode, GamepadTargetLogic
        if
            gm ~= nil
            and logic ~= nil
            and type(logic.ConsumeModifier) == "function"
            and call(gm.IsTargetingModifierDown) == true
        then
            logic:ConsumeModifier()
            note("targeting hold marked as used (ConsumeModifier)")
        end
    end)
    r3Owner = CreateFrame("Frame")
    dpadOwner = CreateFrame("Frame")
    pcall(pollFrame.RegisterEvent, pollFrame, "ADDON_ACTION_BLOCKED")
    pcall(pollFrame.RegisterEvent, pollFrame, "ADDON_ACTION_FORBIDDEN")
    pollFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
    pollFrame:SetScript("OnEvent", function(_, event, addon, func)
        -- The last moment before combat lockdown: give the D-pad back, or
        -- it stays the probe's (and the action bar's D-pad dead) all fight.
        if event == "PLAYER_REGEN_DISABLED" then
            if dpadClaimed then
                ClearOverrideBindings(dpadOwner)
                dpadClaimed = false
                for _, entry in ipairs(DPAD_CLAIMS) do
                    takeBack[entry.key] = nil
                end
                note("D-pad given back: combat starts")
            end
            return
        end
        if watching or claiming then
            note("BLOCKED: " .. event .. ", addon " .. tostring(addon) .. ", function " .. tostring(func))
            WowVision:speak("Action blocked, " .. tostring(func))
        end
    end)
end

local function updatePolling()
    if watching or claiming or dpadClaimed then
        pollFrame:SetScript("OnUpdate", onUpdate)
    else
        pollFrame:SetScript("OnUpdate", nil)
    end
end

-- Post hooks on Blizzard's gamepad switches: they run after the original
-- and only note what happened.
local function installHooks()
    if hooked then
        return
    end
    hooked = true
    local function hook(target, name, describe)
        if target ~= nil and type(target[name]) == "function" then
            hooksecurefunc(target, name, function(...)
                if watching then
                    local ok, text = pcall(describe, ...)
                    note("game: " .. (ok and tostring(text) or name))
                end
            end)
        end
    end
    local gm = GamepadMode
    hook(gm, "OpenRadial", function()
        return "radial menu opened or closed"
    end)
    hook(gm, "ToggleUIFocus", function()
        return "UI focus toggled"
    end)
    hook(gm, "TogglePingSystem", function(down)
        return "ping " .. (down and "down" or "up")
    end)
    hook(gm, "OnCrossBarModifierChanged", function(mod, down)
        return "bar modifier " .. tostring(mod) .. (down and " down" or " up")
    end)
    hook(gm, "SetTargetModifier", function(flag, down)
        return "targeting modifier " .. targetingName(flag) .. (down and " on" or " off")
    end)
    hook(gm, "SetHUDBindingModifier", function(down)
        return "shortcut layer " .. (down and "on" or "off")
    end)
    local logic = GamepadTargetLogic
    hook(logic, "TargetNextFriendly", function()
        return "target next friendly"
    end)
    hook(logic, "TargetNextHostile", function()
        return "target next hostile"
    end)
    hook(logic, "FlipCamera", function(_, down)
        return "flip camera " .. (down and "down" or "up")
    end)
    hook(SmartNavigation, "SelectButton", function(_, button)
        return "D-pad focus on " .. describeFrame(button)
    end)
end

local function startWatch()
    ensureFrames()
    installHooks()
    watchRun = newRun("watch")
    downAt = {}
    lastStyle = styleName()
    if not claiming then
        lastUiFocus = uiFocusOn()
    end
    watching = true
    updatePolling()
    addLine(watchRun, "watch started, interface style " .. lastStyle .. "; " .. padStateText())
    WowVision:speak("Pad watch started")
end

local function stopWatch()
    watching = false
    addLine(watchRun, "watch stopped")
    watchRun = nil
    updatePolling()
    say("Pad watch stopped, log saved at the next reload")
end

local function startClaim()
    if InCombatLockdown() then
        say("Pad claim needs you out of combat")
        return
    end
    ensureFrames()
    claimRun = newRun("claim")
    for _, entry in ipairs(R3_CLAIMS) do
        SetOverrideBindingClick(r3Owner, true, entry.key, CLAIM_BUTTON, entry.name)
    end
    if not watching then
        lastUiFocus = uiFocusOn()
    end
    takeBack = {}
    claiming = true
    updatePolling()
    addLine(
        claimRun,
        "claim started: right stick press bound to the probe; D-pad follows the hostile shoulder, the shortcut layer and UI focus"
    )
    WowVision:speak("Pad claim started")
end

local function stopClaim()
    if InCombatLockdown() then
        say("Pad claim can only stop out of combat")
        return
    end
    claiming = false
    ClearOverrideBindings(r3Owner)
    if dpadClaimed then
        ClearOverrideBindings(dpadOwner)
        dpadClaimed = false
    end
    addLine(claimRun, "claim stopped, all probe bindings removed")
    claimRun = nil
    updatePolling()
    say("Pad claim stopped")
end

-- Command -----------------------------------------------------------------

WowVision.base:registerCommand({
    name = "padprobe",
    description = "Gamepad probe: no argument lists the gamepad settings and pad bindings, 'watch' toggles a log of every pad button press, 'claim' toggles probe bindings on the right stick press and the D-pad",
    func = function(args)
        local command = tostring(args or ""):lower():match("%S+")
        if command == "watch" then
            if watching then
                stopWatch()
            else
                startWatch()
            end
        elseif command == "claim" then
            if claiming then
                stopClaim()
            else
                startClaim()
            end
        elseif command == nil then
            snapshot()
        else
            say("Usage: slash w v padprobe, padprobe watch, or padprobe claim")
        end
    end,
})
