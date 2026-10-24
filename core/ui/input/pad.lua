-- Controller input, the game side. Bindings carry controller inputs next to
-- their keyboard ones (Binding.padInputs, defaults in padLogic.DEFAULTS);
-- wherever a keyboard input binds a pooled secure frame to a key, a
-- controller input attaches the same frame here instead. The router binds
-- each pad key once, to its own secure button, and a press picks the entry
-- for the modifiers held right then (padLogic.heldModKey).
--
-- What a probe in the game showed (WoW: Forever, 2026-10-21) and this rests
-- on:
-- - The pad sends no Shift, Ctrl or Alt; IsKeyDown reads every pad button.
-- - An addon override binding on a pad key beats the game's gamepad
--   bindings. Blizzard's window mode (UI focus) binds every pad key over
--   ours when a window takes the focus; binding ours again wins. So every
--   frame, out of combat, a key we own that runs something else is bound
--   again.
-- - Override bindings cannot change in combat. Keys WowVision owns all the
--   time (padLogic.WORLD_KEYS: the right stick press) keep working; window
--   keys and the shortcut layer are given back when combat starts, like the
--   window keymaps already are.
-- - A press during a targeting shoulder hold must tell Blizzard the hold was
--   used (GamepadTargetLogic:ConsumeModifier), or letting go targets the
--   next unit. Tested in and out of combat, nothing blocked.
--
-- In combat a press can only run Lua: Function actions (their function is
-- called right here) and Script actions that are a "/run" line (the line is
-- run here). A secure action (a real click) needs the router button's
-- attributes set, which only works out of combat. In combat only the world
-- keys are bound, and their actions are all Lua.
--
-- The right stick press doubles as the hold key: held down, a secure
-- handler binds the D-pad to the HOLD entries (buffers) and gives it back on
-- release, which secure code may do in combat. Let go without touching the
-- D-pad and it is a press of its own (turn to the waypoint and its
-- combinations).
local padLogic = WowVision.padLogic

local pad = {}
WowVision.pad = pad

local routes = padLogic.newRoutes()
local buttons = {}
local bound = {}
local dirty = true
local combatStarting = false

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

local function isDown(key)
    return call(IsKeyDown, key) == true
end

-- The pad log, into WowVisionDump.padLog (the last LOG_MAX lines, saved at
-- logout or /reload; the session before stays as padLogBefore): every pad
-- press and what it ran, every key taken back from the game, the window
-- keys and the speech around them. It runs by itself while the gamepad
-- interface is on, so a tester's report comes with its log; /wv padlog
-- starts it afresh. Nothing is printed: chat output would mix into the
-- speech it logs.
local LOG_MAX = 2000
local logOn = false
local logHooked = false

local function log(fmt, ...)
    if not logOn then
        return
    end
    local ok, text = pcall(string.format, fmt, ...)
    if not ok then
        text = fmt
    end
    local lines = WowVisionDump.padLog
    tinsert(lines, string.format("%.3f %s", GetTime(), text))
    if #lines > LOG_MAX then
        tremove(lines, 1)
    end
end
pad.log = log

-- Spoken text for the log; secret text (Retail-style unit values) is not
-- touched.
local function shortText(text)
    if WowVision.isSecret(text) then
        return "(secret)"
    end
    if type(text) ~= "string" then
        return tostring(text)
    end
    return text:sub(1, 50)
end

