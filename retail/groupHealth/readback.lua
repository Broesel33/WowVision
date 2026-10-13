-- Health step readback for the group health monitor: which ten percent step
-- a member's health is in, learned from how long silent utterances play.
-- A sighted healer sees that step on every health bar at one look; the
-- monitor uses it only to decide WHEN to speak (a member crossed into
-- another step). WHAT it speaks still comes from the secret health through
-- the curves, so a misread costs one extra or one missing announcement,
-- never a wrong number. Only official API: curves of ours, C_VoiceChat
-- speech at volume 0, its playback events and debugprofilestop().
--
-- How (camelot/secretSpeechProbe.lua, measured on WoW: Forever 2026-10-13):
-- UnitHealthPercent(unit, true, curve) turns the health into a silence
-- length, 'a<silence msec="..."/>' is spoken at volume 0 and rate 10, and the
-- time from PLAYBACK_STARTED to PLAYBACK_FINISHED gives the length back:
-- - 74 clean samples over five runs lie on one line, played = 190 ms +
--   0.3314 * silence (rate 10 shortens the silence too); on the lengths used
--   here every sample was within 0.27 of a level. Fixed values, no
--   calibration: if another machine differs, /wv sprobe timing measures it.
-- - msec="0" plays longer than 100 ms of silence, so level 0 is 100 ms.
-- - Events land on frames (about 17 ms at 60 fps), so a level is 300 ms of
--   silence, about 100 ms played.
-- - Volume 0 plays in real time; a secret works inside <silence msec>; ten
--   silent utterances side by side keep their timing (/wv sprobe tpar 10).
-- - Other speech beside ours does no harm. A stop of all speech
--   (C_VoiceChat.StopSpeakingText) cuts every utterance short, and so may
--   speech that interrupts: such samples are thrown away.
--
-- One utterance per step took up to 1.3 seconds at full health, too slow.
-- So a sample is TWO utterances called in the same frame (so both read the
-- same health): the step divided by 4 (0 to 2) and the remainder (0 to 3),
-- each as a level of silence. The longer plays at most about 0.5 seconds.
-- The events carry only an utterance id; ids count up in call order, so the
-- lower id is the first digit (checked in game by /wv sprobe tpair).
--
-- Every engine call of ours goes through one slot line (SLOT_MS apart,
-- longer than START_WINDOW_MS), so the starts of different slots never share
-- a window; a start beyond what the slot expects makes it ambiguous and the
-- sample is thrown away.
--
-- No WoW API in here: the caller hands in an environment (clock, timer,
-- speak, the health through a curve), so tools/groupHealthSim.lua runs it
-- against a simulated engine.

local GroupHealth = WowVision.groupHealth

local R = {
    RATE = 10,
    SILENCE_OFFSET = 100,
    LEVEL_SILENCE = 300,
    BASE_MS = 223,
    LEVEL_MS = 99.4,
    START_WINDOW_MS = 100,
    CUT_WINDOW_MS = 110,
    SLOT_MS = 120,
    GAP_SECONDS = 0.12,
    TIMEOUT_SECONDS = 2,
    -- Clean samples land within 0.27 of a whole level; one further off was cut.
    MAX_OFF_LEVEL = 0.42,
    STEPS = 10,
    -- The step as two digits in base 4: 0 to 2, then 0 to 3.
    BASE = 4,
}
GroupHealth.readbackConstants = R

local function digitsOf(step)
    return math.floor(step / R.BASE), step % R.BASE
end

-- The curve points of digit 1 (step divided by 4) or digit 2 (the
-- remainder): step k (k / 10 up to (k + 1) / 10 health, full health is step
-- 10) as that digit's silence length.
function GroupHealth.readbackDigitPoints(digit)
    local points = {}
    for k = 0, R.STEPS do
        local high, low = digitsOf(k)
        local level = digit == 1 and high or low
        tinsert(points, { k / R.STEPS, R.SILENCE_OFFSET + level * R.LEVEL_SILENCE })
    end
    return points
end

