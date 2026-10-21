-- The floor choice for a WowNav route (his /vn ebene): opens only when floors are stacked at the start or at the
-- target and nothing tells which one is meant (no height from the game, no route state, no height of the target, or
-- a target over several certified floors). One button per floor, lowest first; a floor without a network path from
-- here says so (his band_no_path). Enter picks it and the route request goes on with that floor.

local module = WowVision.base.navigation.wownav
local L = module.L

local graph = WowVision.graph
local nodes = graph.nodes
local ControlId = graph.ControlId

local WINDOW = "wownavFloors"

local function floorLabel(floor, index, count)
    local text = string.format(L["Floor %d of %d"], index, count)
    if index == 1 then
        text = text .. ", " .. L["lowest"]
    elseif index == count then
        text = text .. ", " .. L["highest"]
    end
    if floor.reachable == false then
        text = text .. ", " .. L["no path from here"]
    end
    return text
end

local function render(builder, screen)
    local choice = module:floorChoice()
    builder:beginStop("floors")
    local title = choice ~= nil and choice.kind == "start" and L["Choose your floor"] or L["Choose the target's floor"]
    builder:pushContext("floors", title)
    if choice == nil then
        builder:addItem(ControlId.structural("empty"), nodes.text({ label = L["Empty"] }))
    else
        local count = #choice.floors
        for index, floor in ipairs(choice.floors) do
            local captured = floor
            builder:addItem(ControlId.structural("floor:" .. index), nodes.button({
                label = floorLabel(floor, index, count),
                onActivate = function()
                    module:chooseFloor(captured)
                end,
            }))
        end
    end
    builder:popContext()
end

module:registerWindow({
    type = "ManualWindow",
    name = WINDOW,
    graphScreen = { render = render, captureClose = true },
})
