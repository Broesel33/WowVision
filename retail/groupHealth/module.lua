local GroupHealth = WowVision.groupHealth

local module = WowVision.base:createModule("groupHealth")
local L = module.L
module:setLabel(L["Group Health Monitor"])
-- Off until the player turns it on (the module's own Enabled toggle, which
-- also switches its events and the snapshot key): it speaks on its own.
module.enabled = false
local settings = module:hasSettings()

-- The group health monitor: a hurt group member is spoken as their number,
-- the pitch telling how hurt (the lower the health, the higher), silent while
-- they are healthy. The idea and the numbering come from Sku's health
-- monitor: the player is 1, party members 2 to 5, raid members
-- (group - 1) * 5 + their place in the group, numbered anew only out of
-- combat so a number never moves during a fight.
--
-- Health is secret here (see logic.lua), so nothing below ever learns a
-- member's health. A health event wakes two lanes per member, each behind
-- a volume gate the engine evaluates:
-- - urgent: below the role's urgent threshold, short delay and pause;
-- - normal: from the urgent threshold up to the role's start threshold,
--   longer delay and pause, plus "<number> full" at exactly full health.
-- Only the lane whose range matches is audible. An optional repeat speaks
-- every member below the role's repeat threshold at the role's interval.
-- The snapshot key speaks everyone once, ungated.
--
-- Everything goes through one queue that starts an utterance every
-- `spacing` seconds, one entry per member and lane (an entry already
-- waiting keeps its place and reads the health when it plays). Silent
-- entries take their slot too: a word at volume 0 lasts as long as a
-- spoken one.
--
-- Speech uses a game voice of its own, straight to the engine beside the
-- speech queue (speech:speakAside): pitch needs a real SAPI voice, which an
-- NVDA bridge voice is not.
--
-- With "only when health changed enough" (on by default) a member is
-- spoken only when their health moved the role's minimum change since
-- their last announcement: Sku's rule (its "Health Pitch style" monitor:
-- tank 5, healer 10, damage dealer 20, no role 30 percent, small moves
-- adding up), what a healer sees on a health bar at one look. Sku also asks
-- for a number of its 15 pitch steps; with its defaults that never decides
-- (10 percent always crosses one 6.7 percent step), so it is left out.
-- Speak first, check afterwards: the last announcement's health (the
-- member's reference) is a plain number once known, so the rule is a
-- volume gate like the lanes' ones. A health event speaks the number at
-- once behind "outside reference -/+ minimum change" and the game decides
-- whether it is heard; a silent sample in the same frame (readback.lua)
-- reads the same health and only tells afterwards whether it was, moving
-- the reference.

local ROLE_KEYS = { TANK = "tank", HEALER = "healer", DAMAGER = "damager", NONE = "none" }

local ROLE_DEFAULTS = {
    TANK = {
        startThreshold = 90,
        urgentThreshold = 50,
        delay = 0.5,
        pause = 1.5,
        urgentDelay = 0,
        urgentPause = 0.5,
        repeatThreshold = 80,
        repeatInterval = 0,
        minChange = 5,
    },
    HEALER = {
        startThreshold = 80,
        urgentThreshold = 40,
        delay = 1,
        pause = 2,
        urgentDelay = 0,
        urgentPause = 0.5,
        repeatThreshold = 70,
        repeatInterval = 0,
        minChange = 10,
    },
    DAMAGER = {
        startThreshold = 70,
        urgentThreshold = 35,
        delay = 1,
        pause = 3,
        urgentDelay = 0,
        urgentPause = 1,
        repeatThreshold = 60,
        repeatInterval = 0,
        minChange = 20,
    },
    NONE = {
        startThreshold = 70,
        urgentThreshold = 35,
        delay = 1,
        pause = 3,
        urgentDelay = 0,
        urgentPause = 1,
        repeatThreshold = 60,
        repeatInterval = 0,
        minChange = 30,
    },
}

-- Settings ----------------------------------------------------------------------

-- Saved by the voice's name: the pitch scales are tuned per voice, and
-- installing a voice moves the game's voice numbers.
settings:add({
    key = "voice",
    type = "TtsVoice",
    label = L["Voice"],
    default = 0,
})

settings:add({
    key = "rate",
    type = "Number",
    label = L["Speech Rate"],
    -- Short numbers: five hurt members fit in little time.
    default = 7,
    min = -10,
    max = 10,
})
settings:add({
    key = "volume",
    type = "Number",
    label = L["Speech Volume"],
    default = 100,
    min = 0,
    max = 100,
})
settings:add({
    key = "spacing",
    type = "Number",
    label = L["Time Between Numbers (seconds)"],
    -- Sku's 0.2: with the readback a number may be heard 0.05 s after the
    -- health event, so the spacing is most of the wait in a mass hit.
    default = 0.2,
    min = 0.05,
    max = 2,
})
settings:add({
    key = "includeSelf",
    type = "Bool",
    label = L["Include Yourself"],
    default = true,
})
settings:add({
    key = "watchParty",
    type = "Bool",
    label = L["Watch Party"],
    default = true,
})
settings:add({
    key = "watchRaid",
    type = "Bool",
    label = L["Watch Raid"],
    default = true,
})
settings:add({
    key = "announceFull",
    type = "Bool",
    label = L["Announce Full Health"],
    default = true,
})
settings:add({
    key = "announceDeaths",
    type = "Bool",
    label = L["Announce Deaths"],
    default = true,
})
settings:add({
    key = "silentOutOfCombat",
    type = "Bool",
    label = L["Silent Out of Combat"],
    default = false,
})
-- Speak a member only when their health moved by the role's minimum change
-- since their last announcement (readback.lua), the way a healer reacts to
-- a health bar: not on every small change. The key predates the rule (it
-- was a ten percent step) and stays, so the saved choice carries over.
settings:add({
    key = "onlyOnSteps",
    type = "Bool",
    label = L["Only When Health Changed Enough"],
    default = true,
})

