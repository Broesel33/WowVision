-- Headless suite for the group health readback
-- (retail/groupHealth/readback.lua): its pure parts (plans, decoding, Sku's
-- rule), and the offline scenarios of tools/groupHealthSim.lua (party of 5
-- and raid of 10; strong hits on one member, slow changes on two, a healer
-- hovering at a line, stops of all speech) at 60 and 30 frames per second.
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

-- What a sample of `health` reads under `plan`, through the fixed line.
local function readAt(plan, health)
    local function level(digit)
        return (evaluate(plan.digitPoints[digit], health) - R.SILENCE_OFFSET) / R.LEVEL_SILENCE
    end
    return GroupHealth.readbackValue(plan, played(level(1)), played(level(2)))
end

-- A reading of a sample that carried a number (a health event's), and of
-- a plain one (zooming in, a roster check).
local function reading(plan, health)
    return { plan = plan, value = readAt(plan, health), carried = true }
end

local function plain(plan, health)
    return { plan = plan, value = readAt(plan, health) }
end

local PLANS = {
    { "steps", GroupHealth.stepPlan() },
    { "locate", GroupHealth.locatePlan() },
}
for _, case in ipairs({ { 100, 5 }, { 60, 10 }, { 50, 20 }, { 12, 10 }, { 0, 10 }, { 95, 30 }, { 3, 2 } }) do
    tinsert(PLANS, { "change " .. case[1] .. "/" .. case[2], GroupHealth.changePlan(case[1], case[2]) })
end

-- Of the numbers heard, how many repeat the one before: health less than
-- half a minimum change away from the member's last heard number. Lost
-- samples (the number goes out again) and moves while a member is being
-- located do that.
local function repeatShare(result)
    local heard, repeats = 0, 0
    for _, m in ipairs(result.members) do
        local a = Sim.ROLES[m.role].minChange / 100
        local last = nil
        for _, x in ipairs(m.announcements) do
            heard = heard + 1
            if last ~= nil and math.abs(x.health - last) < a / 2 then
                repeats = repeats + 1
            end
            last = x.health
        end
    end
    return heard > 0 and repeats / heard or 0
end

local results = {}
local function scenario(kind, size, fps)
    local key = kind .. size .. ":" .. fps
    if results[key] == nil then
        results[key] = Sim.run(Sim.scenario(kind, size, fps))
    end
    return results[key]
end

local suite = {
    ["readback: the fixed values read every level back to itself"] = function(t)
        for level = 0, 3 do
            local raw = GroupHealth.readbackRaw(played(level))
            t:assertTrue(math.abs(raw - level) < 0.15, "level " .. level .. " reads " .. raw)
        end
    end,

    ["readback: under every plan each health reads back as the value of its band"] = function(t)
        for _, case in ipairs(PLANS) do
            local plan = case[2]
            for percent = 0, 100 do
                local health = percent / 100
                local value, why = readAt(plan, health)
                t:assertEqual(value, evaluate(plan.points, health), case[1] .. ", " .. percent .. " percent: " .. tostring(why))
                local band = plan.intervals[value]
                t:assertTrue(health >= band[1] - 1e-9 and health <= band[2] + 1e-9, case[1] .. ", " .. percent .. " percent outside its band")
            end
        end
    end,

    ["readback: no digit plays longer than about half a second"] = function(t)
        for _, case in ipairs(PLANS) do
            for _, digits in ipairs(case[2].digitPoints) do
                for _, point in ipairs(digits) do
                    t:assertTrue(point[2] <= R.SILENCE_OFFSET + 3 * R.LEVEL_SILENCE, case[1])
                end
            end
        end
        t:assertTrue(played(3) < 530)
    end,

    ["change plan: the middle band is exactly the reference -/+ the threshold"] = function(t)
        local plan = GroupHealth.changePlan(60, 10)
        local middle = readAt(plan, 0.6)
        t:assertEqual(readAt(plan, 0.5), middle)
        t:assertEqual(readAt(plan, 0.699), middle)
        t:assertTrue(readAt(plan, 0.499) ~= middle)
        t:assertTrue(readAt(plan, 0.70) ~= middle)
    end,

    ["change plan: \"moved less\" plays shortest, the nearest moves next"] = function(t)
        local plan = GroupHealth.changePlan(60, 10)
        local function longer(health)
            local value = readAt(plan, health)
            return math.max(math.floor(value / plan.base), value % plan.base)
        end
        t:assertEqual(readAt(plan, 0.6), 0)
        t:assertEqual(longer(0.49), 1)
        t:assertEqual(longer(0.71), 1)
    end,

    ["gate: Sku's rule as a volume gate, silent exactly in the quiet band"] = function(t)
        local plan = GroupHealth.changePlan(60, 10)
        local points = GroupHealth.gatePoints(0, 0.8, plan.quiet)
        t:assertEqual(evaluate(points, 0.49), 100)
        t:assertEqual(evaluate(points, 0.5), 0)
        t:assertEqual(evaluate(points, 0.699), 0)
        t:assertEqual(evaluate(points, 0.7), 100)
        -- Above "Speak Below" silent anyway.
        t:assertEqual(evaluate(points, 0.85), 0)
        -- Full health: a gate of its own, heard only from far enough away.
        t:assertEqual(evaluate(GroupHealth.gatePoints(1, 2, plan.quiet), 1), 100)
        t:assertEqual(evaluate(GroupHealth.gatePoints(1, 2, GroupHealth.changePlan(95, 10).quiet), 1), 0)
    end,

    ["speak first: a hit on a quiet member is heard at once"] = function(t)
        local opts = Sim.scenario("hover", 5, 60)
        opts.disturb = {}
        for _, m in ipairs(opts.members) do
            m.subject = nil
            m.health = 1
            m.script = {}
        end
        local tank = opts.members[2]
        tank.subject = true
        tank.script = { { 5, 0.4 } }
        local result = Sim.run(opts)
        local heard = result.members[2].announcements
        t:assertEqual(#heard, 1)
        t:assertTrue(heard[1].t - 5 < 0.15, "heard after " .. (heard[1].t - 5))
    end,

    ["change plan: full health is a band of its own below a full reference"] = function(t)
        local plan = GroupHealth.changePlan(80, 10)
        local band = plan.intervals[readAt(plan, 1)]
        t:assertEqual(band[1], 1)
        t:assertEqual(band[2], 1)
        -- At a full reference full health is simply "moved less".
        local full = GroupHealth.changePlan(100, 10)
        t:assertEqual(readAt(full, 1), readAt(full, 0.95))
    end,

    ["readback: digits in the wrong order or between levels never pass"] = function(t)
        -- Under the step plan 0 and 3 is step 3; swapped it is out of range.
        local plan = GroupHealth.stepPlan()
        t:assertEqual(GroupHealth.readbackValue(plan, played(0), played(3)), 3)
        t:assertNil(GroupHealth.readbackValue(plan, played(3), played(0)))
        local value, why = GroupHealth.readbackValue(plan, played(1) + 50, played(0))
        t:assertNil(value)
        t:assertEqual(why, "between levels")
    end,

    ["readback: the background's fixed 462 ms is thrown away, not read as level 2"] = function(t)
        for _, case in ipairs(PLANS) do
            local value, why = GroupHealth.readbackValue(case[2], 462, 461)
            t:assertNil(value, case[1])
            t:assertEqual(why, "game in the background")
        end
        -- A real level 2 pair is still read.
        t:assertEqual(GroupHealth.readbackValue(GroupHealth.stepPlan(), played(2), played(2)), 10)
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

    ["rule: the first reading only sets the reference"] = function(t)
        local member = {}
        t:assertFalse(GroupHealth.judge(member, plain(GroupHealth.locatePlan(), 0.7), 10))
        t:assertTrue(math.abs(member.reference - 70) <= 3.2, "reference " .. member.reference)
    end,

    ["rule: less than the minimum change says nothing, the minimum change announces"] = function(t)
        local member = { reference = 60 }
        t:assertFalse(GroupHealth.judge(member, reading(GroupHealth.changePlan(60, 10), 0.52), 10))
        t:assertFalse(GroupHealth.judge(member, reading(GroupHealth.changePlan(60, 10), 0.68), 10))
        t:assertEqual(member.reference, 60)
        t:assertTrue(GroupHealth.judge(member, reading(GroupHealth.changePlan(60, 10), 0.49), 10))
        -- The new reference: the middle of a quarter-threshold band, within 1.25.
        t:assertTrue(math.abs(member.reference - 49) <= 1.25, "reference " .. member.reference)
        t:assertFalse(member.locate)
    end,

    ["rule: small moves add up, as in Sku"] = function(t)
        local member = { reference = 80 }
        for _, health in ipairs({ 0.77, 0.74, 0.72 }) do
            t:assertFalse(GroupHealth.judge(member, reading(GroupHealth.changePlan(member.reference, 10), health), 10))
        end
        t:assertTrue(GroupHealth.judge(member, reading(GroupHealth.changePlan(member.reference, 10), 0.69), 10))
    end,

    ["rule: a jump past the outer bands announces, then zooming in settles quietly within a quarter threshold"] = function(t)
        local member = { reference = 100 }
        t:assertTrue(GroupHealth.judge(member, reading(GroupHealth.changePlan(100, 5), 0.4), 5))
        local zooms = 0
        while member.locate do
            zooms = zooms + 1
            t:assertFalse(GroupHealth.judge(member, plain(GroupHealth.planFor(member, 5), 0.4), 5))
        end
        t:assertTrue(zooms <= 2, zooms .. " zooms")
        t:assertTrue(math.abs(member.reference - 40) <= 1.25, "reference " .. member.reference)
    end,

    ["rule: a new member is found in at most two zooms, quietly"] = function(t)
        for _, health in ipairs({ 0.03, 0.37, 0.5, 0.86, 1 }) do
            local member = {}
            local samples = 0
            repeat
                samples = samples + 1
                t:assertFalse(GroupHealth.judge(member, plain(GroupHealth.planFor(member, 10), health), 10))
            until not member.locate
            t:assertTrue(samples <= 2, samples .. " samples")
            t:assertTrue(math.abs(member.reference - health * 100) <= 2.5, health .. ": reference " .. member.reference)
        end
    end,

    ["rule: while locating, a reading outside the jump's band is a new move"] = function(t)
        local member = { reference = 100 }
        t:assertTrue(GroupHealth.judge(member, reading(GroupHealth.changePlan(100, 5), 0.4), 5))
        -- Healed back to full before the zoom sample: the band above the zoom.
        t:assertTrue(GroupHealth.judge(member, reading(GroupHealth.planFor(member, 5), 1), 5))
        -- Zooming into that band pins it down, quietly.
        local zooms = 0
        while member.locate do
            zooms = zooms + 1
            t:assertFalse(GroupHealth.judge(member, plain(GroupHealth.planFor(member, 5), 1), 5))
        end
        t:assertTrue(zooms <= 2, zooms .. " zooms")
        t:assertTrue(member.reference >= 99, "reference " .. member.reference)
    end,

    ["rule: a plain sample that sees a move leaves the reference to the move's own number"] = function(t)
        local member = { reference = 50 }
        t:assertFalse(GroupHealth.judge(member, plain(GroupHealth.changePlan(50, 10), 0.3), 10))
        t:assertEqual(member.reference, 50)
    end,

    ["rule: a carried sample is judged by the gate its number went out behind"] = function(t)
        -- The number went out around 60; another reading moved the
        -- reference to 50 meanwhile. 0.49 is outside 60 -/+ 10: heard.
        local member = { reference = 50 }
        t:assertTrue(GroupHealth.judge(member, reading(GroupHealth.changePlan(60, 10), 0.49), 10))
    end,

    ["rule: after a death (reference 0) the resurrection announces"] = function(t)
        local member = { reference = 0, locate = false }
        t:assertTrue(GroupHealth.judge(member, reading(GroupHealth.changePlan(0, 10), 0.35), 10))
    end,

    ["rule: a lane speaks a move once; there and back while it waited is nothing new"] = function(t)
        local lane = {}
        t:assertTrue(GroupHealth.laneRefNew(lane, 50, 10))
        t:assertFalse(GroupHealth.laneRefNew(lane, 52, 10))
        t:assertTrue(GroupHealth.laneRefNew(lane, 40, 10))
        t:assertFalse(GroupHealth.laneRefNew(lane, nil, 10))
    end,

    ["a voice that does not fit the fixed values: stuck purges, and the failure is said once"] = function(t)
        local opts = Sim.scenario("spikes", 5, 60)
        opts.baseMs = 290
        local result = Sim.run(opts)
        t:assertEqual(result.failingSaid, 1)
        t:assertTrue((result.stats.purges.stuck or 0) >= 1, "no stuck purge")
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
        t:assertTrue(second.stats.readings >= second.stats.samples * 0.8, second.stats.readings .. " of " .. second.stats.samples .. " used")
    end
end

for _, fps in ipairs({ 60, 30 }) do
    for _, size in ipairs({ 5, 10 }) do
        local where = string.format("%d players, %d fps", size, fps)
        suite["scenario slow changes, " .. where .. ": announced after about the minimum change, nothing misread"] = function(t)
            local total = scenario("drift", size, fps).total
            t:assertEqual(total.misreads, 0)
            t:assertTrue(#total.moves > 0, "nothing announced")
            t:assertTrue(total.moves[1] >= 0.9, "an announcement after a move of " .. total.moves[1])
            t:assertTrue(Sim.percentile(total.moves, 0.5) <= 1.3, "median move " .. Sim.percentile(total.moves, 0.5))
        end
        suite["scenario strong hits, " .. where .. ": fast, nothing misread, few repeats"] = function(t)
            local result = scenario("spikes", size, fps)
            local total = result.total
            t:assertEqual(total.misreads, 0)
            t:assertTrue(total.extra <= 2, total.extra .. " extra")
            -- One fight each: a raid of 10 follows 43 to 73 percent per fight
            -- (eight fights: 86 percent at 60 fps).
            t:assertTrue(total.followed >= total.ideal * 0.4, total.followed .. " of " .. total.ideal .. " followed")
            t:assertTrue(Sim.percentile(total.latencies, 0.5) < 0.9, "median delay " .. Sim.percentile(total.latencies, 0.5))
            t:assertTrue(repeatShare(result) <= 0.2, "repeats " .. repeatShare(result))
            t:assertTrue((result.carried or 0) > 0, "no number went out")
            t:assertEqual(result.gateMismatches or 0, 0)
        end
        suite["scenario a healer hovering at a line, " .. where .. ": nothing said"] = function(t)
            local result = scenario("hover", size, fps)
            t:assertEqual(result.total.misreads, 0)
            for _, m in ipairs(result.members) do
                if m.subject then
                    t:assertEqual(#m.triggers, 0)
                end
            end
        end
        suite["scenario stops of all speech every 1 to 3 seconds, " .. where .. ": followed, few repeats"] = function(t)
            local result = scenario("stops", size, fps)
            local total = result.total
            t:assertEqual(total.misreads, 0)
            t:assertTrue((result.stats.discarded.stop or 0) > 0, "no sample was cut")
            t:assertTrue(total.followed >= total.ideal * 0.4, total.followed .. " of " .. total.ideal .. " followed")
            t:assertTrue(repeatShare(result) <= 0.25, "repeats " .. repeatShare(result))
        end
    end
end

testRunner:addSuite("GroupHealthReadback", suite)
