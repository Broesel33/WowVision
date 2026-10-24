local L = WowVision:getLocale()
local secrets = WowVision.secrets

-- Auras tracked through Blizzard's cooldown manager (Retail, WoW: Forever).
--
-- In combat and in instances the aura APIs are closed to addons, and every
-- value of an aura that does come through is secret. The cooldown manager
-- (Blizzard_CooldownViewer) is Blizzard's own code, so it reads what we
-- cannot, and it leaves plain facts on its item frames (measured in game,
-- 2026-10-24): whether an item's aura is up (IsActive on buff items, the
-- cached aura data on cooldown items), on which unit ("player" or "target",
-- auraDataUnit), and whether it is in its pandemic window (PandemicIcon).
-- The time left is drawn by the engine as the countdown text on the item's
-- Cooldown widget, secret but speakable. This monitor polls those facts each
-- tick for the item frames whose spell a rule names, and never touches an
-- aura value itself. Only spells the player put in the cooldown manager can
-- be tracked, and only on the player and the target, the two units the
-- viewers watch.
local monitors = WowVision.monitors

local VIEWERS = { "BuffIconCooldownViewer", "BuffBarCooldownViewer", "EssentialCooldownViewer", "UtilityCooldownViewer" }
-- Below this many seconds the countdown text shows one decimal ("8.7"), the
-- finest the engine formats; Blizzard's own value is 0.
local DECIMAL_BELOW_SECONDS = 600
-- The viewers are looked over again this often, besides on their layout
-- changes, in case a hook was missed.
local RESCAN_SECONDS = 5

local stateOutputs = {
    { type = "Sound", key = "sound", label = L["Sound Alert"], enabled = false },
    { type = "TTS", key = "tts", label = L["TTS Alert"], enabled = false },
}

local function spellNameOf(id)
    if id == nil or secrets.isSecret(id) or id == 0 then
        return nil
    end
    if C_Spell ~= nil and C_Spell.GetSpellName ~= nil then
        return C_Spell.GetSpellName(id)
    end
    return nil
end

-- The plain spell names an item frame stands for: its base spell and the
-- override and linked spells (the ids that turn secret while the aura is up
-- are skipped; the base id never does).
local function frameSpellNames(frame)
    local names = {}
    if frame.GetCooldownInfo == nil then
        return names
    end
    local ok, info = pcall(frame.GetCooldownInfo, frame)
    if not ok or info == nil then
        return names
    end
    for _, key in ipairs({ "spellID", "overrideSpellID", "linkedSpellID", "overrideTooltipSpellID" }) do
        local name = spellNameOf(info[key])
        if name ~= nil then
            names[name] = true
        end
    end
    if type(info.linkedSpellIDs) == "table" and not secrets.isSecret(info.linkedSpellIDs) then
        for _, id in ipairs(info.linkedSpellIDs) do
            local name = spellNameOf(id)
            if name ~= nil then
                names[name] = true
            end
        end
    end
    return names
end

-- Whether the frame shows its aura on the unit right now. A buff item (the
-- Buff Icon and Buff Bar viewers) says so with IsActive; a cooldown item
-- (Essential, Utility) is active whenever it has a cooldown, so there the
-- cached aura data stands for the aura.
local function auraShown(frame, unit)
    if frame.auraDataUnit ~= unit or frame.auraDataCached == nil then
        return false
    end
    if frame.GetApplicationsText ~= nil and frame.IsActive ~= nil then
        local ok, active = pcall(frame.IsActive, frame)
        return ok and active == true
    end
    return true
end

local function inPandemic(frame)
    return frame.PandemicIcon ~= nil
end

-- The text of a font string, or nil (secret text comes through as is).
local function textOf(fontString)
    if fontString == nil or fontString.GetText == nil then
        return nil
    end
    local ok, text = pcall(fontString.GetText, fontString)
    if ok then
        return text
    end
    return nil
end