local raidGroupFields = {}
for group = 1, GroupHealth.MAX_RAID_GROUPS do
    tinsert(raidGroupFields, {
        key = "group" .. group,
        type = "Bool",
        label = string.format(L["Group %d"], group),
        default = true,
    })
end
settings:add({
    key = "raidGroups",
    type = "Category",
    label = L["Raid Groups"],
    fields = raidGroupFields,
})

local ROLE_LABELS = {
    TANK = L["Tanks"],
    HEALER = L["Healers"],
    DAMAGER = L["Damage Dealers"],
    NONE = L["No Role"],
}

for _, role in ipairs(GroupHealth.ROLES) do
    local defaults = ROLE_DEFAULTS[role]
    settings:add({
        key = ROLE_KEYS[role],
        type = "Category",
        label = ROLE_LABELS[role],
        fields = {
            {
                key = "startThreshold",
                type = "Number",
                label = L["Speak Below (percent)"],
                default = defaults.startThreshold,
                min = 0,
                max = 100,
            },
            {
                key = "minChange",
                type = "Number",
                label = L["Minimum Change (percent)"],
                default = defaults.minChange,
                min = 2,
                max = 50,
            },
            {
                key = "delay",
                type = "Number",
                label = L["Delay (seconds)"],
                default = defaults.delay,
                min = 0,
                max = 10,
            },
            {
                key = "pause",
                type = "Number",
                label = L["Pause (seconds)"],
                default = defaults.pause,
                min = 0,
                max = 30,
            },
            {
                key = "urgentThreshold",
                type = "Number",
                label = L["Urgent Below (percent)"],
                default = defaults.urgentThreshold,
                min = 0,
                max = 100,
            },
            {
                key = "urgentDelay",
                type = "Number",
                label = L["Urgent Delay (seconds)"],
                default = defaults.urgentDelay,
                min = 0,
                max = 10,
            },
            {
                key = "urgentPause",
                type = "Number",
                label = L["Urgent Pause (seconds)"],
                default = defaults.urgentPause,
                min = 0,
                max = 30,
            },
            {
                key = "repeatThreshold",
                type = "Number",
                label = L["Repeat Below (percent)"],
                default = defaults.repeatThreshold,
                min = 0,
                max = 100,
            },
            {
                key = "repeatInterval",
                type = "Number",
                label = L["Repeat Every (seconds, 0 is off)"],
                default = defaults.repeatInterval,
                min = 0,
                max = 300,
            },
        },
    })
end

-- A role's setting, falling back to the default when a saved category
-- predates the key.
local function roleSetting(role, key)
    local values = module.settings[ROLE_KEYS[role]]
    local value = values ~= nil and values[key] or nil
    if value == nil then
        value = ROLE_DEFAULTS[role][key]
    end
    return value
end

local function raidGroupWatched(group)
    local groups = module.settings.raidGroups
    return groups == nil or groups["group" .. group] ~= false
end

-- Curves ------------------------------------------------------------------------

local isSecret = WowVision.secrets.isSecret

local curves = {}

local function curveFor(points)
    local key = GroupHealth.pointsKey(points)
    local curve = curves[key]
    if curve == nil then
        curve = C_CurveUtil.CreateCurve()
        curve:SetType(Enum.LuaCurveType.Step)
        for _, point in ipairs(points) do
            curve:AddPoint(point[1], point[2])
        end
        curves[key] = curve
    end
    return curve
end

-- The voice profile of the chosen voice (voices.lua), looked up by its name.
local profileCache = {}

function module:profile()
    local voice = self.settings.voice or 0
    local cached = profileCache[voice]
    if cached == nil then
        local name
        for _, v in ipairs(C_VoiceChat.GetTtsVoices() or {}) do
            if v.voiceID == voice then
                name = v.name
            end
        end
        local profile = GroupHealth.voices:forVoice(name)
        cached = { profile = profile, pitch = GroupHealth.pitchPoints(profile) }
        profileCache[voice] = cached
    end
    return cached.profile, cached.pitch
end
local fullPoints = GroupHealth.fullPoints()

-- The member's health through a curve; nil when the game refuses the unit
-- (party and raid units are restricted for addons in PvP).
local function through(unit, points)
    local ok, value = pcall(UnitHealthPercent, unit, true, curveFor(points))
    if not ok then
        return nil
    end
    return value
end

-- Members -----------------------------------------------------------------------

module.members = {}
module.aliases = {}
module.rosterDirty = false

local VALID_ROLES = { TANK = true, HEALER = true, DAMAGER = true }

local function roleOf(unit, rosterRole)
    local ok, role = pcall(UnitGroupRolesAssigned, unit)
    if not ok or isSecret(role) or not VALID_ROLES[role] then
        role = "NONE"
    end
    if role == "NONE" and rosterRole == "MAINTANK" and not isSecret(rosterRole) then
        role = "TANK"
    end
    return role