-- The hooks go in at the first start: the speech module and the window host
-- load after this file.
local function hookLog()
    if logHooked then
        return
    end
    logHooked = true
    local speech = WowVision.base.speech
    hooksecurefunc(speech, "speak", function(self, text)
        log("speak [queue %d, speaking %s] %s", #(self.queue or {}), tostring(self.speaking), shortText(text))
    end)
    hooksecurefunc(speech, "stop", function()
        log("speech stop")
    end)
    local events = CreateFrame("Frame")
    events:RegisterEvent("VOICE_CHAT_TTS_PLAYBACK_STARTED")
    events:RegisterEvent("VOICE_CHAT_TTS_PLAYBACK_FINISHED")
    events:RegisterEvent("VOICE_CHAT_TTS_PLAYBACK_FAILED")
    events:SetScript("OnEvent", function(_, event, ...)
        log("%s %s", event:gsub("VOICE_CHAT_TTS_", ""), table.concat({ tostringall(...) }, " "))
    end)
    hooksecurefunc(WowVision.graphHost, "onKey", function(_, key)
        log("window key %s", tostring(key))
    end)
end

-- A fresh log, at login and on /wv padlog. False with the gamepad
-- interface off: then nothing is logged.
function pad.restartLog()
    logOn = pad.controllerUIEnabled()
    if not logOn then
        return false
    end
    hookLog()
    WowVisionDump = WowVisionDump or {}
    if WowVisionDump.padLog ~= nil and #WowVisionDump.padLog > 1 then
        WowVisionDump.padLogBefore = WowVisionDump.padLog
    end
    WowVisionDump.padLog = {}
    log("log started")
    return true
end

-- The game's shortcut layer (both shoulders), Forever's gamepad interface.
function pad.layerOn()
    local gm = GamepadMode
    return gm ~= nil and call(gm.IsHUDBindingModifierDown) == true
end

-- A press while a targeting shoulder is held counts as using the hold.
local function consumeTargeting()
    local gm, logic = GamepadMode, GamepadTargetLogic
    if gm == nil or logic == nil or type(logic.ConsumeModifier) ~= "function" then
        return
    end
    if call(gm.IsTargetingModifierDown) == true then
        pcall(logic.ConsumeModifier, logic)
    end
end

local function windowOpen()
    local host = WowVision.graphHost
    return host ~= nil and host:isOpen()
end

-- The pad keys the focused window keeps for itself (its graphScreen
-- padKeys), or nil for all of them.
local function windowOnlyKeys()
    local host = WowVision.graphHost
    local stack = host ~= nil and host:focusedStack() or nil
    return stack ~= nil and stack.config ~= nil and stack.config.padKeys or nil
end

-- The Lua of a Script action's one-line "/run" macro, or nil. Running it
-- here is what the macro would do (macro Lua runs as addon code anyway),
-- and works in combat, where this button's click cannot be redirected.
local function macroLua(frame)
    if frame:GetAttribute("type") ~= "macro" then
        return nil
    end
    local text = frame:GetAttribute("macrotext")
    if type(text) ~= "string" or text:find("\n", 1, true) then
        return nil
    end
    return text:match("^/run%s+(.+)$") or text:match("^/script%s+(.+)$")
end

-- Run what a press picked.
function pad.dispatch(button, base, hold)
    local modKey = padLogic.heldModKey(isDown, base, pad.layerOn(), hold)
    local entry = padLogic.pick(routes, base, modKey)
    log(
        "pad %s [%s]%s -> %s",
        base,
        modKey,
        hold and " hold" or "",
        entry == nil and "nothing" or entry.kind == "command" and ("command " .. tostring(entry.command))
            or (entry.frame.func ~= nil and "function" or tostring(entry.frame:GetAttribute("type")))
    )
    if entry == nil then
        return
    end
    consumeTargeting()
    local lua = entry.kind == "frame" and entry.frame.func == nil and macroLua(entry.frame) or nil
    if entry.kind == "frame" and entry.frame.func ~= nil then
        local ok, err = pcall(entry.frame.func)
        if not ok then
            geterrorhandler()(err)
        end
    elseif lua ~= nil then
        local ok, err = pcall(RunScript, lua)
        if not ok then
            geterrorhandler()(err)
        end
    end
    if entry.kind == "frame" and (entry.frame.func ~= nil or lua ~= nil) then
        -- The frame's own after-click step (activator spec.postClick), which
        -- its click would have run.
        local post = entry.frame.GetScript ~= nil and entry.frame:GetScript("PostClick") or nil
        if post ~= nil then
            local ok, err = pcall(post, entry.frame)
            if not ok then
                geterrorhandler()(err)
            end
        end
        return
    end
    if entry.kind == "frame" and not InCombatLockdown() then
        -- A secure action, run by this button as the entry's keyboard key
        -- runs it. A macro is taken over as it is: one started from another
        -- macro's /click does not run (the wheel's slices, 2026-10-23).
        -- Anything else is clicked as a key-down click: a "click" redirect
        -- is a release, which a key-down button ignores.
        button:SetAttribute("type", "macro")
        local frame = entry.frame
        if frame:GetAttribute("type") == "macro" then
            button:SetAttribute("macrotext", frame:GetAttribute("macrotext"))
        else
            button:SetAttribute("macrotext", "/click " .. frame:GetName() .. " " .. entry.mouseButton .. " true")
        end
    end
end

