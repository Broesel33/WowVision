local module = WowVision.base:createModule("quests")
local L = module.L
module:setLabel(L["Quests"])
local settings = module:hasSettings()

-- The quests module: quest data for the rest of the addon, sourced from
-- Questie when it is loaded. It answers three questions through the
-- adapter -- nearby available quests, the log with objective progress, and
-- the places a quest sends you -- and raises events when Questie becomes
-- ready and when a quest changes. How that reaches the player (screens,
-- beacons, announcements) is layered on top later.
--
-- module:nearbyQuests(opts?)        see Adapter:nearbyQuests
-- module:inProgress()               see Adapter:inProgress
-- module:targets(questId, phase)    see Adapter:targets ("start" | "objectives" | "finish")
-- module:objectiveTargets(questId, objectiveIndex)
-- module:quest(questId)
-- module.events.ready               emitted once the data source is usable
-- module.events.questUpdate         (questId, objectiveIndex?, reason) where reason is one of
--                                   module.updateReasons

settings:add({
    key = "levelRange",
    type = "Number",
    label = L["Nearby Level Range"],
    default = 5,
    min = 0,
    max = 60,
})
settings:add({
    key = "includeRepeatable",
    type = "Bool",
    label = L["Include Repeatable Quests"],
    default = true,
})

module.updateReasons = { accepted = "accepted", updated = "updated", turnedIn = "turnedIn", abandoned = "abandoned" }

module.events = {
    ready = WowVision.Event:new("questsReady"),
    questUpdate = WowVision.Event:new("questUpdate"),
}

module.adapter = nil

function module:isReady()
    return self.adapter ~= nil and self.adapter:isReady()
end

function module:hasSource()
    return self.adapter ~= nil
end

local function requireReady(self)
    if self:isReady() then
        return true
    end
    return false
end

function module:nearbyQuests(opts)
    if not requireReady(self) then
        return {}
    end
    opts = opts or {}
    if opts.levelRange == nil then
        opts.levelRange = self.settings.levelRange
    end
    if opts.includeRepeatable == nil then
        opts.includeRepeatable = self.settings.includeRepeatable
    end
    return self.adapter:nearbyQuests(opts)
end

function module:inProgress()
    if self.adapter == nil then
        -- No Questie: the game's own log still reads, without target data.
        return WowVision.quests.Adapter:new({
            isReady = function()
                return false
            end,
            questLog = WowVision.quests.gameQuestLog,
        }):inProgress()
    end
    return self.adapter:inProgress()
end

function module:targets(questId, phase)
    if not requireReady(self) then
        return {}
    end
    return self.adapter:targets(questId, phase)
end

function module:objectiveTargets(questId, objectiveIndex)
    if not requireReady(self) then
        return {}
    end
    return self.adapter:objectiveTargets(questId, objectiveIndex)
end

function module:quest(questId)
    if not requireReady(self) then
        return nil
    end
    return self.adapter:quest(questId)
end

-- NPCs of the current zone by role (Adapter.roles keys plus "rare"),
-- nearest first within opts.radius, at most opts.maxCount each.
function module:npcsByRole(opts)
    if not requireReady(self) then
        return {}
    end
    return self.adapter:npcsByRole(opts)
end

-- Targets for explicit ids of one kind ("npc" or "object").
function module:placeTargets(kind, ids, opts)
    if not requireReady(self) then
        return {}
    end
    return self.adapter:placeTargets(kind, ids, opts)
end

-- Questie's curated per-character id lists ("Mailbox", "Class Trainer", ...).
function module:townsfolk(key)
    local backend = self.adapter ~= nil and self.adapter.backend or nil
    if backend == nil or backend.townsfolk == nil then
        return {}
    end
    return backend.townsfolk(key)
end

-- Where a spawn is, for reading: the zone, then the best of two hints.
-- A map landmark within LANDMARK_RANGE reads as "near Halfhill, 40 yards"
-- (always available, always right about what it is). The explored-overlay
-- area name reads instead when no landmark is close (open country, where
-- overlays are trustworthy), or alongside when it agrees with the
-- landmark; a disagreeing overlay in a crowded spot is dropped. Cached for
-- the session once an overlay name is known (exploring reveals them).
local LANDMARK_RANGE = 600
module._placeNames = {}
function module:placeName(spawn)
    local backend = self.adapter ~= nil and self.adapter.backend or nil
    if backend == nil or backend.placeName == nil or spawn == nil then
        return nil
    end
    local key = tostring(spawn.mapId) .. ":" .. tostring(spawn.x) .. ":" .. tostring(spawn.y)
    local cached = self._placeNames[key]
    if cached ~= nil and cached.final then
        return cached.text
    end
    local zone, landmark, distance, area, subzone = backend.placeName(spawn.mapId, spawn.x, spawn.y, spawn.areaId)
    local parts = {}
    if zone ~= nil then
        tinsert(parts, zone)
    end
    local nearLandmark = landmark ~= nil and distance ~= nil and distance <= LANDMARK_RANGE
    if subzone ~= nil then
        -- The data names the subzone itself: exact, so it leads.
        tinsert(parts, subzone)
        if nearLandmark and landmark ~= subzone then
            tinsert(parts, string.format("%s %s, %d %s", L["near"], landmark, distance, L["yards"]))
        end
    elseif nearLandmark then
        if area ~= nil and area == landmark then
            tinsert(parts, string.format("%s, %d %s", landmark, distance, L["yards"]))
        else
            tinsert(parts, string.format("%s %s, %d %s", L["near"], landmark, distance, L["yards"]))
        end
    elseif area ~= nil then
        tinsert(parts, area)
    end
    local text = #parts > 0 and table.concat(parts, ", ") or nil
    self._placeNames[key] = { text = text, final = subzone ~= nil or area ~= nil or nearLandmark }
    return text
