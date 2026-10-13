-- Offline simulation of the group health monitor with the health step
-- readback (retail/groupHealth/readback.lua): a party of 5 or a raid of 10,
-- scripted health, a simulated speech engine, the monitor's lanes and queue
-- in miniature. The readback code itself is the real one.
--
-- The engine copies what was measured on WoW: Forever (2026-10-13):
-- - a start comes 34 to 56 ms after the call, events land on frames;
-- - an utterance 'a<silence msec="s"/>' at rate 10 plays 190 + 0.3314 * s ms
--   (plus a few ms of noise); utterances overlap freely;
-- - other WowVision speech plays beside ours; now and then a stop of all
--   speech (hooked, like C_VoiceChat.StopSpeakingText) or an interrupting
--   call (no hook: everything ends, the new speech starts) cuts samples.
-- Not known yet, so not modelled: an engine limit on overlapping utterances.
--
-- Used by tools/groupHealthSimTests.lua (headless suite) and
-- tools/group-health-sim.lua (printed report).

local GroupHealth = WowVision.groupHealth
local R = GroupHealth.readbackConstants

local Sim = {}

-- The monitor's role defaults (retail/groupHealth/module.lua), thresholds in percent.
Sim.ROLES = {
    TANK = { start = 90, urgent = 50, delay = 0.5, pause = 1.5, urgentDelay = 0, urgentPause = 0.5 },
    HEALER = { start = 80, urgent = 40, delay = 1, pause = 2, urgentDelay = 0, urgentPause = 0.5 },
    DAMAGER = { start = 70, urgent = 35, delay = 1, pause = 3, urgentDelay = 0, urgentPause = 1 },
}
Sim.SPACING = 0.3
Sim.ANNOUNCE_MS = 700

-- Deterministic random numbers (a plain LCG), so every run is the same.
local function rng(seed)
    local state = seed
    local r = {}
    function r.next()
        state = (state * 1103515245 + 12345) % 2147483648
        return state / 2147483648
    end
    function r.range(a, b)
        return a + (b - a) * r.next()
    end
    function r.normal(sd)
        local u1, u2 = math.max(r.next(), 1e-9), r.next()
        return sd * math.sqrt(-2 * math.log(u1)) * math.cos(2 * math.pi * u2)
    end
    return r
end

local function trueStep(health)
    if health >= 1 then
        return R.STEPS
    end
    return math.floor(health * R.STEPS)
end

local function evalPoints(points, x)
    local y = points[1][2]
    for _, p in ipairs(points) do
        if x >= p[1] then
            y = p[2]
        end
    end
    return y
end

-- Health scripts: each member gets a list of { t (seconds), health (0..1) }.
local function clamp(h, lo, hi)
    return math.max(lo, math.min(hi, h))
end

-- Strong hits and big heals, health changing every second or so.
function Sim.spikes(r, duration)
    local events = {}
    local h = 1.0
    local nextHit, nextHeal = r.range(0.5, 1.2), r.range(1.0, 2.0)
    while true do
        local t = math.min(nextHit, nextHeal)
        if t > duration then
            break
        end
        if nextHit <= nextHeal then
            h = clamp(h - r.range(0.10, 0.30), 0.03, 1)
            nextHit = t + r.range(0.8, 1.6)
        else
            h = clamp(h + r.range(0.15, 0.35), 0.03, 1)
            nextHeal = t + r.range(1.2, 2.4)
        end
        tinsert(events, { t, h })
    end
    return events
end

-- A slow change: a tick every `every` seconds by `step` (negative drains).
function Sim.drift(start, step, every, duration)
    local events = {}
    local h = start
    local t = every
    while t <= duration do
        h = clamp(h + step, 0.01, 1)
        tinsert(events, { t, h })
        t = t + every
    end
    return events
end

-- Small wobble that stays inside one step: events, but nothing meaningful.
function Sim.wobble(r, base, duration)
    local events = {}
    local stepLow = math.floor(base * 10) / 10
    local t = r.range(1, 4)
    while t <= duration do
        tinsert(events, { t, clamp(base + r.range(-0.03, 0.03), stepLow + 0.005, stepLow + 0.095) })
        t = t + r.range(2, 5)
    end
    return events