end

-- A comparison the game may refuse or answer secretly counts as "no".
local function sameUnit(a, b)
    local ok, same = pcall(UnitIsUnit, a, b)
    return ok and not isSecret(same) and same == true
end

local function plainTrue(func, unit)
    local ok, value = pcall(func, unit)
    return ok and not isSecret(value) and value == true
end

local function plainFalse(func, unit)
    local ok, value = pcall(func, unit)
    return ok and not isSecret(value) and value == false
end

local function newMember(unit, number, role, old)
    local member = {
        unit = unit,
        number = number,
        role = role,
        lanes = { urgent = {}, normal = {} },
        dead = false,
    }
    -- The same person keeps their timing and reference across a roster update.
    if old ~= nil and old.number == number then
        member.lanes.urgent.last = old.lanes.urgent.last
        member.lanes.normal.last = old.lanes.normal.last
        member.lanes.urgent.spokenRef = old.lanes.urgent.spokenRef
        member.lanes.normal.spokenRef = old.lanes.normal.spokenRef
        member.reference = old.reference
        member.locate = old.locate
        member.locateBand = old.locateBand
        member.lastRepeat = old.lastRepeat
        member.dead = old.dead
    end
    return member
end

function module:buildRaid(members, aliases)
    local roster = {}
    local rosterRoles = {}
    for index = 1, MAX_RAID_MEMBERS or 40 do
        local ok, _, _, subgroup, _, _, _, _, _, _, rosterRole = pcall(GetRaidRosterInfo, index)
        if ok and subgroup ~= nil and not isSecret(subgroup) then
            roster[index] = subgroup
            rosterRoles[index] = rosterRole
        end
    end
    local numbers = GroupHealth.raidNumbers(roster, MAX_RAID_MEMBERS or 40)
    for index, number in pairs(numbers) do
        local unit = "raid" .. index
        local isSelf = sameUnit(unit, "player")
        if raidGroupWatched(roster[index]) and (self.settings.includeSelf or not isSelf) then
            members[unit] = newMember(unit, number, roleOf(unit, rosterRoles[index]), self.members[unit])
            -- Events may name the same person by another token.
            if isSelf then
                aliases.player = members[unit]
            end
            for party = 1, 4 do
                if sameUnit(unit, "party" .. party) then
                    aliases["party" .. party] = members[unit]
                end
            end
        end
    end
end

function module:buildParty(members)
    if self.settings.includeSelf then
        members.player = newMember("player", 1, roleOf("player"), self.members.player)
    end
    if IsInGroup() and self.settings.watchParty then
        for party = 1, 4 do
            local unit = "party" .. party
            if UnitExists(unit) then
                members[unit] = newMember(unit, party + 1, roleOf(unit), self.members[unit])
            end
        end
    end
end

function module:collect()
    local members, aliases = {}, {}
    if IsInRaid() and self.settings.watchRaid then
        self:buildRaid(members, aliases)
    else
        self:buildParty(members)
    end
    return members, aliases
end

-- Raid numbers change only out of combat; a party's follow its tokens.
function module:rebuild()
    local raid = IsInRaid() and self.settings.watchRaid
    if raid and InCombatLockdown() and self.raidMode then
        self.rosterDirty = true
        return
    end
    self.rosterDirty = false
    self.raidMode = raid
    self.members, self.aliases = self:collect()
    -- Everyone once: a new member's reference, later moves are measured from it.
    self:readEveryone()
end

-- A sample of every living member (after a roster change, or a purge of a
-- readback stuck failing).
function module:readEveryone()
    local readback = self:stepReadback()
    if readback == nil or self:silenced() then
        return
    end
    for unit, member in pairs(self.members) do
        if not member.dead then
            readback:request(unit)
        end
    end
end

function module:memberFor(unit)
    return self.members[unit] or self.aliases[unit]
end

-- The queue ---------------------------------------------------------------------

module.queue = {}
module.queued = {}

local function entryKey(member, lane)
    return member.unit .. ":" .. lane
end

function module:clearQueue()
    self.queue = {}
    self.queued = {}
end

-- `force` entries play even when a roster update dropped the member: the
-- snapshot finishes what it started.
function module:enqueue(member, lane, force, info)
    local key = entryKey(member, lane)
    if self.queued[key] then
        return
    end
    self.queued[key] = true
    tinsert(self.queue, { member = member, lane = lane, key = key, force = force, info = info, queuedAt = GetTime() })
    self:pump()
end

function module:pump()
    if self.pumping then
        return
    end
    local entry = tremove(self.queue, 1)
    if entry == nil then
        return
    end
    self.queued[entry.key] = nil
    -- A member dropped by a roster update is skipped.
    if entry.force or self:memberFor(entry.member.unit) == entry.member then
        self:logPlay(entry)
        self:announce(entry.member, entry.lane)
    end
    self.pumping = true
    C_Timer.After(self.settings.spacing or 0.3, function()
        self.pumping = false
        self:pump()
    end)
end

-- Speaking ----------------------------------------------------------------------

local function bust(words)
    return WowVision.ttsCacheBust.bust(words)
end

