local module = WowVision.base.windows:createModule("colorPicker")
local L = module.L
module:setLabel(L["Color Picker"])

local graph = WowVision.graph
local nodes = graph.nodes
local ControlId = graph.ControlId

-- The game's colour picker, opened by colour swatches in the settings
-- window and elsewhere. Retail's picker has a hex entry box, which is
-- the one part of a colour wheel a keyboard can drive exactly; it gets
-- its own stop, then Okay and Cancel. Classic pickers lack the hex box
-- and offer only the buttons here (their wheel and value slider are
-- mouse-only widgets).

local function render(builder, screen)
    local frame = ColorPickerFrame
    if frame == nil or not frame:IsShown() then
        return
    end
    local content = frame.Content
    local hexBox = content ~= nil and content.HexBox or nil
    if hexBox ~= nil and hexBox:IsShown() then
        builder:beginStop("hex")
        builder:addItem(ControlId.forObject(hexBox), nodes.proxyEditBox({ editBox = hexBox, label = L["Hex Color"] }))
    end

    local footer = frame.Footer
    local okay = footer ~= nil and footer.OkayButton or ColorPickerOkayButton
    local cancel = footer ~= nil and footer.CancelButton or ColorPickerCancelButton
    builder:beginStop("buttons")
    builder:pushContext("buttons", L["Color Picker"])
    builder:startRow()
    if okay ~= nil then
        builder:addItem(ControlId.forObject(okay), nodes.proxyButton({ target = okay }))
    end
    if cancel ~= nil then
        builder:addItem(ControlId.forObject(cancel), nodes.proxyButton({ target = cancel }))
    end
    builder:endRow()
    builder:popContext()
end

module:registerWindow({
    type = "FrameWindow",
    name = "ColorPickerFrame",
    frameName = "ColorPickerFrame",
    graphScreen = { render = render },
})