end

function module:indexReady()
    local backend = self.adapter ~= nil and self.adapter.backend or nil
    return backend ~= nil and backend.indexReady ~= nil and backend.indexReady() == true
end

-- ---- source lifecycle ----

local function reasonFor(code)
    local enums = Questie ~= nil and Questie.API ~= nil and Questie.API.Enums or nil
    local reasons = enums ~= nil and enums.QuestUpdateTriggerReason or nil
    if reasons ~= nil then
        if code == reasons.QUEST_ACCEPTED then
            return module.updateReasons.accepted
        elseif code == reasons.QUEST_TURNED_IN then
            return module.updateReasons.turnedIn
        elseif code == reasons.QUEST_ABANDONED then
            return module.updateReasons.abandoned
        end
    end
    return module.updateReasons.updated
end

function module:_attachQuestie()
    local backend = WowVision.quests.questieBackend()
    if backend == nil then
        return false
    end
    backend.questLog = WowVision.quests.gameQuestLog
    self.adapter = WowVision.quests.Adapter:new(backend)
    backend.onReady(function()
        if backend.startIndex ~= nil then
            backend.startIndex()
        end
        self.events.ready:emit()
    end)
    backend.onQuestUpdate(function(questId, objectiveIndex, reason)
        -- Phase visibility follows quest progress: resolved spawns may
        -- change, so forget them.
        self.adapter:invalidate()
        self.events.questUpdate:emit(questId, objectiveIndex, reasonFor(reason))
    end)
    return true
end

module:registerEvent("event", "ZONE_CHANGED_NEW_AREA")

function module:onEvent(event)
    if event == "ZONE_CHANGED_NEW_AREA" and self.adapter ~= nil then
        self.adapter:invalidate()
    end
end

function module:onEnable()
    if self.adapter == nil then
        self:_attachQuestie()
    end
end

-- ---- /wv quests: a plain-spoken dump for checking the data in game ----

local function formatDistance(distance)
    if distance == nil then
        return L["far"]
    end
    return string.format("%d %s", distance, L["yards"])
end

local function describeTarget(target)
    local name = target.name or L["Unknown"]
    if target.item ~= nil and target.item.name ~= nil then
        name = target.item.name .. " " .. L["from"] .. " " .. name
    end
    return name .. " " .. formatDistance(target.distance)
end

local function printLines(lines)
    for _, line in ipairs(lines) do
        print(line)
    end
end

function module:handleCommand(args)
    local lines = {}
    if not self:hasSource() then
        tinsert(lines, L["Questie is not loaded"])
        printLines(lines)
        return
    end
    if not self:isReady() then
        tinsert(lines, L["Questie is still loading"])
        printLines(lines)
        return
    end
    local word, rest = args:match("^(%S+)%s*(.*)$")
    if word == "near" or word == nil or word == "" then
        local list = self:nearbyQuests({ maxCount = 10 })
        if #list == 0 then
            tinsert(lines, L["No nearby quests"])
        end
        for _, entry in ipairs(list) do
            tinsert(
                lines,
                string.format(
                    "%s, %s %s, %s, %s",
                    entry.name,
                    L["Level"],
                    tostring(entry.level),
                    describeTarget(entry.starter),
                    tostring(entry.questId)
                )
            )
        end
    elseif word == "log" then
        local list = self:inProgress()
        if #list == 0 then
            tinsert(lines, L["No quests in progress"])
        end
        for _, entry in ipairs(list) do
            local state = ""
            if entry.complete then
                state = " " .. L["Complete"]
            elseif entry.failed then
                state = " " .. L["Failed"]
            end
            tinsert(lines, string.format("%s%s, %s", entry.title, state, tostring(entry.questId)))
            for _, objective in ipairs(entry.objectives) do
                local target = objective.target ~= nil and objective.target.name or nil
                local suffix = target ~= nil and (" " .. L["target"] .. " " .. target) or ""
                tinsert(lines, "  " .. tostring(objective.text) .. suffix)
            end
        end
    elseif word == "go" then
        local questId, phase = rest:match("^(%d+)%s*(%a*)$")
        questId = tonumber(questId)
        if questId == nil then
            tinsert(lines, "Usage quests go questId start or objectives or finish")
        else
            if phase == nil or phase == "" then
                phase = "objectives"
            end
            local ok, list = pcall(self.targets, self, questId, phase)
            if not ok then
                tinsert(lines, tostring(list))
            elseif #list == 0 then
                tinsert(lines, L["No targets"])
            else
                for _, target in ipairs(list) do
                    local prefix = target.objectiveIndex ~= nil and (tostring(target.objectiveIndex) .. " ") or ""
                    tinsert(lines, prefix .. describeTarget(target))
                end
            end
        end
    else
        tinsert(lines, "Usage quests near, quests log, quests go questId phase")
    end
    printLines(lines)
end

module:registerCommand({
    name = "quests",
    scope = "WowVision",
    description = "Quest data check. Usage: /wv quests near, /wv quests log, /wv quests go questId [start|objectives|finish]",
    func = function(args)
        module:handleCommand(args or "")
    end,
})