-- The utterance counter behind the unique padding (logic.lua). Kept in the
-- character's saved data: the engine's audio cache outlives a /reload.
function module:nextCount()
    local data = self.data
    if data == nil then
        self.fallbackCount = (self.fallbackCount or math.floor(GetTime() * 1000)) + 1
        return self.fallbackCount
    end
    data.utterances = (data.utterances or 0) + 1
    return data.utterances
end

function module:nextPad()
    return GroupHealth.uniquePad(self:nextCount())
end

-- `tag` ({ member, lane }) comes back when a stop of all speech cuts it.
-- `direct`: straight to the engine, in the caller's slot (a number carried
-- by a readback sample).
function module:speak(text, tag, direct)
    local speech = WowVision.base.speech
    if speech == nil or speech.speakAside == nil then
        return
    end
    local voice, rate, volume = self.settings.voice or 0, self.settings.rate, self.settings.volume
    if direct then
        speech:speakAside(voice, text, rate, volume)
        return
    end
    -- Beside the readback its own speech takes a slot of the same line, so
    -- its start is never taken for a sample's (readback.lua).
    local readback = self:stepReadback()
    if readback ~= nil then
        readback:speakOwn(function()
            speech:speakAside(voice, text, rate, volume)
        end, tag)
        return
    end
    speech:speakAside(voice, text, rate, volume)
end

-- Readback (readback.lua) --------------------------------------------------------

-- A role's minimum change in whole percent, never below the setting's floor.
local function minChange(role)
    return math.max(2, math.floor(roleSetting(role, "minChange") + 0.5))
end

-- The plan of a member's next sample: against their reference, or
-- zooming in to find it (a new member, or after a jump past the outer bands).
function module:readbackPlan(unit)
    local member = self:memberFor(unit)
    if member == nil then
        return GroupHealth.locatePlan()
    end
    return GroupHealth.planFor(member, minChange(member.role))
end

-- Who is read first when several wait for the line (lower first): a
-- member below their urgent threshold, then tanks, then healers, then the
-- lower health; a member not yet located last. As Sku's role priority, but
-- by health too.
function module:readbackPriority(unit)
    local member = self:memberFor(unit)
    if member == nil or member.reference == nil then
        return 1000
    end
    local score = member.reference
    if member.reference < roleSetting(member.role, "urgentThreshold") then
        score = score - 200
    end
    if member.role == "TANK" then
        score = score - 30
    elseif member.role == "HEALER" then
        score = score - 15
    end
    return score
end

-- The readback while the setting is on, made on first use; nil where it
-- cannot work (no curves, no speech module).
function module:stepReadback()
    if not self.settings.onlyOnSteps then
        return nil
    end
    if self.readback == nil then
        local speech = WowVision.base.speech
        if C_CurveUtil == nil or UnitHealthPercent == nil or speech == nil or speech.speakAside == nil then
            return nil
        end
        self.readback = GroupHealth.Readback:new({
            now = debugprofilestop,
            after = C_Timer.After,
            speak = function(text)
                -- Silent: volume 0, at the rate the fixed values were measured at.
                speech:speakAside(self.settings.voice or 0, text, GroupHealth.readbackConstants.RATE, 0)
            end,
            through = function(unit, points)
                return through(unit, points)
            end,
            nextCount = function()
                return self:nextCount()
            end,
            plan = function(unit)
                return self:readbackPlan(unit)
            end,
            priority = function(unit)
                return self:readbackPriority(unit)
            end,
            rerequest = function(unit)
                self:check(unit)
            end,
            onReading = function(unit, reading)
                self:onReading(unit, reading)
            end,
            onDiscard = function(unit, why, sample)
                self:onDiscard(unit, why, sample)
            end,
            onPurge = function()
                for _, member in pairs(self.members) do
                    member.pending = false
                    member.pendingCount = 0
                    member.again = false
                    member.lost = nil
                    member.rechecking = false
                end
                self:readEveryone()
            end,
            onOwnCut = function(tag)
                self:onOwnCut(tag)
            end,
            onError = function(err)
                geterrorhandler()(err)
            end,
            onFailing = function()
                print("WowVision: " .. L["Group health readings failing"])
                WowVision:speak(L["Group health readings failing"])
            end,
        })
    end
    return self.readback
end

-- Speak first, check afterwards ---------------------------------------------------

