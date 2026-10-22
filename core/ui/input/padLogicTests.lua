local testRunner = WowVision.testing.testRunner
local padLogic = WowVision.padLogic

local function downSet(keys)
    local set = {}
    for _, key in ipairs(keys) do
        set[key] = true
    end
    return function(key)
        return set[key] == true
    end
end

testRunner:addSuite("PadLogic", {
    ["pad inputs are told apart from keyboard ones"] = function(t)
        t:assertTrue(padLogic.isPadInput("PADRSTICK"))
        t:assertTrue(padLogic.isPadInput("ALT-PADRSTICK"))
        t:assertTrue(padLogic.isPadInput("LAYER-PAD1"))
        t:assertFalse(padLogic.isPadInput("ALT-I"))
        t:assertFalse(padLogic.isPadInput("PAGEUP"))
        t:assertFalse(padLogic.isPadInput(nil))
    end,

    ["parse puts the modifiers in the fixed order"] = function(t)
        local base, modKey = padLogic.parse("SHIFT-ALT-PADDUP")
        t:assertEqual(base, "PADDUP")
        t:assertEqual(modKey, "ALT-SHIFT")
        t:assertEqual(padLogic.normalize("SHIFT-HOLD-PADDLEFT"), "SHIFT-HOLD-PADDLEFT")
        t:assertEqual(padLogic.normalize("HOLD-SHIFT-PADDLEFT"), "SHIFT-HOLD-PADDLEFT")
        t:assertEqual(padLogic.normalize("PAD1"), "PAD1")
        t:assertNil(padLogic.parse("META-PAD1"))
    end,

    ["held modifiers: shoulder Alt, triggers Shift and Ctrl"] = function(t)
        local isDown = downSet({ "PADLSHOULDER", "PADRTRIGGER" })
        t:assertEqual(padLogic.heldModKey(isDown, "PADRSTICK", false, false), "ALT-CTRL")
        t:assertEqual(padLogic.heldModKey(downSet({}), "PADRSTICK", false, false), "")
        t:assertEqual(padLogic.heldModKey(downSet({ "PADLTRIGGER" }), "PADDUP", false, true), "SHIFT-HOLD")
    end,

    ["the pressed button is not its own modifier"] = function(t)
        local isDown = downSet({ "PADLSHOULDER" })
        t:assertEqual(padLogic.heldModKey(isDown, "PADLSHOULDER", false, false), "")
        local withCtrl = downSet({ "PADLSHOULDER", "PADRTRIGGER" })
        t:assertEqual(padLogic.heldModKey(withCtrl, "PADLSHOULDER", false, false), "CTRL")
    end,

    ["in the shortcut layer the shoulders are the layer, not Alt"] = function(t)
        local isDown = downSet({ "PADLSHOULDER", "PADRSHOULDER" })
        t:assertEqual(padLogic.heldModKey(isDown, "PADRSTICK", true, false), "LAYER")
    end,

    ["pick takes the newest entry for exactly the held modifiers"] = function(t)
        local routes = padLogic.newRoutes()
        local turn, lead, other = {}, {}, {}
        padLogic.add(routes, "PADRSTICK", turn)
        padLogic.add(routes, "ALT-PADRSTICK", lead)
        t:assertEqual(padLogic.pick(routes, "PADRSTICK", ""), turn)
        t:assertEqual(padLogic.pick(routes, "PADRSTICK", "ALT"), lead)
        t:assertNil(padLogic.pick(routes, "PADRSTICK", "SHIFT"))
        local token = padLogic.add(routes, "PADRSTICK", other)
        t:assertEqual(padLogic.pick(routes, "PADRSTICK", ""), other)
        t:assertTrue(padLogic.remove(routes, token))
        t:assertEqual(padLogic.pick(routes, "PADRSTICK", ""), turn)
    end,

    ["removing the last entry clears the key"] = function(t)
        local routes = padLogic.newRoutes()
        local token = padLogic.add(routes, "PADDUP", {})
        t:assertTrue(padLogic.remove(routes, token))
        t:assertNil(routes.PADDUP)
        t:assertFalse(padLogic.remove(routes, token))
    end,

    ["owned keys: world always, windows and layer by state, hold never"] = function(t)
        local routes = padLogic.newRoutes()
        padLogic.add(routes, "PADRSTICK", {})
        padLogic.add(routes, "PADDUP", {})
        padLogic.add(routes, "LAYER-PADDDOWN", {})
        padLogic.add(routes, "HOLD-PADDLEFT", {})
        local world = padLogic.ownedBases(routes, { windowOpen = false, layerOn = false })
        t:assertTrue(world.PADRSTICK)
        t:assertNil(world.PADDUP)
        t:assertNil(world.PADDDOWN)
        t:assertNil(world.PADDLEFT)
        local window = padLogic.ownedBases(routes, { windowOpen = true, layerOn = false })
        t:assertTrue(window.PADDUP)
        t:assertNil(window.PADDDOWN)
        local layer = padLogic.ownedBases(routes, { windowOpen = false, layerOn = true })
        t:assertTrue(layer.PADDDOWN)
        t:assertNil(layer.PADDLEFT)
        t:assertTrue(padLogic.holdBases(routes).PADDLEFT)
        t:assertNil(padLogic.holdBases(routes).PADDUP)
    end,

    ["owned keys: a window's own pick leaves the rest to the game"] = function(t)
        local routes = padLogic.newRoutes()
        padLogic.add(routes, "PADRSTICK", {})
        padLogic.add(routes, "PADDUP", {})
        padLogic.add(routes, "PAD1", {})
        local owned = padLogic.ownedBases(routes, { windowOpen = true, layerOn = false, onlyKeys = { PAD1 = true } })
        t:assertTrue(owned.PAD1)
        t:assertNil(owned.PADDUP)
        t:assertNil(owned.PADRSTICK)
    end,

    ["spoken text: modifiers first, then the button"] = function(t)
        local names = {
            buttons = { PADRSTICK = "right stick press", PADDUP = "D-pad up" },
            modifiers = { ALT = "left shoulder", HOLD = "right stick press held" },
            joiner = " + ",
        }
        t:assertEqual(padLogic.inputText("ALT-PADRSTICK", names), "left shoulder + right stick press")
        t:assertEqual(padLogic.inputText("HOLD-PADDUP", names), "right stick press held + D-pad up")
        t:assertEqual(padLogic.inputText("PAD9", names), "PAD9")
    end,

    ["defaults: copies, and nothing for unknown bindings"] = function(t)
        local first = padLogic.defaultsFor("maps/turnToWaypoint")
        t:assertEqual(first[1], "PADRSTICK")
        first[1] = "PAD1"
        t:assertEqual(padLogic.defaultsFor("maps/turnToWaypoint")[1], "PADRSTICK")
        t:assertEqual(#padLogic.defaultsFor("no/such/binding"), 0)
        t:assertEqual(#padLogic.defaultsFor(nil), 0)
    end,

    ["every default input parses"] = function(t)
        for key, inputs in pairs(padLogic.DEFAULTS) do
            for _, input in ipairs(inputs) do
                t:assertNotNil(padLogic.parse(input), key .. " " .. input)
                t:assertEqual(padLogic.normalize(input), input, key .. " is written in the fixed order")
            end
        end
    end,

    ["no two world or layer defaults share an input"] = function(t)
        local seen = {}
        for key, inputs in pairs(padLogic.DEFAULTS) do
            for _, input in ipairs(inputs) do
                local base, modKey = padLogic.parse(input)
                local always = padLogic.WORLD_KEYS[base]
                    or padLogic.hasModifier(modKey, "LAYER")
                    or padLogic.hasModifier(modKey, "HOLD")
                if always then
                    t:assertNil(seen[input], input .. " for " .. key .. " and " .. tostring(seen[input]))
                    seen[input] = key
                end
            end
        end
    end,
})
