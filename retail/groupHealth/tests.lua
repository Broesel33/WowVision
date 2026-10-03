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
    ["pitch: every voice has fifteen whole-number steps inside -10..10"] = function(t)
        for key, profile in pairs(GroupHealth.VOICE_PROFILES) do
            t:assertEqual(#profile.scale, 15, key)
            t:assertEqual(#profile.heard, 15, key)
            for _, pitch in ipairs(profile.scale) do
                t:assertEqual(pitch, math.floor(pitch), key)
                t:assertTrue(pitch >= -10 and pitch <= 10, key)
            end
        end
    end,

    ["pitch: heard pitch falls step by step, about a semitone or more"] = function(t)
        for key, profile in pairs(GroupHealth.VOICE_PROFILES) do
            local heard = profile.heard
            -- The two lowest and the two highest steps share a level.
            t:assertEqual(heard[1], heard[2], key)
            t:assertEqual(heard[14], heard[15], key)
            for i = 3, 14 do
                local fall = heard[i - 1] - heard[i]
                t:assertTrue(fall >= 0.95, key .. ": step into " .. i .. " falls only " .. fall)
            end
        end
    end,

    ["profiles: chosen by voice name, Hedda for unknown voices"] = function(t)
        local _, key = GroupHealth.profileFor("Microsoft Zira Desktop - English (United States)")
        t:assertEqual(key, "zira")
        _, key = GroupHealth.profileFor("Microsoft Hedda Desktop - German")
        t:assertEqual(key, "hedda")
        -- The OneCore voices, as named once copied into the SAPI list.
        _, key = GroupHealth.profileFor("Microsoft Hedda - German (Germany)")
        t:assertEqual(key, "hedda")
        _, key = GroupHealth.profileFor("Microsoft Katja - German (Germany)")
        t:assertEqual(key, "katja")
        _, key = GroupHealth.profileFor("Microsoft Stefan - German (Germany)")
        t:assertEqual(key, "hedda")
        _, key = GroupHealth.profileFor("Some Other Voice")
        t:assertEqual(key, "hedda")
        _, key = GroupHealth.profileFor(nil)
        t:assertEqual(key, "hedda")
    end,

    ["copy ranges: below the split the LOW copy, from it the HIGH copy"] = function(t)
        local profile = GroupHealth.VOICE_PROFILES.hedda
        local split = GroupHealth.split(profile)
        local lowCopy, highCopy = GroupHealth.copyRanges(0, 0.35, profile)
        t:assertEqual(lowCopy[2], 0.35)
        t:assertTrue(highCopy[1] >= highCopy[2]) -- nothing for the HIGH copy
        lowCopy, highCopy = GroupHealth.copyRanges(0.35, 0.9, profile)
        t:assertEqual(lowCopy[1], 0.35)
        t:assertEqual(lowCopy[2], split)
        t:assertEqual(highCopy[1], split)
        t:assertEqual(highCopy[2], 0.9)
        -- Every health in a lane plays exactly one copy.
        for i = 0, 100 do
            local x = i / 100
            local a = evaluate(GroupHealth.bandPoints(lowCopy[1], lowCopy[2]), x)
            local b = evaluate(GroupHealth.bandPoints(highCopy[1], highCopy[2]), x)
            if x >= 0.35 and x < 0.9 then
                t:assertEqual(a + b, 100, "health " .. x)
            else
                t:assertEqual(a + b, 0, "health " .. x)
            end
        end
    end,

    ["copy ranges: above 1 the HIGH copy includes full health"] = function(t)
        local _, highCopy = GroupHealth.copyRanges(0, 2, GroupHealth.VOICE_PROFILES.zira)
        t:assertEqual(evaluate(GroupHealth.bandPoints(highCopy[1], highCopy[2]), 1), 100)
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

    ["unique padding: never repeats, only spaces"] = function(t)
        local seen = {}
        for n = 0, 20000 do
            local pad = GroupHealth.uniquePad(n)
            t:assertNil(seen[pad], "padding repeats at " .. n)
            seen[pad] = true
            t:assertNil(pad:gsub("\194\160", ""):find("[^ ]"), "only spaces")
        end
        -- About fifty invisible characters even at a million utterances.
        t:assertTrue(#GroupHealth.uniquePad(1000000) < 120)
    end,

    ["fraction clamps percent"] = function(t)
        t:assertEqual(GroupHealth.fraction(150), 1)
        t:assertEqual(GroupHealth.fraction(-5), 0)
        t:assertEqual(GroupHealth.fraction(35), 0.35)
    end,
})
