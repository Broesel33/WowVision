-- The gamepad action bars in the bars window (Shift-F4, or both shoulders +
-- left stick press). In Forever's gamepad interface the spells sit on these
-- bars, not on the keyboard ones: their own action slots, eight per bar (the
-- D-pad and the face buttons), the bar picked by the triggers held -- none,
-- left, right or both (Blizzard_GamepadActionBars PageUnit
-- ActionBarModKeyDownStateCheck). The window shows the current page; the
-- shortcut layer's D-pad left and right turn it, as for sighted players.
local module = WowVision.base.windows.bars
local L = module.L

local graph = WowVision.graph
local ControlId = graph.ControlId

-- The pad button of each slot (Blizzard_GamepadActionBars Bindings.xml).
local SLOT_KEYS = { "PADDLEFT", "PADDUP", "PADDRIGHT", "PADDDOWN", "PAD3", "PAD4", "PAD2", "PAD1" }

local function pageUnit()
    local frame = GamepadMainActionBarFrame
    return frame ~= nil and frame.PageUnit or nil
end

local GamepadActionBar = WowVision.components.createType("bars", { key = "GamepadActionBar" })
GamepadActionBar:addFields({
    { key = "barKey", required = true },
})

function GamepadActionBar:getBar()
    local unit = pageUnit()
    return unit ~= nil and unit.actionBars ~= nil and unit.actionBars[self.barKey] or nil
end

function GamepadActionBar:isVisible()
    if not WowVision.pad.controllerUIEnabled() then
        return false
    end
    local bar = self:getBar()
    return bar ~= nil and bar.actionButtons ~= nil
end

function GamepadActionBar:renderGraph(builder)
    local bar = self:getBar()
    local label = self.label
    local unit = pageUnit()
    local ok, page = pcall(function()
        return unit:GetCurrentPage()
    end)
    if ok and page ~= nil then
        label = label .. ", " .. L["Page"] .. " " .. page
    end
    builder:pushContext(self.key, label)
    builder:startRow()
    for i, button in ipairs(bar.actionButtons) do
        local slotKey = SLOT_KEYS[i]
        builder:addItem(
            ControlId.forObject(button),
            module.actionButtonNode(button, function()
                local text = module.getActionButtonLabel(button)
                if slotKey ~= nil then
                    text = text .. ", " .. WowVision.pad.inputText(slotKey)
                end
                return text
            end)
        )
    end
    builder:endRow()
    builder:popContext()
end

WowVision.components.createComponent("bars", {
    key = "gamepadTopBar",
    type = "GamepadActionBar",
    label = L["Gamepad Bar"],
    barKey = "topBar",
})

WowVision.components.createComponent("bars", {
    key = "gamepadLeftBar",
    type = "GamepadActionBar",
    label = L["Left Trigger Bar"],
    barKey = "leftBar",
})

WowVision.components.createComponent("bars", {
    key = "gamepadRightBar",
    type = "GamepadActionBar",
    label = L["Right Trigger Bar"],
    barKey = "rightBar",
})

WowVision.components.createComponent("bars", {
    key = "gamepadBottomBar",
    type = "GamepadActionBar",
    label = L["Both Triggers Bar"],
    barKey = "bottomBar",
})
