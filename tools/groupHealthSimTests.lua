-- Headless suite for the group health step readback
-- (retail/groupHealth/readback.lua): its pure parts, and the four offline
-- scenarios of tools/groupHealthSim.lua (party of 5 and raid of 10; strong
-- hits on one member, slow changes on two) at 60 and 30 frames per second.
-- tools/group-health-sim.lua prints the same scenarios as a report.

local testRunner = WowVision.testing.testRunner
local GroupHealth = WowVision.groupHealth
local R = GroupHealth.readbackConstants
local Sim = loadfile("tools/groupHealthSim.lua")("WowVision", {})

local function played(level)
    -- The line measured on Forever, without noise.
    return 190 + 0.3314 * (R.SILENCE_OFFSET + level * R.LEVEL_SILENCE)
end

local function evaluate(points, x)
    local y = points[1][2]
    for _, point in ipairs(points) do
        if x >= point[1] then
            y = point[2]
        end
    end
    return y
end

local results = {}
local function scenario(kind, size, fps)
    local key = kind .. size .. ":" .. fps
    if results[key] == nil then
        results[key] = Sim.run(Sim.scenario(kind, size, fps))
    end
    return results[key].total
end

local suite = {
    ["readback: the fixed values read every level back to itself"] = function(t)
        for level = 0, R.BASE - 1 do
            local raw = GroupHealth.readbackRaw(played(level))
            t:assertTrue(math.abs(raw - level) < 0.15, "level " .. level .. " reads " .. raw)
        end
    end,

    ["readback: every health gives two digits that read back as its step"] = function(t)
        local high, low = GroupHealth.readbackDigitPoints(1), GroupHealth.readbackDigitPoints(2)
        for percent = 0, 100 do
            local health = percent / 100
            local function level(points)
                return (evaluate(points, health) - R.SILENCE_OFFSET) / R.LEVEL_SILENCE
            end
            local step = GroupHealth.readbackStep(played(level(high)), played(level(low)))
            t:assertEqual(step, math.min(10, math.floor(percent / 10)), percent .. " percent")
        end
    end,

    ["readback: the longest digit plays about half a second"] = function(t)
        t:assertTrue(played(R.BASE - 1) < 530)
    end,

    ["readback: digits in the wrong order never pass as the right step"] = function(t)
        -- 0 and 3 is step 3; swapped it is out of range.
        t:assertNil(GroupHealth.readbackStep(played(3), played(0)))
        -- A level between two levels was cut short: no step.
        local step, why = GroupHealth.readbackStep(played(1) + 50, played(0))
        t:assertNil(step)
        t:assertEqual(why, "between levels")
    end,

    ["readback: every padding has the same length and no two are alike"] = function(t)
        -- Characters, not bytes: a no-break space is two bytes, a space one.
        local function chars(s)
            return select(2, s:gsub("[^\128-\191]", ""))
        end
        local seen = {}
        local length = chars(GroupHealth.readbackPad(0))
        for n = 0, 2000 do
            local pad = GroupHealth.readbackPad(n)
            t:assertEqual(chars(pad), length)
            t:assertNil(seen[pad])
            seen[pad] = true
        end
    end,

    ["readback: the first reading sets the baseline, a new step wakes, the same does not"] = function(t)
        local member = {}
        t:assertFalse(GroupHealth.stepChanged(member, 7))
        t:assertFalse(GroupHealth.stepChanged(member, 7))
        t:assertTrue(GroupHealth.stepChanged(member, 6))
        t:assertEqual(member.announcedStep, 6)
    end,

    ["readback: a lane speaks a step once; there and back while it waited is nothing new"] = function(t)
        local lane = {}
        t:assertTrue(GroupHealth.laneStepNew(lane, 5))
        t:assertFalse(GroupHealth.laneStepNew(lane, 5))
        t:assertTrue(GroupHealth.laneStepNew(lane, 4))
        t:assertFalse(GroupHealth.laneStepNew(lane, nil))
    end,

    ["readback: the digit curves start at the first step and end at full health"] = function(t)
        for digit = 1, 2 do
            local points = GroupHealth.readbackDigitPoints(digit)
            t:assertEqual(#points, R.STEPS + 1)
            t:assertEqual(points[1][2], R.SILENCE_OFFSET)
            t:assertEqual(points[#points][1], 1)
        end
    end,
}

-- Seen in game 2026-10-13: the probe's watch beside the monitor, both woken
-- by the same health events, lost almost every sample as ambiguous while
-- each had its own slot line. On the shared line both read.
for _, kind in ipairs({ "spikes", "drift" }) do
    suite["two readbacks on the same member share the slot line: both read, " .. kind] = function(t)
        local opts = Sim.scenario(kind, 5, 60)
        opts.secondReader = true
        local result = Sim.run(opts)
        local second = result.second
        t:assertEqual(result.total.misreads, 0)
        t:assertEqual(second.misreads, 0)
        t:assertEqual(result.total.quietTriggers, 0)
        t:assertTrue(second.stats.readings >= second.stats.samples * 0.8, second.stats.readings .. " of " .. second.stats.samples .. " used")
        t:assertTrue(result.total.followed >= result.total.changes * 0.8, result.total.followed .. " of " .. result.total.changes .. " followed")
    end
end

for _, fps in ipairs({ 60, 30 }) do
    for _, size in ipairs({ 5, 10 }) do
        suite[string.format("scenario slow changes, %d players, %d fps: every step followed, nothing misread", size, fps)] = function(t)
            local total = scenario("drift", size, fps)
            t:assertEqual(total.missed, 0)
            t:assertEqual(total.misreads, 0)
            t:assertEqual(total.quietTriggers, 0)
            t:assertTrue(total.latencies[#total.latencies] < 3, "worst delay " .. total.latencies[#total.latencies])
        end
        suite[string.format("scenario strong hits, %d players, %d fps: fast, nothing misread, quiet members quiet", size, fps)] = function(t)
            local total = scenario("spikes", size, fps)
            t:assertEqual(total.misreads, 0)
            t:assertEqual(total.quietTriggers, 0)
            t:assertTrue(total.followed >= total.changes * 0.8, total.followed .. " of " .. total.changes .. " followed")
            t:assertTrue(total.latencies[math.ceil(#total.latencies / 2)] < 1, "median delay too long")
        end
    end
end

testRunner:addSuite("GroupHealthReadback", suite)
