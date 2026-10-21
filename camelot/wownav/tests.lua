local testRunner = WowVision.testing.testRunner
local Route = WowVision.wownavRoute
local catalog = WowVision.wownavCatalog
local text = WowVision.wownavText

-- WowNav routes on Broesel's real data: tools/headless-tests.lua loads the engine (camelot/wownav/engine) and the
-- packed data of mapdata/WowNavPacked (run tools/wownav-pack.lua first). Without the data only the parts that need
-- no network run.
local N = _G.WowVisionNavigationNavNetwork
local G = _G.WowVisionNavigationGuidance
local R = _G.WowVisionNavigationTargetResolver
local C = _G.WowVisionNavigationTargetCatalog
local haveNetwork = N ~= nil and N.Job ~= nil and type(_G.WVN7Index) == "table" and next(_G.WVN7Index) ~= nil

local STORMWIND, ELWYNN, UNDERCITY = 84, 37, 1458

-- A game stand-in: the player's position, clock and movement, changed by the test.
local function newGame()
    local game = { x = nil, y = nil, map = 0, t = 0, swimming = false, facing = 0, moving = false, speed = 7 }
    game.env = {
        N = N, G = G, R = R, C = C,
        position = function()
            return game.x, game.y, game.map
        end,
        swimming = function()
            return game.swimming
        end,
        now = function()
            return game.t
        end,
        facing = function()
            return game.facing
        end,
        moving = function()
            return game.moving
        end,
        speed = function()
            return game.speed
        end,
    }
    return game
end

local function setup()
    N.LoadIndex()
    N.ActionAllowed = function(action)
        local c = type(action) == "table" and action.conditions or nil
        return type(c) == "table" and c.status == "unconditional" and c.proof ~= nil
    end
    N.SetComfort(50)
    G.arrivalMin = 3
    N.activeMapId = 0
end

-- Runs a job to its end in slices, as the module does per frame; returns its results and the number of slices.
local function runJob(job)
    local clock = 0
    local slices = 0
    while true do
        slices = slices + 1
        local done, a, b = job:Step(2, function()
            clock = clock + 1
            return clock
        end)
        if done then
            return a, b, slices
        end
        if slices > 100000 then
            error("job does not end")
        end
    end
end

-- the first waypoint of a zone whose position binds to the network without a floor question
local function bindablePosition(zoneId, game, route)
    N.LoadZone(zoneId)
    for i = 0, 2000 do
        local x, y, z = N.Position(zoneId * N.ZONE_BASE + i)
        route.anchor.last = z
        if route:startBinding(x, y) then
            game.x, game.y = x, y
            return x, y, z
        end
    end
end

local function rowsWith(rows, category)
    for _, r in ipairs(rows) do
        if r.detail ~= nil and r.detail:find(category, 1, true) then
            return r
        end
    end
end