-- The time left as the engine draws it on the item: the countdown text of
-- its Cooldown widget while the numbers are shown, else the bar's duration
-- text (the Buff Bar viewer).
local function timerText(frame)
    local cooldown = frame.Cooldown
    if cooldown ~= nil and cooldown.GetCountdownFontString ~= nil then
        local okHidden, hidden = pcall(cooldown.GetHideCountdownNumbers, cooldown)
        if okHidden and not hidden then
            local ok, fontString = pcall(cooldown.GetCountdownFontString, cooldown)
            if ok then
                local text = textOf(fontString)
                if secrets.hasText(text) then
                    return text
                end
            end
        end
    end
    local bar = frame.Bar
    if bar ~= nil then
        return textOf(bar.Duration)
    end
    return nil
end

local function stacksText(frame)
    if frame.GetApplicationsFontString == nil then
        return nil
    end
    local ok, fontString = pcall(frame.GetApplicationsFontString, frame)
    if not ok then
        return nil
    end
    return textOf(fontString)
end

-- ---------------------------------------------------------------------------
-- The rule: one spell of the cooldown manager, with alerts per state.
-- ---------------------------------------------------------------------------
local CdmAuraStateRule = monitors.ruleRegistry:createType({ key = "CdmAuraState", parent = "State" })

CdmAuraStateRule:addFields({
    { key = "spell", type = "Spell", persist = true, label = L["Spell"], sortPriority = 2 },
    {
        key = "applied",
        type = "Alert",
        persist = true,
        label = L["Applied"],
        sortPriority = 3,
        alert = { key = "applied", label = L["Applied"] },
        outputs = stateOutputs,
    },
    {
        key = "pandemic",
        type = "Alert",
        persist = true,
        label = L["Pandemic"],
        sortPriority = 3,
        alert = { key = "pandemic", label = L["Pandemic"] },
        outputs = stateOutputs,
    },
    {
        key = "missing",
        type = "Alert",
        persist = true,
        label = L["Missing"],
        sortPriority = 3,
        alert = { key = "missing", label = L["Missing"] },
        outputs = stateOutputs,
    },
})

-- Whether the game has a pandemic window at all. WoW: Forever has none (a
-- refreshed aura carries nothing over), so camelot/cdmAuras.lua clears this
-- and hides the Pandemic state there.
CdmAuraStateRule.hasPandemic = true

function CdmAuraStateRule:initialize(config)
    self._frames = {}
    monitors.StateRule.initialize(self, config)
end

function CdmAuraStateRule:getTrackingFields()
    return { "spell" }
end

function CdmAuraStateRule:getStates()
    if not self.class.hasPandemic then
        return { { key = "applied" } }
    end
    return {
        { key = "applied" },
        { key = "pandemic", fallback = "applied" },
    }
end

-- The rule's spell by name: the cooldown manager item for a cast spell
-- (Moonfire) stands for its debuff too, and both carry the same name.
function CdmAuraStateRule:spellName()
    if self._nameFor ~= self.spell then
        self._nameFor = self.spell
        self._name = spellNameOf(self.spell)
    end
    return self._name
end

function CdmAuraStateRule:matchesFrame(names)
    local name = self:spellName()
    return name ~= nil and names[name] == true
end

function CdmAuraStateRule:setFrames(frames)
    self._frames = frames
end

-- Spoken as "Moonfire Applied" rather than "applied".
function CdmAuraStateRule:stateMessage(stateKey)
    local field = self.class:getField(stateKey)
    local label = field ~= nil and field.label or stateKey
    return { text = (self:spellName() or self:getLabel()) .. " " .. label, state = stateKey, rule = self }
end

-- One tick: the state from the frames, then the transition.
function CdmAuraStateRule:updateFromViewers(unit)
    local shown, pandemic = false, false
    for _, frame in ipairs(self._frames) do
        if auraShown(frame, unit) then
            shown = true
            if self.class.hasPandemic and inPandemic(frame) then
                pandemic = true
            end
        end
    end
    if shown then
        local state = pandemic and "pandemic" or "applied"
        if state ~= self:getCurrentState() then
            self:transitionTo(state)
        else
            self:updateResolved(state)
        end
        return
    end
    local current = self:getCurrentState()
    if current ~= "missing" and (current ~= nil or self._announceRequested) then
        self:transitionTo("missing")
    else
        self:updateResolved("missing")
    end
    self._announceRequested = false
end