local function resetClick(button)
    if not InCombatLockdown() then
        button:SetAttribute("type", nil)
        button:SetAttribute("macrotext", nil)
    end
end

-- The hold handler and its D-pad buttons. Built once, out of combat.
local holdHeader
local function buildHold()
    holdHeader = CreateFrame("Frame", "WowVisionPadHold", UIParent, "SecureHandlerBaseTemplate")
    for _, key in ipairs(padLogic.HOLD_KEYS) do
        local button = CreateFrame("Button", "WowVisionPadHold_" .. key, UIParent, "SecureActionButtonTemplate")
        button:RegisterForClicks("AnyDown")
        button:SetAttribute("useOnKeyDown", true)
        button:SetScript("PreClick", function(self)
            pad.dispatch(self, key, true)
        end)
        button:SetScript("PostClick", resetClick)
        holdHeader:WrapScript(button, "OnClick", [[ owner:SetAttribute("used", true) ]])
    end
    local key = padLogic.HOLD_KEY
    local button = CreateFrame("Button", "WowVisionPad_" .. key, UIParent, "SecureActionButtonTemplate")
    button:RegisterForClicks("AnyDown", "AnyUp")
    -- Its press runs on the release (the down only arms the D-pad).
    button:SetAttribute("useOnKeyDown", false)
    -- Down: the D-pad keys with HOLD entries ("bind<KEY>" attributes, set
    -- out of combat) go to the hold buttons, and the press waits. Up: the
    -- D-pad comes back; the press runs unless the D-pad was used.
    local snippet = [[
        if down then
            owner:SetAttribute("used", false)
    ]]
    for _, holdKey in ipairs(padLogic.HOLD_KEYS) do
        snippet = snippet
            .. string.format(
                [[
            if owner:GetAttribute("bind%s") then
                owner:SetBindingClick(true, "%s", "WowVisionPadHold_%s")
            end
    ]],
                holdKey,
                holdKey,
                holdKey
            )
    end
    snippet = snippet .. [[
            return false
        end
        owner:ClearBindings()
    ]]
    holdHeader:WrapScript(button, "OnClick", snippet)
    button:SetScript("PreClick", function(self, _, down)
        log("%s %s, D-pad used %s", key, down and "down" or "up", tostring(holdHeader:GetAttribute("used")))
        if down == true then
            return
        end
        if holdHeader:GetAttribute("used") then
            return
        end
        pad.dispatch(self, key, false)
    end)
    button:SetScript("PostClick", resetClick)
    buttons[key] = button
end

local function routerButton(base)
    local button = buttons[base]
    if button ~= nil then
        return button
    end
    button = CreateFrame("Button", "WowVisionPad_" .. base, UIParent, "SecureActionButtonTemplate")
    button:RegisterForClicks("AnyDown")
    -- (whatever the player's "use key down" setting: a secure button acts
    -- only on the half of the click it is set for)
    button:SetAttribute("useOnKeyDown", true)
    button:SetScript("PreClick", function(self)
        pad.dispatch(self, base, false)
    end)
    button:SetScript("PostClick", resetClick)
    buttons[base] = button
    return button
end

-- What a key we own should run: a game command when its plain entry is one
-- (B as Escape), otherwise a click of its router button.
local function wanted(base)
    local plain = padLogic.pick(routes, base, "")
    if plain ~= nil and plain.kind == "command" then
        return "command", plain.command
    end
    return "click", "CLICK " .. routerButton(base):GetName() .. ":LeftButton"
end

local function release(base)
    local button = buttons[base]
    if button ~= nil then
        ClearOverrideBindings(button)
    end
    bound[base] = nil
end

