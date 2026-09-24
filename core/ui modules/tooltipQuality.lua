local module = WowVision.base.ui.tooltip:createModule("quality")
local L = module.L
module:setLabel(L["Quality"])

-- Whether item names carry their quality colour ("Fur Boots, White").
-- Disabling the module, or one colour, drops it from names only; the
-- tooltip always reads the quality line.
local settings = module:hasSettings()

for quality = 0, 7 do
    local color = WowVision.items.getQualityColor(quality)
    local name = WowVision.items.getQualityName(quality)
    settings:add({
        type = "Bool",
        key = "quality" .. quality,
        label = name ~= nil and color .. " (" .. name .. ")" or color,
        default = true,
    })
end

-- The WoW Token shares the Heirloom colour, and its switch.
local SETTING_QUALITY = { [8] = 7 }

function WowVision.items.shouldAnnounceColor(quality)
    if not module:getEnabled() then
        return false
    end
    local key = "quality" .. tostring(SETTING_QUALITY[quality] or quality)
    return module.settings[key] ~= false
end
