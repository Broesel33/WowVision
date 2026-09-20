local HyperlinkTooltipType = WowVision.tooltips:createType("Hyperlink")

function HyperlinkTooltipType:initialize(tooltip)
    WowVision.TooltipType.initialize(self, tooltip)
    self.link = nil
end

-- Fill the private tooltip frame from link data ("item:2589:..."). Links the
-- client cannot render as a tooltip (a player, a channel) throw in
-- SetHyperlink; those simply leave no tooltip.
function HyperlinkTooltipType:fill()
    local frame = self.tooltip.frame
    frame:SetOwner(WorldFrame, "ANCHOR_NONE")
    local ok = pcall(frame.SetHyperlink, frame, self.link)
    return ok and frame:NumLines() > 0
end

-- data: { type = "Hyperlink", link = string|function }
function HyperlinkTooltipType:activate(widget, data)
    local link = data.link
    if type(link) == "function" then
        link = link()
    end
    self.link = link
    if link == nil then
        return
    end
    self:fill()
    self.tooltip.activeFrame = self.tooltip.frame
end

function HyperlinkTooltipType:deactivate()
    self.link = nil
end

-- An item the client has not cached yet renders empty at first; ask again
-- at read time, when the data has usually arrived.
function HyperlinkTooltipType:beforeRead()
    if self.link ~= nil and self.tooltip.frame:NumLines() == 0 then
        self:fill()
    end
end

WowVision.HyperlinkTooltipType = HyperlinkTooltipType