-- Bind what should be bound, give back what should not, take back what the
-- game bound over us. Out of combat only; a held key waits (the engine hands
-- a key's release to whoever owns it then, and the game's action would
-- never see its release).
function pad.sync()
    if InCombatLockdown() then
        dirty = true
        return
    end
    if holdHeader == nil then
        buildHold()
    end
    dirty = false
    local state = { windowOpen = windowOpen(), layerOn = pad.layerOn() }
    if state.windowOpen then
        state.onlyKeys = windowOnlyKeys()
    end
    if combatStarting then
        state = { windowOpen = false, layerOn = false }
    end
    local owned = padLogic.ownedBases(routes, state)
    local holding = isDown(padLogic.HOLD_KEY)
    for base in pairs(bound) do
        if not owned[base] then
            release(base)
        end
    end
    for base in pairs(owned) do
        local kind, action = wanted(base)
        local current = GetBindingAction(base, true)
        -- While the hold key is down the hold handler owns the D-pad.
        local heldAway = holding and holdHeader:GetAttribute("bind" .. base)
        if current ~= action and not heldAway and not isDown(base) then
            log("bind %s (it ran %s)", base, tostring(current))
            local button = routerButton(base)
            ClearOverrideBindings(button)
            if kind == "command" then
                SetOverrideBinding(button, true, base, action)
            else
                SetOverrideBindingClick(button, true, base, button:GetName(), "LeftButton")
            end
            bound[base] = true
        end
    end
    local holdBases = padLogic.holdBases(routes)
    for _, key in ipairs(padLogic.HOLD_KEYS) do
        local want = holdBases[key] == true
        if (holdHeader:GetAttribute("bind" .. key) == true) ~= want then
            holdHeader:SetAttribute("bind" .. key, want)
        end
    end
end

-- Attach a pooled secure frame (already configured with its action) to a
-- controller input; mouseButton is the one its keyboard binding clicks with
-- (default LeftButton). Returns a token for detach, or nil for a keyboard
-- input.
function pad.attach(input, frame, mouseButton)
    local token = padLogic.add(routes, input, { kind = "frame", frame = frame, mouseButton = mouseButton or "LeftButton" })
    if token ~= nil then
        pad.sync()
    end
    return token
end

-- A controller input that runs a game binding command (Command actions).
function pad.attachCommand(input, command)
    local token = padLogic.add(routes, input, { kind = "command", command = command })
    if token ~= nil then
        pad.sync()
    end
    return token
end

function pad.detach(token)
    if token ~= nil and padLogic.remove(routes, token) then
        pad.sync()
    end
end

function pad.isPadInput(input)
    return padLogic.isPadInput(input)
end

-- Whether the game's gamepad interface is on (Options, Gamepad, Enable
-- Gamepad UI). Clients without it: never.
function pad.controllerUIEnabled()
    local util = InputUtil
    return util ~= nil and call(util.IsGamepadUIEnabled) == true
end

-- Whether a gamepad is in use (Options, Gamepad, Enable Gamepad). Without
-- one, nothing takes the pad keys from us and nothing changes the layer.
local function gamepadEnabled()
    local gamePad = C_GamePad
    return gamePad ~= nil and call(gamePad.IsEnabled) == true
end

-- Every frame, with a gamepad: the window state, the shortcut layer and the
-- game's window mode change what we own and can take keys from us.
local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_REGEN_DISABLED")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")
frame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        pad.restartLog()
    elseif event == "PLAYER_REGEN_DISABLED" then
        -- The last moment bindings can change: keep only the world keys.
        combatStarting = true
        pad.sync()
    else
        combatStarting = false
        dirty = true
    end
end)
frame:SetScript("OnUpdate", function()
    if not InCombatLockdown() and (dirty or (next(routes) ~= nil and gamepadEnabled())) then
        pad.sync()
    end
end)

-- Spoken names. The game's own key names for pad buttons are icon markup,
-- which speech cannot read.
local L = WowVision:getLocale()

local function names()
    return {
        buttons = {
            PAD1 = L["A button"],
            PAD2 = L["B button"],
            PAD3 = L["X button"],
            PAD4 = L["Y button"],
            PADDUP = L["D-pad up"],
            PADDDOWN = L["D-pad down"],
            PADDLEFT = L["D-pad left"],
            PADDRIGHT = L["D-pad right"],
            PADLSHOULDER = L["Left shoulder"],
            PADRSHOULDER = L["Right shoulder"],
            PADLTRIGGER = L["Left trigger"],
            PADRTRIGGER = L["Right trigger"],
            PADLSTICK = L["Left stick press"],
            PADRSTICK = L["Right stick press"],
            PADBACK = L["View button"],
            PADFORWARD = L["Menu button"],
            PADSOCIAL = L["Share button"],
        },
        modifiers = {
            ALT = L["Left shoulder"],
            SHIFT = L["Left trigger"],
            CTRL = L["Right trigger"],
            LAYER = L["Both shoulders"],
            HOLD = L["Right stick press held"],
        },
        joiner = " + ",
    }
end

function pad.inputText(input)
    return padLogic.inputText(input, names())
end