-- The aura now, as the game draws it: "Moonfire, 8.7, 3 stacks, Pandemic",
-- or "Moonfire, Missing".
function CdmAuraStateRule:currentText(unit)
    local name = self:spellName() or self:getLabel()
    for _, frame in ipairs(self._frames) do
        if auraShown(frame, unit) then
            local text = name
            text = text .. secrets.whenText(timerText(frame), ", ", "")
            text = text .. secrets.whenText(stacksText(frame), ", ", " " .. L["stacks"])
            if self.class.hasPandemic and inPandemic(frame) then
                text = text .. ", " .. L["Pandemic"]
            end
            return text
        end
    end
    return name .. ", " .. L["Missing"]
end

function CdmAuraStateRule:reset()
    monitors.StateRule.reset(self)
end

function CdmAuraStateRule:getLabel()
    if self.label and self.label ~= "" then
        return self.label
    end
    if self.spell then
        local spellField = self.class:getField("spell")
        local valueStr = spellField ~= nil and spellField:getValueString(self, self.spell) or nil
        if valueStr then
            return valueStr
        end
    end
    return L["Cooldown Manager Aura Rule"]
end

-- ---------------------------------------------------------------------------
-- The monitor: the unit, the rules, and the look over the viewers.
-- ---------------------------------------------------------------------------
local CdmAuraMonitor = monitors:createType("CdmAura")
CdmAuraMonitor.label = L["Cooldown Manager Auras"]

local UNIT_CHOICES = {
    { value = "target", label = L["Target"] },
    { value = "player", label = L["Player"] },
}

CdmAuraMonitor:addFields({
    { key = "unit", type = "Choice", default = "target", persist = true, label = L["Unit"], sortPriority = 2, choices = UNIT_CHOICES },
    { key = "announceOnUnitChange", type = "Bool", default = false, persist = true, label = L["Announce on Target Change"], sortPriority = 2 },
    -- The countdown text on the tracked items gains a decimal ("8.7"); it
    -- changes what is drawn on screen, so off by default.
    { key = "decimalTimer", type = "Bool", default = false, persist = true, label = L["One Decimal Timer"], sortPriority = 2 },
})

CdmAuraMonitor:updateFields({
    {
        key = "rules",
        availableTypes = function()
            return { { key = "CdmAuraState", label = L["Cooldown Manager Aura Rule"] } }
        end,
    },
})

CdmAuraMonitor.frameSpellNames = frameSpellNames
CdmAuraMonitor.auraShown = auraShown
CdmAuraMonitor.inPandemic = inPandemic

-- The live monitors, for the viewer hooks, the target change and the key.
local live = setmetatable({}, { __mode = "k" })
local hookedViewers = {}
local eventFrame = nil

local function markAllDirty()
    for monitor in pairs(live) do
        monitor._trackingDirty = true
    end
end

-- The viewers rebuild their item frames on a layout change; take a look
-- again then. Each viewer is hooked once it exists.
local function hookViewers()
    if hooksecurefunc == nil then
        return
    end
    for _, name in ipairs(VIEWERS) do
        local viewer = _G[name]
        if viewer ~= nil and not hookedViewers[name] and viewer.RefreshLayout ~= nil then
            hookedViewers[name] = true
            hooksecurefunc(viewer, "RefreshLayout", markAllDirty)
        end
    end
end

local function ensureEvents()
    if eventFrame ~= nil or CreateFrame == nil then
        return
    end
    eventFrame = CreateFrame("Frame")
    eventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
    eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    eventFrame:SetScript("OnEvent", function(_, event)
        for monitor in pairs(live) do
            if event == "PLAYER_TARGET_CHANGED" then
                monitor:onTargetChanged()
            else
                monitor._trackingDirty = true
                monitor._skipTicks = 2
            end
        end
    end)
end

function CdmAuraMonitor:initialize(config)
    monitors.Monitor.initialize(self, config)
    self._skipTicks = 0
    self._nextRescan = 0
    live[self] = true
    ensureEvents()
end

function CdmAuraMonitor:getTrackingFields()
    return { "unit", "decimalTimer" }
end