-- A health event, or the readback asking for the member again. A member
-- without a reference gets a silent sample (the first reading only sets
-- it). Otherwise the number goes out now, carried by a sample. While the
-- member's last check is still out, a second number may go out beside it
-- when the slot line is free (nobody else waiting): gated by the same
-- reference, it may repeat the first if that one was a move, but a member
-- taking hit after hit is heard at once. Otherwise it waits for the check
-- and goes out with the health of that moment. Measured in the
-- simulation (eight fights each): one member taking hits, 52 instead of
-- 24 percent of numbers right after the hit, repeats 8 instead of 6
-- percent; everyone hit, unchanged (the line is never free then).
-- No pause: the minimum change keeps a member from speaking too often (the
-- pauses throttled the first version, which spoke on every health event),
-- as in Sku.
function module:check(unit)
    local member = self:memberFor(unit)
    local readback = self:stepReadback()
    if member == nil or member.dead or readback == nil then
        return
    end
    if member.reference == nil then
        readback:request(member.unit)
        return
    end
    local now = GetTime()
    member.eventAt = member.eventAt or now
    local out = member.pendingCount or 0
    -- A lost sample's number may have been heard: a silent re-check with
    -- its plan moves the reference as if it had come back, with no second
    -- number (seen in game 2026-10-13: sending the number again on every
    -- lost sample made a burst of repeats).
    if member.lost ~= nil then
        if out >= 2 then
            member.again = true
            return
        end
        local plan = member.lost
        member.lost = nil
        member.waitReason = member.waitReason or "a re-check after a lost check"
        member.pendingCount = out + 1
        member.pending = true
        member.rechecking = true
        if not readback:request(member.unit, { plan = plan, recheck = true }) then
            member.pendingCount = member.pendingCount - 1
            member.pending = member.pendingCount > 0
            member.rechecking = false
            member.lost = plan
        end
        return
    end
    if out >= 2 or (out == 1 and (member.rechecking or not readback:lineFree())) then
        member.again = true
        if member.waitReason == nil then
            member.waitReason = (out >= 2 and "two checks out")
                or (member.rechecking and "a re-check was out")
                or "its last check was out and the line busy"
        end
        return
    end
    member.pendingCount = out + 1
    member.pending = true
    local accepted = readback:request(member.unit, {
        carry = function(plan)
            return self:announceWith(member, plan)
        end,
    })
    -- Two samples out already: the readback asks again when one is back.
    if not accepted then
        member.pendingCount = member.pendingCount - 1
        member.pending = member.pendingCount > 0
    end
end

-- The number carried by a sample: gated by the plan's quiet band, the
-- band read as "moved less" (GroupHealth.quietFor).
-- Returns how many utterances went out.
function module:announceWith(member, plan)
    if self:memberFor(member.unit) ~= member or member.dead then
        return 0
    end
    local quiet = GroupHealth.quietFor(member, plan, minChange(member.role))
    if quiet == nil then
        return 0
    end
    member.spokenAfter = member.eventAt ~= nil and GetTime() - member.eventAt or nil
    member.eventAt = nil
    member.waitedFor = member.waitReason
    member.waitReason = nil
    return self:announce(member, "fire", quiet, true) or 0
end

function module:onReading(unit, reading)
    local member = self:memberFor(unit)
    if member == nil or member.dead then
        return
    end
    local heard = GroupHealth.judge(member, reading, minChange(member.role))
    if reading.carried then
        member.pendingCount = math.max(0, (member.pendingCount or 1) - 1)
        member.pending = member.pendingCount > 0
        if reading.recheck then
            member.rechecking = false
        end
        if heard then
            -- Heard, if the lane's range ("Speak Below") allowed it.
            self:logChange(member, reading.recheck)
        end
    end
    -- Not located yet: zoom in now, not at the next event.
    if member.locate and not member.pending and self.readback ~= nil then
        self.readback:request(unit)
    end
    if member.again and not member.pending then
        member.again = false
        self:check(unit)
    end
end

-- A sample that carried a number was lost: whether it was heard is not
-- known. The next check is a silent re-check with the same plan (it moves
-- the reference if the number was heard). Only a number cut off right
-- after it went out (a stop within RESPEAK_MS, at most once in
-- RESPEAK_EVERY seconds) is sent again. After a disturbance the readback
-- asks again by itself.
local RESPEAK_MS = 400
local RESPEAK_EVERY = 2

function module:onDiscard(unit, why, sample)
    if not sample.carried then
        return
    end
    local member = self:memberFor(unit)
    if member == nil then
        return
    end
    member.pendingCount = math.max(0, (member.pendingCount or 1) - 1)
    member.pending = member.pendingCount > 0
    self:logLine(member, (sample.recheck and "re-check lost: " or "check lost: ") .. why)
    if sample.recheck then
        member.rechecking = false
        member.lost = sample.plan
    elseif why == "stop" and debugprofilestop() - sample.calledMs < RESPEAK_MS
        and GetTime() - (member.lastRespeak or -math.huge) > RESPEAK_EVERY then
        member.lastRespeak = GetTime()
        self.respoken = (self.respoken or 0) + 1
    else
        member.lost = sample.plan
    end
    if not GroupHealth.readbackRetries(why) and why ~= "stop" and member.again then
        member.again = false
        self:check(unit)
    end
end

-- A stop of all speech cut a number of ours: it is spoken again, health
-- being worth more than the silence asked for. The snapshot and the repeat
-- are not: a stop during them means stop.
local RESPEAK = { urgent = true, normal = true, dead = true }

function module:onOwnCut(tag)
    if tag == nil or not RESPEAK[tag.lane] then
        return
    end
    local member = tag.member
    if self:memberFor(member.unit) ~= member or (tag.lane == "dead") ~= member.dead then
        return
    end
    self.respoken = (self.respoken or 0) + 1
    self:enqueue(member, tag.lane, nil, { wokeAt = GetTime(), respoken = true })
end

-- Anyone stopping all speech cuts the samples out and our speech with
-- them: the readback drops the cut samples, reads those members again and
-- hands back the cut numbers.
if C_VoiceChat ~= nil and C_VoiceChat.StopSpeakingText ~= nil then
    hooksecurefunc(C_VoiceChat, "StopSpeakingText", function()
        if module.readback ~= nil then
            module:noteStop()
            module.readback:onStop()
        end
    end)
end