local suite = {
    ["a transit is proven in the plane: left the source, then in the arrival volume"] = function(t)
        local game = newGame()
        local route = Route.new(game.env)
        local action = {
            kind = "lift", fromNativeMap = 0, toNativeMap = 0, timing = { timeout_seconds = 16.667 },
            arrival = { mode = "transport_stop_volume" },
            sourceVolume = { radius = 2, x = 1596.0, y = 282.4, z = 55.4 },
            arrivalVolume = { radius = 2, x = 1602.0, y = 287.0, z = -41.2 },
        }
        route:startAction(action, {})
        -- standing at the top: never an arrival, even with a wide arrival distance
        t:assertNil(route:observeAction(1596.0, 282.4, 0, 5))
        -- the ride goes down: the source is left, the arrival circle (widened to 5) holds the player
        t:assertNil(route:observeAction(1599.0, 285.0, 0, 5), "nearer the source than the arrival: not yet")
        t:assertEqual(route:observeAction(1601.5, 286.5, 0, 5), "arrived")
    end,

    ["a transit into another map needs the map change"] = function(t)
        local game = newGame()
        local route = Route.new(game.env)
        local action = {
            kind = "tram", fromNativeMap = 0, toNativeMap = 369, timing = { timeout_seconds = 30 },
            arrival = { mode = "native_map_volume" },
            sourceVolume = { radius = 10, x = -8346.5, y = 514.0, z = 96.6 },
            arrivalVolume = { radius = 10, x = 68.3, y = 2490.9, z = -4.3 },
        }
        route:startAction(action, {})
        t:assertNil(route:observeAction(68.3, 2490.9, 0, 3), "the same point on the old map")
        t:assertEqual(route:observeAction(70, 2492, 369, 3), "arrived")
    end,

    ["a transit that takes longer than its three phases ends"] = function(t)
        local game = newGame()
        local route = Route.new(game.env)
        route:startAction({ timing = { timeout_seconds = 10 }, fromNativeMap = 0, toNativeMap = 0,
            sourceVolume = { radius = 2, x = 0, y = 0 }, arrivalVolume = { radius = 2, x = 50, y = 0 } }, {})
        game.t = 29
        t:assertNil(route:observeAction(0, 0, 0, 3))
        game.t = 31
        t:assertEqual(route:observeAction(0, 0, 0, 3), "timeout")
    end,

    ["turning on the spot is no travel for the stagnation window"] = function(t)
        local game = newGame()
        local route = Route.new(game.env)
        game.speed = 0
        route:checkApproach(0, 0, 50, 0)
        route:checkApproach(3, 0, 50, 1)
        t:assertEqual(route.stagnationTravel, 0, "speed 0: the position noise is not counted")
        game.speed = nil
        route:checkApproach(6, 0, 50, 2)
        t:assertEqual(route.stagnationTravel, 3, "unknown speed (secret): counted, his fallback")
    end,

    ["a dyn target is named from its key and place, with its suffix"] = function(t)
        t:assertEqual(text.targetName({ nameKey = "portal", nameParam = "Darnassus" }), "Portal to Darnassus")
        t:assertEqual(text.targetName({ nameKey = "elevator", nameParam = "Undercity",
            nameSuffix = { key = "upper" } }), "Elevator: Undercity (upper)")
        t:assertEqual(text.targetName({ nameKey = "tram_entrance" }), "Deeprun Tram entrance")
        t:assertEqual(text.targetName({ nameEn = "Guard", nameDe = "Wache" }, true), "Wache")
        t:assertEqual(text.targetName({ nameEn = "Guard", nameDe = "Wache" }, false), "Guard")
        t:assertEqual(text.categories({ category = { "quest_giver", "trainer" } }), "quest giver, trainer")
        t:assertEqual(text.categories({ category = "object_type_5" }), "object type 5")
    end,
}