local DIGIT_POINTS = { GroupHealth.readbackDigitPoints(1), GroupHealth.readbackDigitPoints(2) }

-- A level as a fraction: played time back through the fixed line.
function GroupHealth.readbackRaw(playedMs)
    return (playedMs - R.BASE_MS) / R.LEVEL_MS
end

-- The step from the two played times; nil and the reason when they make none.
function GroupHealth.readbackStep(firstMs, secondMs)
    local rawHigh, rawLow = GroupHealth.readbackRaw(firstMs), GroupHealth.readbackRaw(secondMs)
    local high, low = math.floor(rawHigh + 0.5), math.floor(rawLow + 0.5)
    if math.abs(rawHigh - high) > R.MAX_OFF_LEVEL or math.abs(rawLow - low) > R.MAX_OFF_LEVEL then
        return nil, "between levels", rawHigh, rawLow
    end
    local step = high * R.BASE + low
    if high < 0 or low < 0 or low >= R.BASE or step > R.STEPS then
        return nil, "out of range", rawHigh, rawLow
    end
    return step, nil, rawHigh, rawLow
end

-- The engine keys its audio cache on the text without markup: a repeat of
-- the same padding would replay an old silence. So every utterance gets
-- its own padding, and all paddings are the same length (24 positions of
-- a no-break space followed by a space or a second no-break space), so the
-- text is identical in all but its code.
local NBSP = "\194\160"

function GroupHealth.readbackPad(n)
    local parts = {}
    for _ = 1, 24 do
        tinsert(parts, n % 2 == 1 and (NBSP .. NBSP) or (NBSP .. " "))
        n = math.floor(n / 2)
    end
    return table.concat(parts)
end

-- When a reading is worth an announcement: the member is in another step
-- than at the last announcement. The first reading only sets the baseline
-- (a bar at its place is nothing to react to); a death sets step 0, so the
-- resurrection is heard.
function GroupHealth.stepChanged(state, step)
    if state.announcedStep == nil then
        state.announcedStep = step
        return false
    end
    if step == state.announcedStep then
        return false
    end
    state.announcedStep = step
    return true
end

-- When a lane fires (after its pause), it speaks only if the member is in
-- another step than when this lane last spoke: a flip to another step and
-- back while the lane waited changed nothing for the listener.
function GroupHealth.laneStepNew(laneState, step)
    if step == nil or laneState.spokenStep == step then
        return false
    end
    laneState.spokenStep = step
    return true
end

-- One slot line for every readback in the addon (the monitor's, the probe's):
-- two lines calling in the same frame put both starts into each other's
-- windows. Seen in game 2026-10-13: the probe's watch and the monitor, woken
-- by the same health event, lost 63 of 68 samples as ambiguous.
-- The line also records every start once, centrally: which slot's window it
-- fell into and as which start of that slot. Only as many starts as the slot
-- expects can be its own (two for a sample, one for the caller's speech);
-- any later one is foreign, whichever readback owns the slot.
function GroupHealth.newReadbackLine()
    return { nextSlotMs = 0, slots = {}, starts = {}, byId = {} }
end
GroupHealth.readbackLine = GroupHealth.newReadbackLine()

local Readback = WowVision.Class("GroupHealthReadback")
GroupHealth.Readback = Readback

-- env: now() in ms; after(seconds, fn); speak(text) speaks at volume 0 and
-- R.RATE; through(unit, points, digit) the unit's health through a step
-- curve of those points (may be secret, nil when the game refuses the
-- unit); nextCount() a counter that never repeats, not even after a /reload;
-- onReading(unit, reading) with { step, calledMs, rawHigh, rawLow, playedHigh,
-- playedLow }; onDiscard(unit, why, sample) optional; line (optional) a slot
-- line of its own, for the simulation; the addon's readbacks all share
-- GroupHealth.readbackLine.
function Readback:initialize(env)
    self.env = env
    self.line = env.line or GroupHealth.readbackLine
    self.units = {}
    self.inflight = {}
    self.stats = { samples = 0, readings = 0, discarded = {}, maxInflight = 0 }
end

-- Runs fn(slot) (engine calls) in the next free slot of the shared line;
-- `expect` is how many starts the calls make.
function Readback:inSlot(expect, fn)
    local line = self.line
    local now = self.env.now()
    local at = math.max(now, line.nextSlotMs)
    line.nextSlotMs = at + R.SLOT_MS
    local function run()
        local slot = { t = self.env.now(), starts = 0, expect = expect }
        tinsert(line.slots, slot)
        while #line.slots > 32 do
            tremove(line.slots, 1)
        end
        fn(slot)
    end
    if at <= now then
        run()
    else
        self.env.after((at - now) / 1000, run)
    end
end

-- Speech of the caller's own (the monitor's announcements): in a slot, so
-- its start never falls into a sample's window, and is known as ours.
function Readback:speakOwn(fn)
    self:inSlot(1, function()
        fn()
    end)
