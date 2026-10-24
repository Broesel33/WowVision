-- Controller input, the pure part: how WowVision names a controller input,
-- which held buttons count as modifiers, which input a press picks, which
-- pad keys WowVision takes in which state, the spoken names, and the
-- default controller inputs per binding. core/ui/input/pad.lua does the game
-- side. Pure Lua: the headless tests run it.
--
-- In WoW: Forever's gamepad interface the pad sends no Shift, Ctrl or Alt to
-- the game (probed in the game, 2026-10-21), so WowVision reads the held
-- buttons itself. A controller input is written like a keyboard one, the
-- modifiers before the button: "ALT-PADRSTICK". The modifiers are
--   ALT    the left shoulder held
--   SHIFT  the left trigger held
--   CTRL   the right trigger held
--   LAYER  the game's shortcut layer (both shoulders held)
--   HOLD   the right stick press held (only with the D-pad: buffers)
local padLogic = {}
WowVision.padLogic = padLogic

padLogic.MODIFIER_ORDER = { "ALT", "CTRL", "SHIFT", "LAYER", "HOLD" }

-- The button behind each held modifier.
padLogic.MODIFIER_BUTTONS = {
    ALT = "PADLSHOULDER",
    SHIFT = "PADLTRIGGER",
    CTRL = "PADRTRIGGER",
}

-- Held down, this key turns the D-pad over to the HOLD inputs.
padLogic.HOLD_KEY = "PADRSTICK"
padLogic.HOLD_KEYS = { "PADDUP", "PADDDOWN", "PADDLEFT", "PADDRIGHT" }

-- Keys WowVision holds all the time, also in combat. Everything else on the
-- pad is the game's (action bars, targeting, radial) and WowVision takes it
-- only while one of its windows is open, or during the shortcut layer.
padLogic.WORLD_KEYS = { PADRSTICK = true }

local MODIFIERS = {}
for _, name in ipairs(padLogic.MODIFIER_ORDER) do
    MODIFIERS[name] = true
end

-- Whether an input is a controller one: its button is a pad key.
function padLogic.isPadInput(input)
    if type(input) ~= "string" then
        return false
    end
    local base = input:match("([^%-]+)$")
    return base ~= nil and base:sub(1, 3) == "PAD"
end

-- The modifier names of a set in the fixed order, joined: "ALT-SHIFT", or ""
-- for none.
function padLogic.modKey(set)
    local parts = {}
    for _, name in ipairs(padLogic.MODIFIER_ORDER) do
        if set[name] then
            tinsert(parts, name)
        end
    end
    return table.concat(parts, "-")
end

-- An input as its button and its modifier key: "SHIFT-ALT-PADDUP" is
-- "PADDUP", "ALT-SHIFT". Unknown modifier words make it nil.
function padLogic.parse(input)
    if not padLogic.isPadInput(input) then
        return nil
    end
    local tokens = {}
    for token in input:gmatch("[^%-]+") do
        tinsert(tokens, token)
    end
    local base = tremove(tokens)
    local set = {}
    for _, token in ipairs(tokens) do
        if not MODIFIERS[token] then
            return nil
        end
        set[token] = true
    end
    return base, padLogic.modKey(set)
end

-- The canonical spelling of an input (modifiers in the fixed order), or nil.
function padLogic.normalize(input)
    local base, modKey = padLogic.parse(input)
    if base == nil then
        return nil
    end
    if modKey == "" then
        return base
    end
    return modKey .. "-" .. base
end

-- The modifier key held for a press of base. isDown(key) asks the game;
-- layerOn is the game's shortcut layer state; hold marks a press on the
-- D-pad while the hold key is down. The pressed button never counts as its
-- own modifier (the left shoulder alone is the left shoulder, not Alt), and
-- in the shortcut layer the shoulders are the layer, not Alt.
function padLogic.heldModKey(isDown, base, layerOn, hold)
    local set = {}
    if layerOn then
        set.LAYER = true
    end
    for name, button in pairs(padLogic.MODIFIER_BUTTONS) do
        if button ~= base and isDown(button) == true then
            if not (layerOn and name == "ALT") then
                set[name] = true
            end
        end
    end
    if hold then
        set.HOLD = true
    end
    return padLogic.modKey(set)
end

-- Routes: per pad key, per modifier key, a stack of entries; the newest
-- entry wins (a window opened over another takes the keys, as override
-- bindings do).
function padLogic.newRoutes()
    return {}
end

-- Add an entry for an input; returns a token for remove, or nil when the
-- input is not a controller input.
function padLogic.add(routes, input, entry)
    local base, modKey = padLogic.parse(input)
    if base == nil then
        return nil
    end
    local byMod = routes[base]
    if byMod == nil then
        byMod = {}
        routes[base] = byMod
    end
    local stack = byMod[modKey]
    if stack == nil then
        stack = {}
        byMod[modKey] = stack
    end
    tinsert(stack, entry)
    return { base = base, modKey = modKey, entry = entry }
end

function padLogic.remove(routes, token)
    local byMod = routes[token.base]
    if byMod == nil then
        return false
    end
    local stack = byMod[token.modKey]
    if stack == nil then
        return false
    end
    for i = #stack, 1, -1 do
        if stack[i] == token.entry then
            tremove(stack, i)
            if #stack == 0 then
                byMod[token.modKey] = nil
                if next(byMod) == nil then
                    routes[token.base] = nil
                end
            end
            return true
        end
    end
    return false
end

