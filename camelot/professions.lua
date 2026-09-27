local module = WowVision.base.windows:createModule("professions")
local L = module.L
module:setLabel(L["Professions"])

local graph = WowVision.graph
local nodes = graph.nodes
local ControlId = graph.ControlId

-- The WoW: Forever professions book. Forever has no standalone book: the
-- professions key opens the retail ProfessionsFrame on its book page, a
-- card per profession (two primary, then cooking, fishing, first aid) with
-- the rank, the profession's spells (Find Herbs, Find Minerals, the
-- crafting windows), and unlearn on the primary cards. The same frame hosts
-- the retail crafting page, which is not covered yet.
--
-- The side tabs are left out: they are plain frames with no secure click,
-- and switching pages as the addon would rebuild the cards tainted, so the
-- spell buttons and unlearn (both untainted-only calls) would fail.

local CARDS = {
    "PrimaryProfession1",
    "PrimaryProfession2",
    "SecondaryProfession1",
    "SecondaryProfession2",
    "SecondaryProfession3",
}

-- A profession spell: a real click casts it (or opens its crafting window),
-- drag picks it up. The button's own OnEnter rewrites action bar highlight
-- marks, so the tooltip is filled straight from the spellbook slot.
local function spellNode(button)
    local function find()
        return button:IsShown() and button or nil
    end
    return nodes.proxyFoundButton({
        find = find,
        label = function(frame)
            return nodes.joinLabel(nodes.shownText(frame.spellString), nodes.shownText(frame.subSpellString))
        end,
        tooltip = function(tooltip, frame)
            local slot = ProfessionsBook_GetSpellBookItemSlot(frame)
            if slot ~= nil then
                tooltip:SetSpellBookItem(slot, Enum.SpellBookSpellBank.Player)
            end
        end,
        rightClick = false,
        drag = nodes.pickupAction(function()
            local slot = find() ~= nil and ProfessionsBook_GetSpellBookItemSlot(button) or nil
            if slot ~= nil then
                C_SpellBook.PickupSpellBookItem(slot, Enum.SpellBookSpellBank.Player)
            end
        end, true),
    })
end

-- One stop per card. A learned profession is a context under its name
-- holding the rank line, its spells, and unlearn; an empty slot reads its
-- header and the hint text.
local function renderCard(builder, key, card)
    builder:beginStop("profession:" .. key)
    if card.missingHeader:IsShown() then
        builder:addItem(
            ControlId.structural("missing:" .. key),
            nodes.text({
                label = function()
                    return nodes.joinLabel(nodes.shownText(card.missingHeader), nodes.shownText(card.missingText))
                end,
            })
        )
        return
    end
    local label = nodes.joinLabel(nodes.shownText(card.ProfessionName), nodes.shownText(card.specialization))
    builder:pushContext("profession:" .. key, label)
    local statusBar = card.StatusBar
    if statusBar ~= nil and statusBar:IsShown() and statusBar.Rank ~= nil then
        builder:addItem(
            ControlId.structural("rank:" .. key),
            nodes.text({
                label = function()
                    return statusBar.Rank.Text:GetText() or ""
                end,
            })
        )
    end
    -- Only shown buttons: hidden ones keep the previous occupant's spell.
    for _, button in ipairs(card.spellButtons) do
        if button:IsShown() then
            builder:addItem(ControlId.forObject(button), spellNode(button))
        end
    end
    if card.UnlearnButton ~= nil then
        builder:addItem(
            ControlId.forObject(card.UnlearnButton),
            nodes.proxyButton({ target = card.UnlearnButton, label = L["Unlearn"], hover = false })
        )
    end
    builder:popContext()
end

local function render(builder, screen)
    local frame = ProfessionsFrame
    if frame == nil or not frame:IsShown() then
        return
    end
    builder:pushContext("professions", L["Professions"])
    local book = frame.BookPage
    if book ~= nil and book:IsShown() then
        local content = book.ProfessionsContentFrame
        for _, key in ipairs(CARDS) do
            local card = content[key]
            if card ~= nil and card:IsShown() then
                renderCard(builder, key, card)
            end
        end
    else
        builder:beginStop("unimplemented")
        builder:addItem(ControlId.structural("unimplemented"), nodes.text({ label = L["Not implemented yet"] }))
    end
    builder:popContext()
end

module:registerWindow({
    type = "FrameWindow",
    name = "professions",
    frameName = "ProfessionsFrame",
    graphScreen = { render = render },
})