end

-- Samples of one unit out at once. A new health event while one is out
-- starts another at once; with MAX_PER_UNIT out, it asks for one more
-- afterwards. A reading older than one already used is dropped.
local MAX_PER_UNIT = 2

-- Read the unit's step soon.
function Readback:request(unit)
    local state = self.units[unit]
    if state == nil then
        state = { out = 0, usedMs = -math.huge }
        self.units[unit] = state
    end
    if state.out >= MAX_PER_UNIT then
        state.again = true
        return
    end
    state.out = state.out + 1
    self:inSlot(2, function(slot)
        self:sample(unit, slot)
    end)
end

function Readback:forget()
    self.units = {}
end

-- Both digits are called here, in one frame: they read the same health.
function Readback:sample(unit, slot)
    local env = self.env
    local m = { unit = unit, calledMs = env.now(), owner = self, slot = slot, starts = {}, ids = {}, finishes = {}, finished = 0 }
    slot.sample = m
    self.stats.samples = self.stats.samples + 1
    local silences = {}
    for digit = 1, 2 do
        local ok, silence = pcall(env.through, unit, DIGIT_POINTS[digit], digit)
        if not ok or silence == nil then
            m.error = "no health"
            self:finish(m)
            return
        end
        silences[digit] = silence
    end
    tinsert(self.inflight, m)
    self.stats.maxInflight = math.max(self.stats.maxInflight, #self.inflight)
    for digit = 1, 2 do
        local ok, err = pcall(env.speak, 'a<silence msec="' .. silences[digit] .. '"/>' .. GroupHealth.readbackPad(env.nextCount()))
        if not ok then
            m.error = "speak: " .. tostring(err)
            self:finish(m)
            return
        end
    end
    env.after(R.TIMEOUT_SECONDS, function()
        if not m.done then
            m.error = "timeout"
            self:finish(m)
        end
    end)
end

-- Every readback hears every start; the line records it once.
function Readback:startEntry(id)
    local line = self.line
    local entry = line.byId[id]
    if entry ~= nil then
        return entry
    end
    local now = self.env.now()
    entry = { t = now, id = id }
    for i = #line.slots, 1, -1 do
        local slot = line.slots[i]
        if now >= slot.t and now <= slot.t + R.START_WINDOW_MS then
            slot.starts = slot.starts + 1
            entry.slot = slot
            entry.order = slot.starts
            break
        end
    end
    line.byId[id] = entry
    tinsert(line.starts, entry)
    while #line.starts > 64 do
        line.byId[tremove(line.starts, 1).id] = nil
    end
    return entry
end

function Readback:onStarted(id)
    local entry = self:startEntry(id)
    local slot = entry.slot
    local m = slot ~= nil and slot.sample or nil
    if m == nil or m.owner ~= self or m.done then
        return
    end
    m.ids[id] = true
    -- The slot's first two starts are the digits; a third makes the sample
    -- ambiguous (it then ends with the first of them to finish).
    if entry.order <= slot.expect then
        tinsert(m.starts, { id = id, t = entry.t })
    else
        m.ambiguous = true
    end
end

-- Did anything foreign start right after `finishMs`? Ours are only the
-- expected starts of a slot whose sample stayed unambiguous, or of a slot of
-- the caller's own speech: an interrupting start can fall into a later slot.
function Readback:interrupted(m, finishMs)
    for _, entry in ipairs(self.line.starts) do
        if entry.t > finishMs and entry.t <= finishMs + R.CUT_WINDOW_MS then
            local slot = entry.slot
            local ours = slot ~= nil and entry.order <= slot.expect and (slot.sample == nil or not slot.sample.ambiguous)
            if not ours then
                return true
            end
        end
    end
    return false
end

function Readback:onFinished(id, failed)
    local now = self.env.now()
    for _, m in ipairs(self.inflight) do
        if m.ids[id] then
            if failed then
                m.error = "failed"
            elseif m.ambiguous then
                m.error = "ambiguous"
            elseif m.finishes[id] == nil then
                m.finishes[id] = now
                m.finished = m.finished + 1
            end
            if m.error ~= nil or m.finished == 2 then
                self:finish(m)
            end
            return
        end
    end
end

-- Someone stopped all speech: every sample out is cut, ended at once.
function Readback:onStop()
    local list = self.inflight
    self.inflight = {}
    for _, m in ipairs(list) do
        m.error = "stop"
        self:finish(m)
    end
end

-- A sample lost to a disturbance is taken again at once, at most this many
-- times in a row; a refused unit ("no health") is not.
local RETRY = { stop = true, ambiguous = true, interrupt = true, timeout = true, failed = true, ["between levels"] = true }
local MAX_RETRIES = 2

function Readback:discard(m, why)
    local stats = self.stats
    stats.discarded[why] = (stats.discarded[why] or 0) + 1
    if self.env.onDiscard ~= nil then
        self.env.onDiscard(m.unit, why, m)
    end
    -- No retry while a newer sample of the unit is still out (out counts this one).
    local state = self.units[m.unit]
    if state ~= nil and RETRY[why] and state.out <= 1 and (state.retries or 0) < MAX_RETRIES then
        state.retries = (state.retries or 0) + 1
        state.again = true
    end
end

-- The digits by id: the lower id was called first, the step divided by 4.
function Readback:decode(m)
    if #m.starts ~= 2 then
        return nil, "ambiguous"
    end
    local first, second = m.starts[1], m.starts[2]
    if second.id < first.id then
        first, second = second, first
    end
    for _, start in ipairs({ first, second }) do
        if self:interrupted(m, m.finishes[start.id]) then
            return nil, "interrupt"
        end
    end
    local playedHigh = m.finishes[first.id] - first.t
    local playedLow = m.finishes[second.id] - second.t
    local step, why, rawHigh, rawLow = GroupHealth.readbackStep(playedHigh, playedLow)
    if step == nil then
        return nil, why
    end
    return { step = step, calledMs = m.calledMs, rawHigh = rawHigh, rawLow = rawLow, playedHigh = playedHigh, playedLow = playedLow }
end

function Readback:finish(m)
    if m.done then
        return
    end
    m.done = true
    for i, other in ipairs(self.inflight) do
        if other == m then
            tremove(self.inflight, i)
            break
        end
    end
    local env = self.env
    -- The gap lets the start of speech that cut ours short arrive.
    env.after(R.GAP_SECONDS, function()
        local state = self.units[m.unit]
        if m.error ~= nil then
            self:discard(m, m.error)
        else
            local reading, why = self:decode(m)
            if reading == nil then
                self:discard(m, why)
            elseif state ~= nil and m.calledMs < state.usedMs then
                self:discard(m, "older than the last reading")
            else
                self.stats.readings = self.stats.readings + 1
                if state ~= nil then
                    state.retries = 0
                    state.usedMs = m.calledMs
                end
                env.onReading(m.unit, reading)
            end
        end
        if state ~= nil then
            state.out = math.max(0, state.out - 1)
            if state.again then
                state.again = false
                self:request(m.unit)
            end
        end
    end)
end
