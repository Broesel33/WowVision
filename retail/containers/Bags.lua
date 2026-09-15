local module = WowVision.base.windows.containers
local L = module.L

local graph = WowVision.graph
local nodes = graph.nodes
local ControlId = graph.ControlId

-- Retail bags: one component covering every shown container frame, in
-- either bag mode.
--
-- COMBINED mode (ContainerFrameCombinedBags) is what a sighted player
-- sees as ONE inventory: a grid ten slots wide with no bag boundaries
-- drawn, the backpack first and the other bags following, wrapping every
-- ten. The screen mirrors that: one tab stop, rows of ten in visual order
-- (derived from the buttons' actual positions, so it always matches the
-- picture), column-preserving up and down, and no mention of which bag a
-- slot sits in, since the picture shows none. The bag slot buttons follow
-- as their own bar. Players who want bags kept apart switch the game to
-- individual mode.
--
-- INDIVIDUAL mode is one frame per bag: one tab stop per bag, the bag slot
-- button first, then the slots in order, as on classic.
--
-- After the bags each frame contributes its own stops: the search box (an
-- edit box, alone in its stop), then the frame's controls -- the bag menu
-- (filters, cleanup, mode switch: a modern dropdown), the sort button,
-- money, and the extra-slots purchase button when offered.
local Bags = WowVision.components.createType("containers", { key = "RetailBags" })

local BAG_SLOT_BUTTONS = {
    [0] = "MainMenuBarBackpackButton",
    [1] = "CharacterBag0Slot",
    [2] = "CharacterBag1Slot",
    [3] = "CharacterBag2Slot",
    [4] = "CharacterBag3Slot",
    [5] = "CharacterReagentBag0Slot",
}

local function shownContainerFrames()
    local frames = {}
    if ContainerFrameUtil_EnumerateContainerFrames == nil then
        return frames
    end
    for _, frame in ContainerFrameUtil_EnumerateContainerFrames() do
        if frame ~= nil and frame:IsShown() then
            tinsert(frames, frame)
        end
    end
    return frames
end

function Bags:isOpen()
    return #shownContainerFrames() > 0
end

-- The frame's shown item buttons grouped by bag id, slots ascending.
local function slotsByBag(frame)
    local groups = {}
    local order = {}
    for _, itemButton in ipairs(frame.Items or {}) do
        if itemButton:IsShown() then
            local bagID = itemButton.GetBagID ~= nil and itemButton:GetBagID() or frame:GetID()
            local list = groups[bagID]
            if list == nil then
                list = {}
                groups[bagID] = list
                tinsert(order, bagID)
            end
            tinsert(list, itemButton)
        end
    end
    table.sort(order)
    for _, list in pairs(groups) do
        table.sort(list, function(a, b)
            return a:GetID() < b:GetID()
        end)
    end
    return order, groups
end

local function bagLabel(bagID)
    local name = C_Container.GetBagName(bagID)
    if name == nil or name == "" then
        if bagID == 0 then
            return BACKPACK_TOOLTIP or L["Bags"]
        end
        return L["Bags"] .. " " .. bagID
    end
    return name
end

local function renderBag(builder, frame, bagID, buttons)
    local label = bagLabel(bagID)
    builder:beginStop("bag:" .. bagID)
    -- Keyed: two identical bags must not share a context identity.
    builder:pushContext("bag:" .. bagID, label)
    local slotButton = _G[BAG_SLOT_BUTTONS[bagID] or ""]
    if slotButton ~= nil then
        builder:addItem(
            ControlId.structural("bagButton:" .. bagID),
            module.itemSlotNode(slotButton, L["Bag Slot"] .. " " .. label)
        )
    end
    for _, itemButton in ipairs(buttons) do
        builder:addItem(
            ControlId.forObject(itemButton),
            module.itemSlotNode(itemButton, function()
                return module.getBagItemLabel(itemButton)
            end)
        )
    end
    builder:popContext()
end

-- The frame's shown item buttons in visual order: rows top to bottom by
-- screen position, left to right within a row.
local function visualRows(frame)
    local buttons = {}
    for _, itemButton in ipairs(frame.Items or {}) do
        if itemButton:IsShown() and itemButton:GetTop() ~= nil then
            tinsert(buttons, itemButton)
        end
    end
    table.sort(buttons, function(a, b)
        local at, bt = a:GetTop(), b:GetTop()
        if math.abs(at - bt) > 1 then
            return at > bt
        end
        return a:GetLeft() < b:GetLeft()
    end)
    local rows = {}
    local current = nil
    local currentTop = nil
    for _, itemButton in ipairs(buttons) do
        local top = itemButton:GetTop()
        if current == nil or math.abs(top - currentTop) > 1 then
            current = {}
            currentTop = top
            tinsert(rows, current)
        end
        tinsert(current, itemButton)
    end
    return rows
end