end

-- The simulation -----------------------------------------------------------------

local function newWorld(opts)
    local world = {
        now = 0,
        timers = {},
        seq = 0,
        fps = opts.fps or 60,
        r = rng(opts.seed or 1),
        nextId = 1000,
        active = {},
        log = {},
    }
    world.phase = world.r.range(0, 1000 / world.fps)
    function world.after(seconds, fn)
        world.seq = world.seq + 1
        tinsert(world.timers, { at = world.now + seconds * 1000, seq = world.seq, fn = fn })
    end
    function world.at(ms, fn)
        world.after((ms - world.now) / 1000, fn)
    end
    -- The next frame boundary at or after t.
    function world.frame(t)
        local f = 1000 / world.fps
        return world.phase + math.ceil((t - world.phase) / f) * f
    end
    function world.run(untilMs)
        while true do
            local best, bestIndex = nil, nil
            for i, timer in ipairs(world.timers) do
                if best == nil or timer.at < best.at or (timer.at == best.at and timer.seq < best.seq) then
                    best, bestIndex = timer, i
                end
            end
            if best == nil or best.at > untilMs then
                break
            end
            tremove(world.timers, bestIndex)
            world.now = math.max(world.now, best.at)
            best.fn()
        end
        world.now = untilMs
    end
    return world
end

-- The engine: utterances with ids, start and finish events on frames.
local function engineSpeak(world, playedMs, handlers)
    world.nextId = world.nextId + 1
    local id = world.nextId
    local callMs = world.now
    local startMs = callMs + world.r.range(34, 56)
    local u = { id = id }
    world.active[id] = u
    world.at(world.frame(startMs), function()
        handlers.started(id)
    end)
    u.finishTimer = world.frame(startMs + playedMs)
    world.at(u.finishTimer, function()
        if world.active[id] == u then
            world.active[id] = nil
            handlers.finished(id)
        end
    end)
    return id
end

-- Ends every utterance at once (the stop of all speech).
local function engineStopAll(world, handlers)
    for id, u in pairs(world.active) do
        world.active[id] = nil
        world.at(world.frame(world.now), function()
            handlers.finished(id)
        end)
    end
end

