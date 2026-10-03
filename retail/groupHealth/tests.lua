local testRunner = WowVision.testing.testRunner
local GroupHealth = WowVision.groupHealth

-- The group health monitor's pure half. A step curve is evaluated here the
-- way the game does it (measured on WoW: Forever, 2026-10-03): the value of
-- the last point at or below the input.
local function evaluate(points, x)
    local y = points[1][2]
    for _, point in ipairs(points) do
        if x >= point[1] then
            y = point[2]
        end
    end
    return y
end

testRunner:addSuite("GroupHealth", {
    ["pitch: lowest health highest, full health lowest, fifteen steps"] = function(t)
        local points = GroupHealth.pitchPoints()
        t:assertEqual(#points, 15)
        t:assertEqual(evaluate(points, 0), 10)
        t:assertEqual(evaluate(points, 0.03), 10)
        t:assertEqual(evaluate(points, 1), -10)
        t:assertEqual(evaluate(points, 0.95), -10)
        -- Monotonic: never higher at more health.
        local last = 11
        for i = 0, 100 do
            local pitch = evaluate(points, i / 100)
            t:assertTrue(pitch <= last)
            last = pitch
        end
    end,

    ["pitch: every step is a whole number inside the SAPI range"] = function(t)
        for _, point in ipairs(GroupHealth.pitchPoints()) do
            t:assertEqual(point[2], math.floor(point[2]))
            t:assertTrue(point[2] >= -10 and point[2] <= 10)
        end
    end,

    ["below gate: audible under the threshold only"] = function(t)
        local points = GroupHealth.belowPoints(0.4)
        t:assertEqual(evaluate(points, 0.1), 100)
        t:assertEqual(evaluate(points, 0.39), 100)
        t:assertEqual(evaluate(points, 0.4), 0)
        t:assertEqual(evaluate(points, 1), 0)
    end,

    ["below gate at 100 percent: everything but full health"] = function(t)
        local points = GroupHealth.belowPoints(1)
        t:assertEqual(evaluate(points, 0.99), 100)
        t:assertEqual(evaluate(points, 1), 0)
    end,

    ["below gate at 0: always silent"] = function(t)
        local points = GroupHealth.belowPoints(0)
        t:assertEqual(evaluate(points, 0), 0)
        t:assertEqual(evaluate(points, 0.5), 0)
    end,

    ["band gate: audible from low up to high"] = function(t)
        local points = GroupHealth.bandPoints(0.35, 0.8)
        t:assertEqual(evaluate(points, 0.2), 0)
        t:assertEqual(evaluate(points, 0.35), 100)
        t:assertEqual(evaluate(points, 0.79), 100)
        t:assertEqual(evaluate(points, 0.8), 0)
        t:assertEqual(evaluate(points, 1), 0)
    end,

    ["band gate: urgent at or above the start leaves nothing"] = function(t)
        local points = GroupHealth.bandPoints(0.8, 0.8)
        t:assertEqual(evaluate(points, 0.5), 0)
        t:assertEqual(evaluate(points, 0.9), 0)
    end,

    ["urgent and normal gates never sound together"] = function(t)
        local urgent = GroupHealth.belowPoints(0.35)
        local normal = GroupHealth.bandPoints(0.35, 0.9)
        for i = 0, 100 do
            local x = i / 100
            t:assertTrue(evaluate(urgent, x) + evaluate(normal, x) <= 100)
        end
    end,

    ["full gate: exactly full health"] = function(t)
        local points = GroupHealth.fullPoints()
        t:assertEqual(evaluate(points, 0.999), 0)
        t:assertEqual(evaluate(points, 1), 100)
    end,

    ["raid numbers: group times five plus place, holes skipped"] = function(t)
        local numbers = GroupHealth.raidNumbers({ [1] = 1, [2] = 2, [3] = 1, [5] = 2, [6] = 8 }, 40)
        t:assertEqual(numbers[1], 1)
        t:assertEqual(numbers[3], 2)
        t:assertEqual(numbers[2], 6)
        t:assertEqual(numbers[5], 7)
        t:assertEqual(numbers[6], 36)
        t:assertNil(numbers[4])
    end,

    ["lane timing: delay after the event, pause after the last one"] = function(t)
        t:assertEqual(GroupHealth.nextFire(10, nil, 1, 2), 11)
        t:assertEqual(GroupHealth.nextFire(10, 9.5, 0, 2), 11.5)
        t:assertEqual(GroupHealth.nextFire(10, 5, 0.5, 2), 10.5)
    end,

    ["segment text carries volume, pitch and words"] = function(t)
        t:assertEqual(
            GroupHealth.segment(100, -4, "3"),
            '<volume level="100"><pitch absmiddle="-4">3</pitch></volume>'
        )
    end,

    ["points key tells gates apart"] = function(t)
        t:assertTrue(
            GroupHealth.pointsKey(GroupHealth.belowPoints(0.4)) ~= GroupHealth.pointsKey(GroupHealth.belowPoints(0.5))
        )
    end,

    ["fraction clamps percent"] = function(t)
        t:assertEqual(GroupHealth.fraction(150), 1)
        t:assertEqual(GroupHealth.fraction(-5), 0)
        t:assertEqual(GroupHealth.fraction(35), 0.35)
    end,
})