if haveNetwork then
    suite["the packed data decodes and a route is searched in time slices"] = function(t)
        setup()
        local game = newGame()
        local route = Route.new(game.env)
        local x, y = bindablePosition(STORMWIND, game, route)
        t:assertNotNil(x, "a bindable Stormwind waypoint")
        local start = route:startBinding(x, y)
        local farId = STORMWIND * N.ZONE_BASE + 3000
        local result, _, slices = runJob(N.Job(function()
            return N.RouteIds(start, farId)
        end))
        t:assertNotNil(result, "a route across Stormwind")
        t:assertTrue(slices > 1, "the search yielded at least once")
    end

    suite["the continent catalogue lists both layers with categories and zone, searchable"] = function(t)
        setup()
        local rows = catalog.zoneRows(N, C, STORMWIND, false)
        t:assertTrue(#rows > 100)
        local innkeeper = rowsWith(rows, "innkeeper")
        t:assertNotNil(innkeeper, "Stormwind has an innkeeper")
        t:assertTrue(innkeeper.search:find("innkeeper", 1, true) ~= nil, "the category is searchable")
        local dyn = 0
        for _, r in ipairs(rows) do
            if r.layer == "dyn" then
                dyn = dyn + 1
            end
        end
        t:assertTrue(dyn > 0, "Stormwind has dyn targets (portals, tram entrance, crossings)")
        local contract = catalog.contract(innkeeper, 0)
        t:assertTrue(C.Validate(contract), "a row makes a valid target")
    end

    suite["a target is resolved, routed and walked to with his arrival rules"] = function(t)
        setup()
        local game = newGame()
        local route = Route.new(game.env)
        local x, y = bindablePosition(STORMWIND, game, route)
        local rows = catalog.zoneRows(N, C, STORMWIND, false)
        local target = rowsWith(rows, "innkeeper")
        local outcome = runJob(N.Job(route.prepare, route, catalog.contract(target, 0), { nativeMapId = 0 }))
        if outcome.kind == "choose" then
            target.levels = nil
            outcome = runJob(N.Job(route.prepare, route,
                (function()
                    local c = catalog.contract(target, 0)
                    c.heightBand = 1
                    return c
                end)(), { nativeMapId = 0 }))
        end
        t:assertEqual(outcome.kind, "start", tostring(outcome.reason))
        route:begin(outcome.plan, catalog.contract(target, 0), outcome.result, target.n)
        t:assertTrue(route.active)
        -- walk: stand on each waypoint in turn
        local arrived
        for step = 1, 2000 do
            game.t = game.t + 0.3
            local id = route.path[route.pathIndex]
            game.x, game.y = N.Position(id)
            game.moving, game.facing = true, 0
            local event = route:update(game.x, game.y)
            if event and event.kind == "arrived" then
                arrived = event
                break
            end
        end
        t:assertNotNil(arrived, "the route ends at the target")
    end

    suite["a target over several certified floors asks the floor and marks the reachable ones"] = function(t)
        setup()
        local game = newGame()
        local route = Route.new(game.env)
        bindablePosition(STORMWIND, game, route)
        local rows = catalog.zoneRows(N, C, STORMWIND, false)
        local stacked
        for _, r in ipairs(rows) do
            if r.levels ~= nil and #r.levels > 1 then
                stacked = r
                break
            end
        end
        t:assertNotNil(stacked, "Stormwind has a target over several floors")
        local outcome = runJob(N.Job(route.prepare, route, catalog.contract(stacked, 0), { nativeMapId = 0 }))
        t:assertEqual(outcome.kind, "choose")
        t:assertEqual(#outcome.result.bands, #stacked.levels, "exactly the certified floors")
        local any = false
        for i = 1, #stacked.levels do
            any = any or outcome.reachable[i] == true
        end
        t:assertTrue(any, "at least one floor has a path from here")
        local chosen = catalog.contract(stacked, 0)
        for i = 1, #stacked.levels do
            if outcome.reachable[i] then
                chosen.heightBand = i
                break
            end
        end
        local second = runJob(N.Job(route.prepare, route, chosen, { nativeMapId = 0 }))
        t:assertEqual(second.kind, "start", tostring(second.reason))
    end

    suite["the choke fallback steps back once at a gate when the player drifted sideways"] = function(t)
        setup()
        local game = newGame()
        local route = Route.new(game.env)
        local zone = N.LoadZone(STORMWIND)
        -- a GATE waypoint and a neighbour of it
        local gateId, fromId
        for i = 0, zone.n - 1 do
            local id = zone.base + i
            if G.Choke(id) then
                local adj = zone.adj[i + 1]
                if adj and #adj >= 2 then
                    gateId, fromId = id, zone.base + adj[1]
                    break
                end
            end
        end
        t:assertNotNil(gateId, "Stormwind has gates")
        route.active = true
        route.path = { fromId, gateId }
        route.pathIndex = 2
        local ax, ay = N.Position(fromId)
        local bx, by = N.Position(gateId)
        local dx, dy = bx - ax, by - ay
        local l = math.sqrt(dx * dx + dy * dy)
        -- 20 yd beside the middle of the run-up segment
        local px, py = (ax + bx) / 2 - dy / l * 20, (ay + by) / 2 + dx / l * 20
        game.t = 100
        t:assertEqual(route:handleBlockage(px, py), "fallback")
        t:assertEqual(route.pathIndex, 1)
        route.pathIndex = 2
        game.t = 110
        t:assertNil(route:handleBlockage(px, py), "the same waypoint is locked for 20 s")
    end

    suite["a route over an Undercity lift ends at the lift and continues from its far end"] = function(t)
        setup()
        local game = newGame()
        local route = Route.new(game.env)
        local zone = N.LoadZone(UNDERCITY)
        local lift
        for _, action in ipairs(zone.actions) do
            if action.kind == "lift" then
                lift = action
                break
            end
        end
        t:assertNotNil(lift)
        -- from the lift's start to a point next to its far end: the route takes the lift
        local plan = runJob(N.Job(route.planToNode, route, lift.toNode, { id = lift.fromNode }))
        t:assertNotNil(plan)
        t:assertNotNil(plan.pendingAction, "the route uses the lift")
        t:assertEqual(plan.path[#plan.path], lift.fromNode, "cut at the lift")
        route:startAction(plan.pendingAction, { contract = {} })
        local tx, ty = N.Position(lift.toNode)
        local fx, fy = N.Position(lift.fromNode)
        t:assertNil(route:observeAction(fx, fy, 0, 3))
        route:observeAction(tx, ty, 0, 3)
        local request, toNode = route:actionArrival()
        t:assertNotNil(request)
        t:assertEqual(toNode, lift.toNode)
        local _, _, tz = N.Position(lift.toNode)
        t:assertEqual(route.anchor.last, tz, "the height of the far end anchors the next start")
    end
end

testRunner:addSuite("WowNav routes", suite)