function Sim.run(opts)
    local world = newWorld(opts)
    local duration = opts.duration
    local members = {}
    local byUnit = {}
    for _, spec in ipairs(opts.members) do
        local m = {
            unit = spec.unit,
            number = spec.number,
            role = spec.role,
            health = spec.health,
            script = spec.script or {},
            subject = spec.subject,
            lanes = { urgent = {}, normal = {} },
            truth = {},
            calls = {},
            readings = 0,
            misreads = 0,
            triggers = {},
            announcements = {},
        }
        tinsert(members, m)
        byUnit[m.unit] = m
    end
    local result = { members = members, opts = opts }
    local counter = 0
    local readback
    local handlers = {}
    local queue, queued, pumping = {}, {}, false

    local function audible(m, lane)
        local role = Sim.ROLES[m.role]
        local h = m.health
        if lane == "urgent" then
            return h < role.urgent / 100
        end
        return (h >= role.urgent / 100 and h < role.start / 100) or h >= 1
    end

    local function announce(entry)
        local m = entry.member
        local heard = audible(m, entry.lane)
        if heard then
            tinsert(m.announcements, { t = world.now / 1000, health = m.health, lane = entry.lane })
        end
        -- Every announcement is an engine call, silent or not (volume gates).
        readback:speakOwn(function()
            engineSpeak(world, Sim.ANNOUNCE_MS, handlers)
        end)
    end

    local function pump()
        if pumping then
            return
        end
        local entry = tremove(queue, 1)
        if entry == nil then
            return
        end
        queued[entry.key] = nil
        announce(entry)
        pumping = true
        world.after(Sim.SPACING, function()
            pumping = false
            pump()
        end)
    end

    local function enqueue(m, lane)
        local key = m.unit .. ":" .. lane
        if queued[key] then
            return
        end
        queued[key] = true
        tinsert(queue, { member = m, lane = lane, key = key })
        pump()
    end

    local function wake(m, lane)
        local state = m.lanes[lane]
        if state.pending then
            return
        end
        local role = Sim.ROLES[m.role]
        -- As the module in step mode: no delay, only the pause.
        local delay, pause = 0, role.pause
        if lane == "urgent" then
            pause = role.urgentPause
        end
        local now = world.now / 1000
        local at = GroupHealth.nextFire(now, state.last, delay, pause)
        state.pending = true
        world.after(math.max(0, at - now), function()
            state.pending = false
            -- As the module: nothing new for this lane, nothing said.
            if not GroupHealth.laneStepNew(state, m.announcedStep) then
                return
            end
            state.last = world.now / 1000
            enqueue(m, lane)
        end)
    end

    -- Each run its own slot line: the addon's shared one would carry the
    -- times of an earlier run.
    local line = GroupHealth.newReadbackLine()
    local function speakSample(text)
        local silence = tonumber(text:match('msec="(%d+)"'))
        local played = 190 + 0.3314 * silence + world.r.normal(opts.noiseMs or 4)
        engineSpeak(world, played, handlers)
    end
    readback = GroupHealth.Readback:new({
        line = line,
        now = function()
            return world.now
        end,
        after = world.after,
        speak = speakSample,
        through = function(unit, points)
            local m = byUnit[unit]
            -- The engine reads the health at the call: the truth for the
            -- reading of this sample, found again by its call time.
            m.calls[world.now] = m.health
            return evalPoints(points, m.health)
        end,
        nextCount = function()
            counter = counter + 1
            return counter
        end,
        onReading = function(unit, reading)
            local m = byUnit[unit]
            m.readings = m.readings + 1
            -- Truth: the health when the sample was called.
            if reading.step ~= trueStep(m.calls[reading.calledMs]) then
                m.misreads = m.misreads + 1
            end
            if GroupHealth.stepChanged(m, reading.step) then
                tinsert(m.triggers, { t = world.now / 1000, step = reading.step })
                wake(m, "urgent")
                wake(m, "normal")
            end
        end,
    })
    -- A second reader on the subjects, woken by the same events, like the
    -- probe's watch beside the monitor: on the shared line, or (the bug seen
    -- in game) on a line of its own.
    local second
    if opts.secondReader then
        result.second = { readings = 0, misreads = 0 }
        second = GroupHealth.Readback:new({
            line = opts.separateLines and GroupHealth.newReadbackLine() or line,
            now = function()
                return world.now
            end,
            after = world.after,
            speak = speakSample,
            through = function(unit, points)
                local m = byUnit[unit]
                m.secondCalls = m.secondCalls or {}
                m.secondCalls[world.now] = m.health
                return evalPoints(points, m.health)
            end,
            nextCount = function()
                counter = counter + 1
                return counter
            end,
            onReading = function(unit, reading)
                local m = byUnit[unit]
                result.second.readings = result.second.readings + 1
                if reading.step ~= trueStep(m.secondCalls[reading.calledMs]) then
                    result.second.misreads = result.second.misreads + 1
                end
            end,
        })
    end
    local readers = { readback, second }
    handlers.started = function(id)
        for _, reader in ipairs(readers) do
            reader:onStarted(id)
        end
    end
    handlers.finished = function(id)
        for _, reader in ipairs(readers) do
            reader:onFinished(id, false)
        end
    end

    -- Health events (UNIT_HEALTH) and the truth timeline.
    for _, m in ipairs(members) do
        tinsert(m.truth, { t = 0, step = trueStep(m.health) })
        for _, ev in ipairs(m.script) do
            world.after(ev[1], function()
                m.health = ev[2]
                local step = trueStep(m.health)
                if step ~= m.truth[#m.truth].step then
                    tinsert(m.truth, { t = world.now / 1000, step = step })
                end
                readback:request(m.unit)
                if second ~= nil and m.subject then
                    second:request(m.unit)
                end
            end)
        end
    end

    -- Other speech: WowVision's queue beside us, stops of all speech, interrupts.
    local d = opts.disturb or {}
    local function every(range, fn)
        local function tick()
            if world.now / 1000 > duration then
                return
            end
            fn()
            world.after(world.r.range(range[1], range[2]), tick)
        end
        world.after(world.r.range(range[1], range[2]), tick)
    end
    result.stops, result.interrupts, result.foreign = 0, 0, 0
    if d.foreign then
        every(d.foreign, function()
            result.foreign = result.foreign + 1
            engineSpeak(world, world.r.range(800, 2000), handlers)
        end)
    end
    if d.stops then
        every(d.stops, function()
            result.stops = result.stops + 1
            engineStopAll(world, handlers)
            for _, reader in ipairs(readers) do
                reader:onStop()
            end
        end)
    end
    if d.interrupts then
        every(d.interrupts, function()
            result.interrupts = result.interrupts + 1
            engineStopAll(world, handlers)
            engineSpeak(world, world.r.range(800, 2000), handlers)
        end)
    end

    -- The monitor reads everyone once at the start: the baseline.
    for _, m in ipairs(members) do
        readback:request(m.unit)
    end
    world.run(duration * 1000 + 3000)

    result.stats = readback.stats
    if second ~= nil then
        result.second.stats = second.stats
    end
    return Sim.score(result)
end

-- Scoring ------------------------------------------------------------------------

-- A step held at least PERSIST seconds is a meaningful change the monitor
-- must follow: its announced step has to reach it within the segment.
Sim.PERSIST = 1.0

function Sim.score(result)
    local duration = result.opts.duration
    local total = { changes = 0, followed = 0, missed = 0, latencies = {}, triggers = 0, misreads = 0, readings = 0, quietTriggers = 0, heard = 0 }
    for _, m in ipairs(result.members) do
        m.changes, m.followed, m.missed, m.latencies = 0, 0, 0, {}
        for i, seg in ipairs(m.truth) do
            local endT = m.truth[i + 1] ~= nil and m.truth[i + 1].t or duration
            if i > 1 and endT - seg.t >= Sim.PERSIST then
                m.changes = m.changes + 1
                local hit = nil
                for _, trig in ipairs(m.triggers) do
                    if trig.t >= seg.t and trig.t <= endT + 0.3 and trig.step == seg.step then
                        hit = trig
                        break
                    end
                end
                if hit ~= nil then
                    m.followed = m.followed + 1
                    tinsert(m.latencies, hit.t - seg.t)
                    tinsert(total.latencies, hit.t - seg.t)
                else
                    -- Already the announced step (a quick flip that went
                    -- unseen and came back) is not a miss.
                    local announced = nil
                    for _, trig in ipairs(m.triggers) do
                        if trig.t < seg.t then
                            announced = trig.step
                        end
                    end
                    if announced == seg.step then
                        m.changes = m.changes - 1
                    else
                        m.missed = m.missed + 1
                    end
                end
            end
        end
        total.changes = total.changes + m.changes
        total.followed = total.followed + m.followed
        total.missed = total.missed + m.missed
        total.triggers = total.triggers + #m.triggers
        total.misreads = total.misreads + m.misreads
        total.readings = total.readings + m.readings
        total.heard = total.heard + #m.announcements
        if not m.subject then
            total.quietTriggers = total.quietTriggers + #m.triggers
        end
    end
    table.sort(total.latencies)
    result.total = total
    return result
end

local function percentile(list, p)
    if #list == 0 then
        return 0
    end
    return list[math.max(1, math.ceil(#list * p))]
end

function Sim.report(result)
    local t = result.total
    local s = result.stats
    local lines = {}
    local function add(fmt, ...)
        tinsert(lines, string.format(fmt, ...))
    end
    add("%s: %d players, %d fps, %d seconds", result.opts.name, #result.members, result.opts.fps or 60, result.opts.duration)
    add("  meaningful changes (a new 10 percent step held %.0f s or more): %d, followed %d, missed %d", Sim.PERSIST, t.changes, t.followed, t.missed)
    if #t.latencies > 0 then
        add("  detection delay after the change: median %.2f s, 90 percent within %.2f s, worst %.2f s", percentile(t.latencies, 0.5), percentile(t.latencies, 0.9), t.latencies[#t.latencies])
    end
    add("  steps read wrong: %d of %d readings; triggers for members whose health stayed in one step: %d", t.misreads, t.readings, t.quietTriggers)
    local discards = {}
    for why, n in pairs(s.discarded) do
        tinsert(discards, why .. " " .. n)
    end
    table.sort(discards)
    add("  samples %d, used %d, thrown away: %s; most at once %d", s.samples, s.readings, #discards > 0 and table.concat(discards, ", ") or "none", s.maxInflight)
    add("  disturbances: %d other utterances, %d stops of all speech, %d interrupts", result.foreign, result.stops, result.interrupts)
    for _, m in ipairs(result.members) do
        if m.subject or #m.triggers > 0 then
            local heard = {}
            for _, a in ipairs(m.announcements) do
                tinsert(heard, string.format("%.1fs %d%%", a.t, math.floor(a.health * 100 + 0.5)))
            end
            add("  %s (number %d, %s): %d changes, %d followed, %d missed, %d triggers; heard %d: %s", m.unit, m.number, m.role, m.changes, m.followed, m.missed, #m.triggers, #m.announcements, table.concat(heard, ", "))
        end
    end
    return lines
end

-- The four scenarios ------------------------------------------------------------

local PARTY = {
    { unit = "player", number = 1, role = "HEALER" },
    { unit = "party1", number = 2, role = "TANK" },
    { unit = "party2", number = 3, role = "DAMAGER" },
    { unit = "party3", number = 4, role = "DAMAGER" },
    { unit = "party4", number = 5, role = "DAMAGER" },
}

local RAID = {}
for i = 1, 10 do
    local role = (i <= 2 and "TANK") or (i <= 4 and "HEALER") or "DAMAGER"
    tinsert(RAID, { unit = "raid" .. i, number = i, role = role })
end

-- Background members sit in the middle of a step and wobble inside it.
local function group(base, r, duration, subjects)
    local list = {}
    for i, spec in ipairs(base) do
        local m = { unit = spec.unit, number = spec.number, role = spec.role }
        local subject = subjects[i]
        if subject ~= nil then
            m.subject = true
            m.health = subject.health
            m.script = subject.script
        else
            m.health = 0.85
            m.script = Sim.wobble(r, 0.85, duration)
        end
        tinsert(list, m)
    end
    return list
end

local DISTURB = { foreign = { 3, 6 }, stops = { 15, 30 }, interrupts = { 20, 40 } }

-- kind "spikes": one member (the first tank) takes strong hits and big heals.
-- kind "drift": two members change slowly, one drains, one regenerates.
function Sim.scenario(kind, size, fps, seed)
    local r = rng(seed or 7)
    local base = size == 10 and RAID or PARTY
    local subjects = {}
    local duration
    if kind == "spikes" then
        duration = 60
        subjects[2] = { health = 1.0, script = Sim.spikes(r, duration) }
    else
        duration = 90
        subjects[3] = { health = 0.98, script = Sim.drift(0.98, -0.012, 2, duration) }
        subjects[4] = { health = 0.32, script = Sim.drift(0.32, 0.010, 2, duration) }
    end
    return {
        name = (kind == "spikes" and "Scenario 1, strong hits and heals on one member" or "Scenario 2, slow changes on two members")
            .. (size == 10 and ", raid of 10" or ", party of 5"),
        duration = duration,
        fps = fps or 60,
        seed = (seed or 7) + size,
        members = group(base, r, duration, subjects),
        disturb = DISTURB,
    }
end

return Sim
