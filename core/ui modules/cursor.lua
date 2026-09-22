local module = WowVision.base.ui:createModule("cursor")
local L = module.L
module:setLabel(L["Cursor"])

local ITEM_QUALITY_RARE = LE_ITEM_QUALITY_RARE or (Enum.ItemQuality and Enum.ItemQuality.Rare) or 3
local ITEM_QUALITY_HEIRLOOM = LE_ITEM_QUALITY_HEIRLOOM or (Enum.ItemQuality and Enum.ItemQuality.Heirloom) or 7

module:registerBinding({
    type = "Function",
    key = "destroyCursorItem",
    label = L["Destroy Cursor Item"],
    inputs = { "ALT-CTRL-\\", "DELETE" },
    interruptSpeech = true,
    func = function()
        local cursorType, id, _ = GetCursorInfo()
        if cursorType ~= "item" then
            return
        end
        local itemName, _, itemQuality = C_Item.GetItemInfo(id)
        if not itemName then
            return
        end
        if itemQuality and itemQuality >= ITEM_QUALITY_RARE and itemQuality ~= ITEM_QUALITY_HEIRLOOM then
            StaticPopup_Show("DELETE_GOOD_ITEM", itemName)
        else
            StaticPopup_Show("DELETE_ITEM", itemName)
        end
    end,
})
