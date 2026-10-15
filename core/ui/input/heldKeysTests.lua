local testRunner = WowVision.testing.testRunner
local heldKeys = WowVision.heldKeys

local function modernEnv(downKeys)
    return {
        isKeyDown = function(key)
            return downKeys[key] == true
        end,
        -- Present but must not be consulted when isKeyDown answers.
        bindingAction = function()
            error("bindingAction consulted")
        end,
        flags = { turnLeft = true },
    }
end

local function classicEnv(actions, flags)
    return {
        isKeyDown = nil,
        bindingAction = function(key)
            return actions[key]
        end,
        flags = flags,
    }
end

testRunner:addSuite("HeldKeys", {
    ["baseKey strips modifiers and keeps the minus key"] = function(t)
        t:assertEqual(heldKeys.baseKey("LEFT"), "LEFT")
        t:assertEqual(heldKeys.baseKey("CTRL-SHIFT-TAB"), "TAB")
        t:assertEqual(heldKeys.baseKey("SHIFT-F10"), "F10")
        t:assertEqual(heldKeys.baseKey("-"), "-")
        t:assertEqual(heldKeys.baseKey("CTRL--"), "-")
        t:assertEqual(heldKeys.baseKey("\\"), "\\")
    end,

    ["modern client: the key state decides, modifiers ignored"] = function(t)
        local env = modernEnv({ LEFT = true, TAB = true })
        t:assertTrue(heldKeys.isHeld("LEFT", env))
        t:assertTrue(heldKeys.isHeld("CTRL-TAB", env))
        t:assertFalse(heldKeys.isHeld("RIGHT", env))
        t:assertFalse(heldKeys.isHeld("ENTER", env))
    end,

    ["modern client: a refused query falls back to the movement flags"] = function(t)
        local env = {
            isKeyDown = function()
                error("secret")
            end,
            bindingAction = function(key)
                return key == "LEFT" and "TURNLEFT" or nil
            end,
            flags = { turnLeft = true },
        }
        t:assertTrue(heldKeys.isHeld("LEFT", env))
        t:assertFalse(heldKeys.isHeld("UP", env))
    end,

    ["classic client: a key bound to a held command reads from its flag"] = function(t)
        local actions = { LEFT = "TURNLEFT", UP = "MOVEFORWARD", TAB = "TARGETNEARESTENEMY", SPACE = "JUMP" }
        local env = classicEnv(actions, { turnLeft = true, moveForward = false, ascend = true })
        t:assertTrue(heldKeys.isHeld("LEFT", env))
        t:assertFalse(heldKeys.isHeld("UP", env))
        t:assertTrue(heldKeys.isHeld("SPACE", env))
        -- Not a held command: never counts as held.
        t:assertFalse(heldKeys.isHeld("TAB", env))
        t:assertFalse(heldKeys.isHeld("CTRL-TAB", env))
        -- Unbound key.
        t:assertFalse(heldKeys.isHeld("ENTER", env))
    end,

    ["classic client: autorun and follow are not held keys"] = function(t)
        local env = classicEnv({ UP = "MOVEFORWARD" }, { autorun = true, following = true })
        t:assertFalse(heldKeys.isHeld("UP", env))
    end,

    ["nothing to ask: nothing is held"] = function(t)
        t:assertFalse(heldKeys.isHeld("LEFT", {}))
        t:assertFalse(heldKeys.isHeld(nil, modernEnv({})))
    end,

    ["anyHeld over a list"] = function(t)
        local env = modernEnv({ DOWN = true })
        t:assertTrue(heldKeys.anyHeld({ "UP", "DOWN", "LEFT" }, env))
        t:assertFalse(heldKeys.anyHeld({ "UP", "LEFT" }, env))
        t:assertFalse(heldKeys.anyHeld({}, env))
    end,
})
