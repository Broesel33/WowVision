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
    },
}

-- Settings ----------------------------------------------------------------------

local voiceSetting = settings:add({
    key = "voice",
    type = "Choice",
    label = L["Voice"],
    default = 0,
})
for _, v in ipairs(C_VoiceChat.GetTtsVoices() or {}) do
    voiceSetting:addChoice({
        label = v.name,
        value = v.voiceID,
    })
end

settings:add({
    key = "rate",
    type = "Number",
    label = L["Speech Rate"],
    default = 2,
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
    default = 0.3,
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

local function isSecret(value)
    return issecretvalue ~= nil and issecretvalue(value) == true
end

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

local pitchPoints = GroupHealth.pitchPoints()
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
    -- The same person keeps their timing across a roster update.
    if old ~= nil and old.number == number then
        member.lanes.urgent.last = old.lanes.urgent.last
        member.lanes.normal.last = old.lanes.normal.last
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
function module:nextPad()
    local data = self.data
    if data == nil then
        self.fallbackCount = (self.fallbackCount or math.floor(GetTime() * 1000)) + 1
        return GroupHealth.uniquePad(self.fallbackCount)
    end
    data.utterances = (data.utterances or 0) + 1
    return GroupHealth.uniquePad(data.utterances)
end

function module:speak(text)
    local speech = WowVision.base.speech
    if speech == nil or speech.speakAside == nil then
        return
    end
    speech:speakAside(self.settings.voice or 0, text, self.settings.rate, self.settings.volume)
end

function module:unavailable()
    if not self.unavailableSaid then
        self.unavailableSaid = true
        WowVision:speak(L["Group health monitor unavailable here"])
    end
end

-- The gated volume for a lane, or nil when the game refused the unit.
function module:laneVolume(member, lane)
    local role = member.role
    local start = GroupHealth.fraction(roleSetting(role, "startThreshold"))
    local urgent = GroupHealth.fraction(roleSetting(role, "urgentThreshold"))
    if lane == "urgent" then
        return through(member.unit, GroupHealth.belowPoints(urgent))
    elseif lane == "normal" then
        return through(member.unit, GroupHealth.bandPoints(urgent, start))
    elseif lane == "repeat" then
        return through(member.unit, GroupHealth.belowPoints(GroupHealth.fraction(roleSetting(role, "repeatThreshold"))))
    end
    return 100
end

function module:announce(member, lane)
    local number = tostring(member.number)
    if lane == "dead" then
        self:speak(bust(number .. " " .. L["dead"]))
        return
    end
    local pitch = through(member.unit, pitchPoints)
    local volume = self:laneVolume(member, lane)
    if pitch == nil or volume == nil then
        self:unavailable()
        return
    end
    local text = GroupHealth.segment(volume, pitch, number .. self:nextPad())
    if lane == "normal" and self.settings.announceFull then
        local full = through(member.unit, fullPoints)
        if full ~= nil then
            text = text .. GroupHealth.segment(full, pitch, number .. " " .. L["full"])
        end
    end
    self:speak(text)
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
-- itself is secret and cannot be logged. Printed to chat while on; the
-- last entries stay for /wv ghlog show.

local LOG_MAX = 200
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
        date("%H:%M:%S") .. string.format(".%d", math.floor((now % 1) * 10)),
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
    chat(line)
end

module:registerCommand({
    name = "ghlog",
    description = "Group health monitor log: 'on' prints every announcement to chat, 'off' stops, 'show' lists the last ones, 'clear' empties it",
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
            text = "Group health log cleared"
        else
            if #module.log == 0 then
                text = "Group health log is empty"
            else
                local all = table.concat(module.log, "\n")
                chat(all)
                WowVision.testing.showResults(all)
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

function module:onEvent(event, ...)
    if event == "UNIT_HEALTH" then
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