-- One grid for a combined frame: plain rows, no bag boundaries, exactly
-- as drawn. Which physical bag a slot belongs to is not part of the
-- picture, so it is not spoken either; individual mode is the view for
-- that.
local function renderGrid(builder, frame, frameKey, separateBags)
    local rows = visualRows(frame)
    builder:beginStop(frameKey .. ":grid")
    builder:pushContext(frameKey .. ":grid", L["Bags"])
    if #rows == 0 then
        builder:addItem(ControlId.structural(frameKey .. ":empty"), nodes.text({ label = L["Empty"] }))
    end
    for _, row in ipairs(rows) do
        builder:startRow("grid")
        for _, itemButton in ipairs(row) do
            builder:addItem(
                ControlId.forObject(itemButton),
                module.itemSlotNode(itemButton, function()
                    return module.getBagItemLabel(itemButton)
                end)
            )
        end
        builder:endRow()
    end
    builder:popContext()

    -- The grid fills from the bottom-right, so a short row sits at the top
    -- pushed right. Up and down deliberately follow POSITION in the row,
    -- not the screen column: from the short row's first cell, down lands
    -- on the full row's first cell, so no column is ever skipped for a
    -- reader who starts top-left and works down.

    -- The bag slot buttons as one bar after the grid. A bag the game
    -- still shows as its own frame (the reagent bag does, even in
    -- combined mode) keeps its slot button with that frame.
    builder:beginStop(frameKey .. ":bagSlots")
    builder:pushContext(frameKey .. ":bagSlots", L["Bag Slots"])
    builder:startRow()
    local any = false
    for bagID = 0, 5 do
        local slotButton = _G[BAG_SLOT_BUTTONS[bagID] or ""]
        if slotButton ~= nil and slotButton:IsShown() and not separateBags[bagID] then
            any = true
            builder:addItem(
                ControlId.structural("bagButton:" .. bagID),
                module.itemSlotNode(slotButton, L["Bag Slot"] .. " " .. bagLabel(bagID))
            )
        end
    end
    if not any then
        builder:addItem(ControlId.structural(frameKey .. ":noBagSlots"), nodes.text({ label = L["Empty"] }))
    end
    builder:endRow()
    builder:popContext()
end

local function moneyText()
    local money = GetMoney()
    if money == nil or WowVision.isSecret(money) then
        return nil
    end
    return GetCoinText(money, " ")
end

local function renderFrameControls(builder, frame, frameKey)
    -- The search box is one shared edit box parented to the frame that
    -- owns it; it gets a stop of its own so tabbing in starts typing.
    local searchBox = BagItemSearchBox
    if searchBox ~= nil and searchBox:GetParent() == frame and searchBox:IsShown() then
        builder:beginStop(frameKey .. ":search")
        builder:addItem(
            ControlId.forObject(searchBox),
            nodes.proxyEditBox({ editBox = searchBox, label = L["Search"] })
        )
    end

    builder:beginStop(frameKey .. ":controls")
    builder:pushContext(frameKey .. ":controls", L["Bag Controls"])
    if frame.PortraitButton ~= nil then
        builder:addItem(
            ControlId.forObject(frame.PortraitButton),
            nodes.proxyDropdown({ target = frame.PortraitButton, label = L["Bag Menu"] })
        )
    end
    local sortButton = BagItemAutoSortButton
    if sortButton ~= nil and sortButton:GetParent() == frame then
        builder:addItem(ControlId.forObject(sortButton), nodes.proxyButton({ target = sortButton, label = L["Sort Bags"] }))
    end
    if frame.MoneyFrame ~= nil and frame.MoneyFrame:IsShown() then
        builder:addItem(
            ControlId.structural(frameKey .. ":money"),
            nodes.text({
                label = function()
                    local text = moneyText()
                    if text == nil then
                        return L["Money"]
                    end
                    return L["Money"] .. ", " .. text
                end,
            })
        )
    end
    if frame.AddSlotsButton ~= nil then
        builder:addItem(
            ControlId.forObject(frame.AddSlotsButton),
            nodes.proxyButton({ target = frame.AddSlotsButton, label = L["Add Slots"] })
        )
    end
    builder:popContext()
end

function Bags:renderGraph(builder)
    local frames = shownContainerFrames()
    -- Bags shown as their own frame alongside the combined grid.
    local separateBags = {}
    for _, frame in ipairs(frames) do
        if not (frame.IsCombinedBagContainer ~= nil and frame:IsCombinedBagContainer()) then
            separateBags[frame:GetID()] = true
        end
    end
    for _, frame in ipairs(frames) do
        local frameKey = "frame:" .. (frame:GetName() or tostring(frame:GetID()))
        if frame.IsCombinedBagContainer ~= nil and frame:IsCombinedBagContainer() then
            renderGrid(builder, frame, frameKey, separateBags)
        else
            local order, groups = slotsByBag(frame)
            for _, bagID in ipairs(order) do
                renderBag(builder, frame, bagID, groups[bagID])
            end
        end
        renderFrameControls(builder, frame, frameKey)
    end
end