-- Who stopped all speech: the first addon file in the call stack that is
-- not this one, counted for the log (seen in game 2026-10-13: 67 stops in
-- one short solo fight).
function module:noteStop()
    local stack = debugstack(2, 10, 0) or ""
    local source = nil
    -- The speech module's stop is only the messenger: the caller above it.
    for file, lineNumber in stack:gmatch("AddOns[/\\]([^%]%[\"\n]-%.%a+)[%]\"]*:(%d+)") do
        if not file:find("groupHealth", 1, true) and not file:find("retail/speech.lua", 1, true) then
            source = file .. ":" .. lineNumber
            break
        end
    end
    -- No addon file: a key binding or the game's own code; its first line.
    if source == nil then
        for line in stack:gmatch("[^\n]+") do
            if not line:find("groupHealth", 1, true) then
                source = "the game: " .. line:sub(1, 100)
                break
            end
        end
    end
    source = source or "the game"
    self.stopSources = self.stopSources or {}
    self.stopSources[source] = (self.stopSources[source] or 0) + 1
    self:keepLog()
end

function module:unavailable()
    if not self.unavailableSaid then
        self.unavailableSaid = true
        WowVision:speak(L["Group health monitor unavailable here"])
    end
end

-- The health range [low, high) a lane speaks in; a high above 1 includes
-- full health. "fire" is the number carried by a sample: urgent and normal
-- in one.
function module:laneRange(member, lane)
    local role = member.role
    local start = GroupHealth.fraction(roleSetting(role, "startThreshold"))
    local urgent = GroupHealth.fraction(roleSetting(role, "urgentThreshold"))
    if lane == "fire" then
        return 0, start
    elseif lane == "urgent" then
        return 0, urgent
    elseif lane == "normal" then
        return urgent, start
    elseif lane == "repeat" then
        return 0, GroupHealth.fraction(roleSetting(role, "repeatThreshold"))
    elseif lane == "snapshot" and self.settings.announceFull then
        -- At full health the snapshot says "<number> full" instead.
        return 0, 1
    end
    return 0, 2
end

