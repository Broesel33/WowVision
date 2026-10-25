local module = WowVision.base.windows.popups:createModule("questieSetup")
local L = module.L
module:setLabel(L["Questie Setup"])

local graph = WowVision.graph
local nodes = graph.nodes
local ControlId = graph.ControlId

-- Questie's one-time "Welcome to Questie" dialog (WoW: Forever, and the
-- Wrath-onward classic clients): three buttons choosing between Questie's,
-- pfQuest's and the game's own quest objective display. It is a plain
-- Questie frame, not a game popup, so nothing read it, and it sits at the
-- screen centre where the minimap scan parks the cursor, cancelling every
-- scan with "window". Its regions are unnamed: the font strings in order
-- are the title and the explanation, the children with a label are the
-- three buttons (the picture buttons have none).
local FRAME_NAME = "QuestieTutorialChooseObjectiveType"

local function hasText(widget)
    if widget.GetText == nil then
        return false
    end
    local ok, text = pcall(widget.GetText, widget)
    return ok and text ~= nil and text ~= ""
end

local function render(builder, screen)
    local frame = rawget(_G, FRAME_NAME)
    if frame == nil or not frame:IsShown() then
        return
    end
    builder:pushContext("questieSetup", L["Questie Setup"])
    for _, region in ipairs({ frame:GetRegions() }) do
        if hasText(region) then
            builder:beginStop()
            builder:addItem(
                ControlId.forObject(region),
                nodes.text({
                    label = function()
                        return region:GetText()
                    end,
                })
            )
        end
    end
    for _, child in ipairs({ frame:GetChildren() }) do
        if hasText(child) then
            builder:beginStop()
            builder:addItem(ControlId.forObject(child), nodes.proxyButton({ target = child }))
        end
    end
    builder:popContext()
end

module:registerWindow({
    type = "FrameWindow",
    name = "QuestieSetup",
    frameName = FRAME_NAME,
    graphScreen = { render = render },
})