-- The entry a press picks: the newest one for exactly this modifier key.
-- No fallback to fewer modifiers: a combination that means nothing does
-- nothing rather than something else.
function padLogic.pick(routes, base, modKey)
    local byMod = routes[base]
    if byMod == nil then
        return nil
    end
    local stack = byMod[modKey]
    if stack == nil then
        return nil
    end
    return stack[#stack]
end

local function hasModifier(modKey, name)
    for token in modKey:gmatch("[^%-]+") do
        if token == name then
            return true
        end
    end
    return false
end
padLogic.hasModifier = hasModifier

-- The pad keys WowVision binds now. state: { windowOpen = bool, layerOn =
-- bool, onlyKeys = set? }. HOLD entries never own their key here: the hold
-- key's secure handler binds the D-pad while it is held. onlyKeys is the
-- focused window's own pick (a window over a Blizzard gamepad screen keeps
-- just these and leaves every other pad key to the game, world keys too).
function padLogic.ownedBases(routes, state)
    local owned = {}
    local only = state.onlyKeys
    for base, byMod in pairs(routes) do
        for modKey in pairs(byMod) do
            if not hasModifier(modKey, "HOLD") and (only == nil or only[base]) then
                if padLogic.WORLD_KEYS[base] then
                    owned[base] = true
                elseif hasModifier(modKey, "LAYER") then
                    if state.layerOn then
                        owned[base] = true
                    end
                elseif state.windowOpen then
                    owned[base] = true
                end
            end
        end
    end
    return owned
end

-- The D-pad keys that have HOLD entries (the hold handler binds only those).
function padLogic.holdBases(routes)
    local bases = {}
    for _, base in ipairs(padLogic.HOLD_KEYS) do
        local byMod = routes[base]
        if byMod ~= nil then
            for modKey in pairs(byMod) do
                if hasModifier(modKey, "HOLD") then
                    bases[base] = true
                end
            end
        end
    end
    return bases
end

-- Spoken text of an input. names: { buttons = { PAD1 = "A", ... },
-- modifiers = { ALT = "left shoulder", ... }, joiner = " + " }. A button
-- without a name is spoken as its key name.
function padLogic.inputText(input, names)
    local base, modKey = padLogic.parse(input)
    if base == nil then
        return tostring(input)
    end
    local parts = {}
    for token in modKey:gmatch("[^%-]+") do
        tinsert(parts, names.modifiers[token] or token)
    end
    tinsert(parts, names.buttons[base] or base)
    return table.concat(parts, names.joiner or " + ")
end

-- Default controller inputs per binding key, for the bindings of the core.
-- A binding elsewhere declares its own (registerBinding's padInputs), and
-- one that does not exist on a client simply never asks.
padLogic.DEFAULTS = {
    -- Windows: the D-pad moves, the face buttons are Enter, Backspace,
    -- Escape and Space, the shoulders Tab, the right trigger is Ctrl.
    up = { "PADDUP" },
    down = { "PADDDOWN" },
    left = { "PADDLEFT" },
    right = { "PADDRIGHT" },
    next = { "PADRSHOULDER" },
    previous = { "PADLSHOULDER" },
    nextWindow = { "CTRL-PADRSHOULDER" },
    previousWindow = { "CTRL-PADLSHOULDER" },
    home = { "CTRL-PADDUP" },
    ["end"] = { "CTRL-PADDDOWN" },
    leftClick = { "PAD1" },
    rightClick = { "PAD3" },
    close = { "PAD2" },
    gameClose = { "PAD2" },
    tooltip = { "PAD4" },
    drag = { "PADLSTICK" },
    contextMenu = { "PADFORWARD" },
    ["tooltip/previousLine"] = { "SHIFT-PADDUP" },
    ["tooltip/nextLine"] = { "SHIFT-PADDDOWN" },
    ["tooltip/readLeft"] = { "SHIFT-PADDLEFT" },
    ["tooltip/readRight"] = { "SHIFT-PADDRIGHT" },
    ["chat/previousPart"] = { "CTRL-PADDLEFT" },
    ["chat/nextPart"] = { "CTRL-PADDRIGHT" },
    ["chat/shiftClick"] = { "SHIFT-PAD1" },
    -- In the world, all the time: the right stick press (ping); its
    -- combinations (left shoulder, triggers) are free for features.
    ["maps/turnToWaypoint"] = { "PADRSTICK" },
    -- Buffers: the D-pad while the right stick press is held.
    ["buffers/previousItem"] = { "HOLD-PADDUP" },
    ["buffers/nextItem"] = { "HOLD-PADDDOWN" },
    ["buffers/previousBuffer"] = { "HOLD-PADDLEFT" },
    ["buffers/nextBuffer"] = { "HOLD-PADDRIGHT" },
    ["buffers/previousGroup"] = { "SHIFT-HOLD-PADDLEFT" },
    ["buffers/nextGroup"] = { "SHIFT-HOLD-PADDRIGHT" },
    -- The shortcut layer (both shoulders held), out of combat: the slots
    -- that only show something to sighted players.
    ["maps/openNavigation"] = { "LAYER-PADDUP" },
    ["chat/openWindow"] = { "LAYER-PADDDOWN" },
    ["scanner/open"] = { "LAYER-PAD3" },
    ["wowvision/menu"] = { "LAYER-PAD1" },
    ["bars/openWindow"] = { "LAYER-PADLSTICK" },
}

-- A fresh copy of a binding's default controller inputs.
function padLogic.defaultsFor(key)
    local inputs = { _type = "array" }
    local defaults = key ~= nil and padLogic.DEFAULTS[key] or nil
    if defaults ~= nil then
        for _, input in ipairs(defaults) do
            tinsert(inputs, input)
        end
    end
    return inputs
end