-- `quiet` (optional) keeps the number silent inside that band, Sku's rule
-- (gatePoints); `direct` speaks straight to the engine (a number carried by
-- a sample). Returns how many utterances went out.
function module:announce(member, lane, quiet, direct)
    local number = tostring(member.number)
    local tag = { member = member, lane = lane }
    if lane == "dead" then
        self:speak(bust(number .. " " .. L["dead"]), tag, direct)
        return 1
    end
    -- A member who died while this waited gets no number.
    if plainTrue(UnitIsDeadOrGhost, member.unit) then
        return 0
    end
    local profile, pitchPoints = self:profile()
    local pitch = through(member.unit, pitchPoints)
    local low, high = self:laneRange(member, lane)
    local lowRange, highRange = GroupHealth.copyRanges(low, high, profile)
    local lowPoints = GroupHealth.gatePoints(lowRange[1], lowRange[2], quiet)
    local highPoints = GroupHealth.gatePoints(highRange[1], highRange[2], quiet)
    local fullGate = quiet ~= nil and GroupHealth.gatePoints(1, 2, quiet) or fullPoints
    local wantFull = (lane == "normal" or lane == "snapshot" or lane == "fire") and self.settings.announceFull
    -- A carried number whose gates keep every health silent is not sent:
    -- fewer utterances at once in the engine.
    local sendNumber = quiet == nil or not (GroupHealth.isSilent(lowPoints) and GroupHealth.isSilent(highPoints))
    if quiet ~= nil and wantFull and GroupHealth.isSilent(fullGate) then
        wantFull = false
    end
    local lowVolume = through(member.unit, lowPoints)
    local highVolume = through(member.unit, highPoints)
    if pitch == nil or lowVolume == nil or highVolume == nil then
        self:unavailable()
        return 0
    end
    -- Every announcement has the same two parts (logic.lua): the LOW copy
    -- (rising, the urgent part of the scale) and the HIGH copy last
    -- (falling, the healthy part). The volume gates pick the copy; the
    -- sentence shape never changes, so the voice's melody adds the same to
    -- every number of a copy.
    -- "<number> full" ends the same utterance, silent unless the member
    -- is at exactly full health (when both copies before it are silent, so
    -- it is heard after their length): one utterance instead of two, as
    -- the engine prepares one after another (flood probe, 2026-10-13).
    local fullPart = ""
    if wantFull then
        local full = through(member.unit, fullGate)
        if full ~= nil then
            local bottom = profile.scale[#profile.scale]
            fullPart = GroupHealth.segment(full, bottom, number .. " " .. L["full"])
            sendNumber = true
        end
    end
    if not sendNumber then
        return 0
    end
    self:speak(GroupHealth.segment(lowVolume, pitch, number .. self:nextPad())
        .. GroupHealth.segment(highVolume, pitch, number) .. fullPart, tag, direct)
    return 1
end

-- Lanes -------------------------------------------------------------------------

function module:wake(member, lane)
    local state = member.lanes[lane]
    if state.pending then
        return
    end
    local role = member.role
    local delay, pause
    if lane == "urgent" then
        delay, pause = roleSetting(role, "urgentDelay"), roleSetting(role, "urgentPause")
    else
        delay, pause = roleSetting(role, "delay"), roleSetting(role, "pause")
    end
    -- A reading has already settled what the delay waits for, and the
    -- minimum change what the pause did: with the readback neither applies.
    if self:stepReadback() ~= nil then
        delay, pause = 0, 0
    end
    local now = GetTime()
    local at = GroupHealth.nextFire(now, state.last, delay, pause)
    state.pending = true
    -- For the log: a lane held back by its pause is a follow-up.
    local info = { wokeAt = now, followUp = at > now + delay + 0.01 }
    C_Timer.After(math.max(0, at - now), function()
        state.pending = false
        if self:memberFor(member.unit) ~= member then
            return
        end
        -- With the readback a lane speaks only for a move it has not spoken
        -- yet: there and back while it waited is nothing new.
        if self:stepReadback() ~= nil and not GroupHealth.laneRefNew(state, member.reference, minChange(member.role)) then
            return
        end
        state.last = GetTime()
        self:enqueue(member, lane, nil, info)
    end)
end

function module:silenced()
    return self.settings.silentOutOfCombat and not InCombatLockdown()
end

function module:onHealth(unit)
    local member = self:memberFor(unit)
    if member == nil then
        return
    end
    unit = member.unit
    -- Dead or offline members get no numbers; a death is said once.
    if plainTrue(UnitIsDeadOrGhost, unit) then
        if not member.dead then
            member.dead = true
            -- Dead is a reference of 0 and the lanes start afresh: the
            -- resurrection is a change, heard whatever health it brings.
            member.reference = 0
            member.locate = false
            member.locateBand = nil
            member.lanes.urgent.spokenRef = nil
            member.lanes.normal.spokenRef = nil
            if self.settings.announceDeaths and not self:silenced() then
                self:enqueue(member, "dead")
            end
        end
        return
    end
    member.dead = false
    if plainFalse(UnitIsConnected, unit) then
        return
    end
    if self:silenced() then
        return
    end
    -- With the readback the number goes out at once, gated by Sku's rule.
    if self:stepReadback() ~= nil then
        self:check(unit)
        return
    end
    self:wake(member, "urgent")
    self:wake(member, "normal")
end

-- The repeat: each role at its own interval, every member below the role's
-- repeat threshold (the gate decides).
local REPEAT_CHECK = 0.25

function module:checkRepeats()
    local now = GetTime()
    if self.nextRepeatCheck ~= nil and now < self.nextRepeatCheck then
        return
    end
    self.nextRepeatCheck = now + REPEAT_CHECK
    if self:silenced() then
        return
    end
    for _, member in pairs(self.members) do
        local interval = roleSetting(member.role, "repeatInterval")
        if interval ~= nil and interval > 0 and not member.dead then
            if member.lastRepeat == nil or now - member.lastRepeat >= interval then
                member.lastRepeat = now
                self:enqueue(member, "repeat")
            end
        end
    end
end

-- Everyone once, in number order, ungated.
function module:snapshot()
    local list = {}
    for _, member in pairs(self.members) do
        tinsert(list, member)
    end
    if #list == 0 then
        WowVision:speak(L["Nobody to watch"])
        return
    end
    table.sort(list, function(a, b)
        return a.number < b.number
    end)
    self:clearQueue()
    for _, member in ipairs(list) do
        if plainTrue(UnitIsDeadOrGhost, member.unit) then
            self:enqueue(member, "dead", true)
        else
            self:enqueue(member, "snapshot", true)
        end
    end
end

-- Log (/wv ghlog) ---------------------------------------------------------------
-- Every announcement as it plays: time, number, lane, how long after the
-- health change that woke it, whether a pause held it back. The health
-- itself is secret and cannot be logged. Recorded quietly while on (in chat
-- it was too much in a fight); /wv ghlog show opens the last entries.

local LOG_MAX = 400
module.log = {}

local function chat(text)
    for line in tostring(text):gmatch("[^\n]+") do
        print("WowVision group health: " .. line)
    end
end

function module:logPlay(entry)
    if not self.logging then
        return
    end
    local now = GetTime()
    local member = entry.member
    local parts = {
        self:logTime(),
        "number " .. tostring(member.number),
        string.lower(member.role),
        entry.lane,
    }
    local info = entry.info
    if info ~= nil then
        tinsert(parts, string.format("%.1f s after the change", now - info.wokeAt))
        if info.followUp then
            tinsert(parts, "follow-up after the pause")
        end
        if info.respoken then
            tinsert(parts, "again after a stop of all speech cut it")
        end
    end
    local queued = now - (entry.queuedAt or now)
    if queued > 0.05 then
        tinsert(parts, string.format("waited %.1f s in the queue", queued))
    end
    local line = table.concat(parts, ", ")
    tinsert(self.log, line)
    while #self.log > LOG_MAX do
        tremove(self.log, 1)
    end
    self:keepLog()
end

-- A number carried by a sample turned out to be a change (heard, if the
-- lane's range allowed it).
function module:logChange(member, recheck)
    if not self.logging then
        return
    end
    local parts = {
        self:logTime(),
        "number " .. tostring(member.number),
        string.lower(member.role),
        "moved, reference now " .. tostring(member.reference),
    }
    -- Heard below "Speak Below", or at full health ("<number> full").
    local start = roleSetting(member.role, "startThreshold")
    local heard = member.reference < start or (member.reference >= 100 and self.settings.announceFull)
    if recheck then
        -- The number went out with the lost sample, earlier.
        tinsert(parts, (heard and "heard" or "silent (above Speak Below)") .. " with a lost sample, found by a re-check")
    else
        tinsert(parts, heard and "heard" or "silent (above Speak Below)")
    end
    if member.spokenAfter ~= nil then
        tinsert(parts, string.format("sent %.2f s after the health event", member.spokenAfter))
        if member.spokenAfter > 0.05 and member.waitedFor ~= nil then
            tinsert(parts, "waited: " .. member.waitedFor)
        end
    end
    tinsert(self.log, table.concat(parts, ", "))
    while #self.log > LOG_MAX do
        tremove(self.log, 1)
    end
    self:keepLog()
end

-- The clock time, and the game's own time to the hundredth (the clock's
-- seconds and the game time's fractions do not line up).
function module:logTime()
    return date("%H:%M:%S") .. string.format(" (%.2f)", GetTime())
end

-- A line about a member in the log (while it is on).
function module:logLine(member, text)
    if not self.logging then
        return
    end
    tinsert(self.log, self:logTime() .. ", number " .. tostring(member.number) .. ", " .. text)
    while #self.log > LOG_MAX do
        tremove(self.log, 1)
    end
    self:keepLog()
end

-- The log and the readback's counts go into WowVisionDump, saved at the
-- next /reload, so a test can be read afterwards.
function module:keepLog()
    WowVisionDump = WowVisionDump or {}
    WowVisionDump.groupHealthLog = {
        lines = self.log,
        readback = self.readback ~= nil and self.readback.stats or nil,
        numbersSpokenAgain = self.respoken,
        stopSources = self.stopSources,
    }
end

module:registerCommand({
    name = "ghlog",
    description = "Group health monitor log: 'on' records every announcement, 'off' stops, 'show' lists the last ones, 'clear' empties it",
    func = function(args)
        local word = (args or ""):lower():match("^%s*(%S+)")
        local text
        if word == "on" then
            module.logging = true
            text = "Group health log on"
        elseif word == "off" then
            module.logging = false
            text = "Group health log off"
        elseif word == "clear" then
            module.log = {}
            module:keepLog()
            text = "Group health log cleared"
        else
            local lines = {}
            for _, line in ipairs(module.log) do
                tinsert(lines, line)
            end
            -- The readback's counts, so its health shows next to the plays.
            local readback = module.readback
            if readback ~= nil then
                local stats = readback.stats
                local function list(counts)
                    local parts = {}
                    for why, n in pairs(counts) do
                        tinsert(parts, why .. " " .. n)
                    end
                    table.sort(parts)
                    return #parts > 0 and table.concat(parts, ", ") or "none"
                end
                tinsert(lines, string.format(
                    "Readback: %d samples, %d readings used, thrown away: %s; most at once %d; purges: %s; own speech cut %d, numbers spoken again %d",
                    stats.samples, stats.readings, list(stats.discarded), stats.maxInflight, list(stats.purges), stats.ownCut, module.respoken or 0
                ))
            end
            if #lines == 0 then
                text = "Group health log is empty"
            else
                chat(lines[#lines])
                WowVision.testing.showResults(table.concat(lines, "\n"))
                return
            end
        end
        chat(text)
        WowVision:speak(text)
    end,
})

-- Wiring ------------------------------------------------------------------------

module:registerEvent("event", "UNIT_HEALTH")
module:registerEvent("event", "GROUP_ROSTER_UPDATE")
module:registerEvent("event", "PLAYER_ROLES_ASSIGNED")
module:registerEvent("event", "PLAYER_REGEN_ENABLED")
module:registerEvent("event", "PLAYER_ENTERING_WORLD")
-- The step readback times its silent samples by these.
module:registerEvent("event", "VOICE_CHAT_TTS_PLAYBACK_STARTED")
module:registerEvent("event", "VOICE_CHAT_TTS_PLAYBACK_FINISHED")
module:registerEvent("event", "VOICE_CHAT_TTS_PLAYBACK_FAILED")

function module:onEvent(event, ...)
    if event == "VOICE_CHAT_TTS_PLAYBACK_STARTED" then
        if self.readback ~= nil then
            self.readback:onStarted(...)
        end
    elseif event == "VOICE_CHAT_TTS_PLAYBACK_FINISHED" then
        if self.readback ~= nil then
            self.readback:onFinished(..., false)
        end
    elseif event == "VOICE_CHAT_TTS_PLAYBACK_FAILED" then
        if self.readback ~= nil then
            self.readback:onFinished(..., true)
        end
    elseif event == "UNIT_HEALTH" then
        self:onHealth(...)
    elseif event == "PLAYER_REGEN_ENABLED" then
        if self.rosterDirty then
            self:rebuild()
        end
    elseif event == "PLAYER_ENTERING_WORLD" then
        self.unavailableSaid = false
        self:rebuild()
    else
        self:rebuild()
    end
end

function module:onEnable()
    self:hasUpdate(function(self)
        self:checkRepeats()
    end)
    self:rebuild()
end

function module:onDisable()
    self:clearQueue()
    self.members = {}
    self.aliases = {}
    self.readback = nil
end

module:registerBinding({
    type = "Function",
    key = "groupHealth/snapshot",
    label = L["Speak Group Health"],
    -- A letter key: the game names keys by the character the keyboard
    -- layout produces, so only letters (and function keys) exist on every
    -- layout. "Ö" never fired, and "#" is a different key on English and
    -- French layouts. H for health.
    inputs = { "ALT-H" },
    func = function()
        module:snapshot()
    end,
})
