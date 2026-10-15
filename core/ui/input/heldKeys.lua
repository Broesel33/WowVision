-- Which bound inputs are physically held right now.
--
-- The engine hands a key's RELEASE to whatever binding owns the key at that
-- moment, not to the binding that took the press. An override binding set
-- on a held movement key (the arrows are both the navigation keys and the
-- default movement keys) therefore eats the release: the game never sees
-- Turn Left stop and the character spins until the override is cleared and
-- the key pressed again. Verified in game on WoW: Forever. So overrides
-- wait until the keys they take are up.
--
-- Two signals, and either one counts: IsKeyDown where the client has it
-- (Retail, Forever; Mists and older lack it), and the key's game binding
-- command checked against the movement flags the hooks in core/movement.lua
-- maintain, which covers every command the game runs on press and ends on
-- release. Unit speed and "is moving" are secret on the modern clients, so
-- neither is used.
--
-- Pure Lua: the game functions arrive through an env table (gameEnv builds
-- the real one) so the headless tests run it.
local heldKeys = {}
WowVision.heldKeys = heldKeys

-- Binding commands the game holds between press and release, with the
-- movement flag each one sets.
heldKeys.HELD_COMMANDS = {
    MOVEFORWARD = "moveForward",
    MOVEBACKWARD = "moveBackward",
    STRAFELEFT = "strafeLeft",
    STRAFERIGHT = "strafeRight",
    TURNLEFT = "turnLeft",
    TURNRIGHT = "turnRight",
    JUMP = "ascend",
    SITORSTAND = "descend",
    PITCHUP = "pitchUp",
    PITCHDOWN = "pitchDown",
    MOVEANDSTEER = "moveAndSteer",
}

-- The key an input ends with: "CTRL-SHIFT-TAB" is TAB. The minus key itself
-- ("-", "CTRL--") stays "-".
function heldKeys.baseKey(input)
    if input == nil or input == "" then
        return input
    end
    if input:sub(-1) == "-" then
        return "-"
    end
    return input:match("([^%-]+)$") or input
end

-- The real game functions. Any may be missing on a client.
function heldKeys.gameEnv()
    return {
        isKeyDown = IsKeyDown,
        bindingAction = GetBindingAction,
        flags = WowVision.movement ~= nil and WowVision.movement.flags or nil,
    }
end

-- The held command this key is bound to in the game, as its movement flag
-- name and the command, or nil.
local function heldCommand(key, env)
    if env.bindingAction == nil or env.flags == nil then
        return nil
    end
    local ok, action = pcall(env.bindingAction, key)
    if not ok or action == nil then
        return nil
    end
    local flag = heldKeys.HELD_COMMANDS[action]
    if flag == nil then
        return nil
    end
    return flag, action
end

-- Whether the key of this input is physically down.
-- env: { isKeyDown = function(key)?, bindingAction = function(key)?, flags = table? }
function heldKeys.isHeld(input, env)
    local key = heldKeys.baseKey(input)
    if key == nil then
        return false
    end
    if env.isKeyDown ~= nil then
        local ok, down = pcall(env.isKeyDown, key)
        if ok and down == true then
            return true
        end
    end
    local flag = heldCommand(key, env)
    return flag ~= nil and env.flags[flag] == true
end

-- What the two signals say about these inputs, as one plain line for the key
-- log (/wv keylog): which keys read down, and the state of each movement
-- command they are bound to.
function heldKeys.describe(inputs, env)
    local parts = {}
    for _, input in ipairs(inputs) do
        local key = heldKeys.baseKey(input)
        local notes = {}
        if env.isKeyDown ~= nil then
            local ok, down = pcall(env.isKeyDown, key)
            if not ok then
                tinsert(notes, "key query refused")
            elseif down == true then
                tinsert(notes, "down")
            end
        end
        local flag, action = heldCommand(key, env)
        if flag ~= nil then
            tinsert(notes, action .. (env.flags[flag] == true and " on" or " off"))
        end
        if #notes > 0 then
            tinsert(parts, input .. " " .. table.concat(notes, ", "))
        end
    end
    local head = env.isKeyDown ~= nil and "key state available" or "key state unavailable"
    if #parts == 0 then
        return head
    end
    return head .. ". " .. table.concat(parts, ". ")
end

-- Whether any input in the list is physically down.
function heldKeys.anyHeld(inputs, env)
    for _, input in ipairs(inputs) do
        if heldKeys.isHeld(input, env) then
            return true
        end
    end
    return false
end