-- Every item frame of every viewer.
function CdmAuraMonitor:itemFrames()
    local frames = {}
    for _, name in ipairs(VIEWERS) do
        local viewer = _G[name]
        if viewer ~= nil and viewer.GetItemFrames ~= nil then
            local ok, list = pcall(viewer.GetItemFrames, viewer)
            if ok and list ~= nil then
                for _, frame in ipairs(list) do
                    tinsert(frames, frame)
                end
            end
        end
    end
    return frames
end

function CdmAuraMonitor:applyTimer(frame)
    local cooldown = frame.Cooldown
    if cooldown ~= nil and cooldown.SetCountdownMillisecondsThreshold ~= nil then
        pcall(cooldown.SetCountdownMillisecondsThreshold, cooldown, self.decimalTimer and DECIMAL_BELOW_SECONDS or 0)
    end
end

-- Match the viewers' item frames to the rules by spell name.
function CdmAuraMonitor:rescan()
    hookViewers()
    local frames = self:itemFrames()
    local namesOf = {}
    for _, frame in ipairs(frames) do
        namesOf[frame] = frameSpellNames(frame)
    end
    for _, rule in ipairs(self.rules or {}) do
        if rule.matchesFrame ~= nil then
            local matched = {}
            for _, frame in ipairs(frames) do
                if rule:matchesFrame(namesOf[frame]) then
                    tinsert(matched, frame)
                    self:applyTimer(frame)
                end
            end
            rule:setFrames(matched)
        end
    end
end

-- The viewers refresh their items against the new target a tick after the
-- change (each item is forced inactive first); two ticks of quiet keep
-- that from reading as the aura dropping and coming back.
function CdmAuraMonitor:onTargetChanged()
    if self.unit ~= "target" then
        return
    end
    self._skipTicks = 2
    if self.announceOnUnitChange then
        for _, rule in ipairs(self.rules or {}) do
            if rule.reset then
                rule:reset()
            end
            rule._announceRequested = true
        end
    end
end

function CdmAuraMonitor:update()
    if not self.enabled then
        return
    end
    local now = GetTime()
    if self._trackingDirty or now >= self._nextRescan then
        self._trackingDirty = false
        self._nextRescan = now + RESCAN_SECONDS
        self:rescan()
    end
    if self._skipTicks > 0 then
        self._skipTicks = self._skipTicks - 1
        return
    end
    for _, rule in ipairs(self.rules or {}) do
        if rule.enabled and rule.updateFromViewers ~= nil then
            rule:updateFromViewers(self.unit)
        end
    end
end

function CdmAuraMonitor:unitLabel()
    for _, choice in ipairs(UNIT_CHOICES) do
        if choice.value == self.unit then
            return choice.label
        end
    end
    return tostring(self.unit)
end

function CdmAuraMonitor:getLabel()
    if self.label and self.label ~= "" then
        return self.label
    end
    return L["Cooldown Manager Auras"] .. " (" .. self:unitLabel() .. ")"
end

-- What the tracked auras read right now, each rule in turn.
function CdmAuraMonitor:currentTexts()
    local texts = {}
    for _, rule in ipairs(self.rules or {}) do
        if rule.enabled and rule.currentText ~= nil then
            tinsert(texts, rule:currentText(self.unit))
        end
    end
    return texts
end

-- The key: the tracked auras of every enabled monitor, as the game draws
-- them (time left, stacks, pandemic), target monitors first.
local module = WowVision.base ~= nil and WowVision.base.monitors or nil
if module ~= nil then
    module:registerBinding({
        type = "Function",
        key = "monitors/speakCdmAuras",
        inputs = {},
        label = L["Speak Tracked Auras"],
        interruptSpeech = true,
        func = function()
            local parts = {}
            for _, monitor in ipairs(module.getMonitors()) do
                if monitor.enabled and monitor.currentTexts ~= nil then
                    for _, text in ipairs(monitor:currentTexts()) do
                        tinsert(parts, text)
                    end
                end
            end
            if #parts == 0 then
                WowVision:speak(L["No tracked auras"])
                return
            end
            WowVision:speak(secrets.join(parts, ". "))
        end,
    })
end

monitors.CdmAuraMonitor = CdmAuraMonitor
monitors.CdmAuraStateRule = CdmAuraStateRule
