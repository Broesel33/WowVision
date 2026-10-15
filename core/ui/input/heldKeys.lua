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
-- Modern clients (Retail, Forever) answer IsKeyDown directly. Classic
-- clients lack it; there the key's game binding command is checked against
-- the movement flags the hooks in core/movement.lua maintain, which covers
-- every command the game runs on press and ends on release. Unit speed and
-- "is moving" are secret on the modern clients, so neither is used.
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

-- Whether the key of this input is physically down.
-- env: { isKeyDown = function(key)?, bindingAction = function(key)?, flags = table? }
function heldKeys.isHeld(input, env)
    local key = heldKeys.baseKey(input)
    if key == nil then
        return false
    end
    if env.isKeyDown ~= nil then
        local ok, down = pcall(env.isKeyDown, key)
        if ok then
            return down == true
        end
    end
    if env.bindingAction == nil or env.flags == nil then
        return false
    end
    local ok, action = pcall(env.bindingAction, key)
    if not ok or action == nil then
        return false
    end
    local flag = heldKeys.HELD_COMMANDS[action]
    return flag ~= nil and env.flags[flag] == true
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
