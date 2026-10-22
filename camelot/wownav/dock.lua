-- The dock guidance of Broesel's WowNav core in WowVision: his DockNavigation.lua (engine/) with what his core
-- (WowVisionNavigation.lua, WowVisionNavigationSelectListEntry, WaypointIsReached, the waiting branch of OnUpdate and
-- WowVisionNavigationStartDirect) does around it. A dock is a stop of the tram, a ship or a zeppelin with a proven
-- waiting point (manual_wait). Vehicles are never part of a route: the player waits, boards by ear and rides.
--
-- - Choosing a dock routes to its waiting point on foot; the route ends only inside the waiting circle (at most 2 yd).
--   Arrived, his text says what to wait for, and a beacon leads to the boarding orientation point a few yards ahead
--   (his ride beacon); it ends there, or when the player leaves the dock.
-- - Choosing the other dock of the same line while standing at a dock notes it (his passive mode): no route, no
--   beacon. Near that dock the turn key (I) faces it.
-- - The boarding points are list entries ("At the vehicle"); choosing one leads straight to it.
--
-- What WowVision adds: standing at a dock counts as having reached it (his core needs the route there first); a dock
-- of the other line at the same far stop is taken as that line's own dock (the Deeprun Tram has two lines with a
-- dock each at both ends); and near the noted dock it is said once that the turn key faces it.
-- Where the dock's waiting node lies outside its waiting circle (the Deeprun Tram in data 9423773: the waiting point
-- is at track level, the route ends on the platform about 7 yd away), his circle rule could never end the route: there
-- the route ends at the waiting node as any route does, standing at that node counts as standing at the dock, and the
-- boarding beacon starts only where his rule gives it a point.

-- (the headless tests load this file without WowVision's navigation: no beacon paths there)
local maps = WowVision.base ~= nil and WowVision.base.navigation ~= nil and WowVision.base.navigation.maps or nil
local catalog = WowVision.wownavCatalog
local L = WowVision:getLocale()

local dock = {}
WowVision.wownavDock = dock

local function D()
    return _G.WowVisionNavigationDockNavigation
end

-- The continent's nav (catalog.lua) with the fields his dock module reads for one zone: his ContinentNavData gives
-- the zone, its fingerprint as the export and waiting-point proof, and the interaction captures of the decoded zones.
function dock.nav(N, zoneId)
    local nav = catalog.activeNav()
    if nav == nil then
        return nil
    end
    local entry = zoneId and N.index[zoneId]
    local fingerprint = entry and entry.fingerprint or nil
    nav.zoneId = zoneId
    nav.exportFingerprint = fingerprint
    nav.waitpoint_schema, nav.waitpointFingerprint = 1, fingerprint
    nav.approach_schema, nav.approachFingerprint = 1, fingerprint
    local captures = {}
    for id in pairs(nav.zoneSet) do
        local zone = N.zones[id] or N.decoded[id]
        for _, capture in ipairs(zone and zone.captures or {}) do
            captures[#captures + 1] = capture
        end
    end
    nav.interactionCaptures = captures
    return nav
end

-- The transit facilities of the continent, resolved where their zones are decoded (his targetList).
local function facilities(nav)
    return WowVisionNavigationTargetList(nav, function(target)
        return target.type == "transit_facility"
    end, true)
end

-- The zones around a point decoded, so its facilities are resolved and proven.
local function loadAround(N, x, y)
    for _, zoneId in ipairs(N.ZonesForPoint(x, y)) do
        N.LoadZone(zoneId)
    end
end

-- How near the waiting node a player counts as standing at the dock (the arrival radius of a waypoint).
local NODE_REACH = 3.0

-- The dock's waiting node: x, y and whether it lies inside the waiting circle; nil without a node.
local function waitingNode(N, target)
    if target.nodeId == nil then
        return nil
    end
    local x, y = N.Position(target.nodeId)
    if x == nil then
        return nil
    end
    return x, y, (x - target.x) ^ 2 + (y - target.y) ^ 2 <= target.waitingRadius ^ 2
end

local function stopKey(target)
    return type(target.transportStopId) == "string" and target.transportStopId:match("^(.*):[^:]*$") or nil
end

-- A list row is a dock when its target waits for a vehicle.
function dock.isDockRow(row)
    return type(row) == "table" and row.interactionMode == "manual_wait"
end

-- The full target of a list row (his list entry), resolved.
function dock.target(N, row)
    loadAround(N, row.x, row.y)
    local nav = dock.nav(N, row.zoneId)
    if nav == nil then
        return nil, nil
    end
    for _, target in ipairs(facilities(nav)) do
        if target.id == row.tid then
            return target, nav
        end
    end
    return nil, nav
end

-- WowVision: a player standing at a proven dock has reached it, also without a route there (his Arrival, silent).
local function adoptStanding(N, x, y)
    local Dock = D()
    if Dock.reached ~= nil or x == nil then
        return
    end
    loadAround(N, x, y)
    local nav = dock.nav(N, nil)
    if nav == nil then
        return
    end
    for _, target in ipairs(facilities(nav)) do
        local zoneNav = dock.nav(N, target.zoneId)
        if Dock:IsDock(target, zoneNav) then
            local reach = target.waitingRadius + (target.boardingPreviewDistance or 0)
            local nx, ny = waitingNode(N, target)
            local reach2 = math.max(NODE_REACH, _G.WowVisionNavigationGuidance.arrivalMin or 0)
            if (x - target.x) ^ 2 + (y - target.y) ^ 2 <= reach * reach
                or (nx ~= nil and (x - nx) ^ 2 + (y - ny) ^ 2 <= reach2 * reach2) then
                Dock:Reset(false)
                Dock.reached = {
                    id = target.id, zoneId = zoneNav.zoneId, navFingerprint = zoneNav.exportFingerprint,
                    waitpointFingerprint = zoneNav.waitpointFingerprint, lastX = x, lastY = y,
                }
                return
            end
        end
    end
end

-- WowVision: the dock of the line the player stands at that serves the same far stop as the chosen one.
local function sameLine(N, nav, target)
    local Dock = D()
    local reached = Dock.reached
    if reached == nil then
        return target
    end
    local source, counterpart
    for _, candidate in ipairs(facilities(nav)) do
        if candidate.id == reached.id then
            source = candidate
        end
    end
    if source == nil or source.transportRouteId == target.transportRouteId then
        return target
    end
    for _, candidate in ipairs(facilities(nav)) do
        if candidate.transportRouteId == source.transportRouteId and candidate.id ~= source.id
            and stopKey(candidate) ~= nil and stopKey(candidate) == stopKey(target) then
            counterpart = candidate
        end
    end
    return counterpart or target
end

-- The choice of a dock row (his WowVisionNavigationSelectListEntry for manual_wait). Returns
--   "passive", target              the other dock of the line is noted; nothing to walk
--   "route", target                walk to the dock's waiting point (the route ends inside the waiting circle)
--   "fail", reason text
function dock.choose(N, row, x, y)
    local Dock = D()
    local target, nav = dock.target(N, row)
    if target == nil then
        return "fail", WowVisionNavigationText("dock_no_wait_proof")
    end
    adoptStanding(N, x, y)
    target = sameLine(N, nav, target)
    -- his ChoosePassive reads the nav of the player's zone (the reached dock's) and the fingerprint of the
    -- target's zone
    if Dock.reached ~= nil then
        local targetEntry = N.index[target.zoneId]
        if Dock:ChoosePassive(target, dock.nav(N, Dock.reached.zoneId), targetEntry and targetEntry.fingerprint) then
            return "passive", target
        end
    end
    local zoneNav = dock.nav(N, target.zoneId)
    if not Dock:IsDock(target, zoneNav) then
        return "fail", WowVisionNavigationText("dock_no_wait_proof")
    end
    return "route", target
end

-- His WaypointIsReached for a waiting target: the last waypoint counts only inside the proven waiting circle. nil
-- when the waiting node lies outside that circle (the route then ends at the node like any route).
function dock.waitAreaCheck(N, target)
    local _, _, inside = waitingNode(N, target)
    if inside == false then
        return nil
    end
    return function(x, y)
        local nav = dock.nav(N, target.zoneId)
        return nav ~= nil and D():WaitAreaReached(target, x, y, nav)
    end
end

-- The route reached the dock: his Arrival (the text) and the ride beacon to the boarding point.
function dock.arrived(N, target, x, y)
    local nav = dock.nav(N, target.zoneId)
    if nav == nil or not D():IsDock(target, nav) then
        WowVisionNavigationPrint(WowVisionNavigationText("wait_proof_invalid"))
        return nil
    end
    D():Arrival(target, nav, x, y)
    -- the boarding beacon only where his rule gives a point (it would forget the dock otherwise)
    if dock.alignment(N, x, y) == nil then
        return nil
    end
    return dock.boardingPath(N)
end

-- The point the turn key faces without a route (his AlignmentTarget): at a reached dock the boarding point, with a
-- noted dock that dock within 30 yd. Returns x, y or nil.
function dock.alignment(N, x, y)
    local Dock = D()
    local context = Dock ~= nil and (Dock.reached or Dock.passive) or nil
    if context == nil or x == nil then
        return nil
    end
    local nav = dock.nav(N, context.zoneId)
    if nav == nil then
        return nil
    end
    local id, px, py = Dock:AlignmentTarget(x, y, nav)
    if id == nil then
        return nil
    end
    return px, py, id
end

-- The boarding points of the docks as list entries (his Dock:BoardingTargets), with their distance.
function dock.boardingRows(N, x, y)
    local nav = dock.nav(N, nil)
    if nav == nil or x == nil then
        return {}
    end
    local rows = {}
    for _, target in ipairs(facilities(nav)) do
        local zoneNav = dock.nav(N, target.zoneId)
        local entry = D():BoardingTarget(target, zoneNav)
        if entry ~= nil then
            local dx, dy = entry.x - x, entry.y - y
            rows[#rows + 1] = {
                id = "wownav:" .. entry.id, n = WowVisionNavigationTargetName(entry),
                detail = WowVisionNavigationTargetName(target), x = entry.x, y = entry.y, z = entry.z,
                boardingTargetId = entry.boardingTargetId, zoneId = target.zoneId, entry = entry,
                distance = math.sqrt(dx * dx + dy * dy),
            }
        end
    end
    return rows
end

-- ---- a beacon to one point, ended by his small capture disc (PointReached), not by WowVision's arrival distance
if maps == nil then
    return
end
local PointPath = WowVision.Class("WowNavPointPath", maps.Path)
dock.PointPath = PointPath

-- step(x, y) -> px, py (the point now) and reached (true when the player got there), or nil when the guidance ends.
function PointPath:initialize(step, onReached, onEnded)
    maps.Path.initialize(self)
    self.step = step
    self.onReached = onReached
    self.onEnded = onEnded
end

function PointPath:start()
    self.active = true
    self.complete = false
    local x, y = UnitPosition("player")
    self:update(x, y)
end

function PointPath:moveBy()
    return nil
end

function PointPath:finish()
    self.active = false
    self.complete = true
    self.beacon = nil
end

function PointPath:update(x, y)
    if not self.active or self.complete then
        return nil
    end
    if x == nil then
        x, y = UnitPosition("player")
    end
    if x == nil then
        return
    end
    local px, py, reached = self.step(x, y)
    if px == nil then
        self:finish()
        if maps.path == self then
            maps:stopPath()
        end
        if self.onEnded then
            self.onEnded()
        end
        return
    end
    if reached then
        self:finish()
        if maps.path == self then
            maps:stopPath()
        end
        self.onReached()
        return
    end
    local current = self.currentWaypoint
    if current == nil or current.x ~= px or current.y ~= py then
        self.currentWaypoint = { x = px, y = py }
        self.waypoints = { self.currentWaypoint }
        self.beacon = maps.Beacon:new(self.currentWaypoint)
    end
    if self.beacon then
        self.beacon:update()
    end
end

-- His ride beacon after the arrival at a dock (Dock:BeaconTarget): to the boarding point; reached, his text.
function dock.boardingPath(N)
    local Dock = D()
    local name
    local path = PointPath:new(function(x, y)
        local context = Dock.reached
        if context == nil then
            return nil
        end
        local nav = dock.nav(N, context.zoneId)
        if nav == nil then
            return nil
        end
        local id, px, py, reachedName = Dock:BeaconTarget(x, y, nav)
        if id == nil then
            return nil
        end
        name = reachedName
        return px, py, reachedName ~= nil
    end, function()
        WowVisionNavigationPrint(WowVisionNavigationText("stop_boarding_point_reached", name or ""))
    end)
    return path
end

-- His WowVisionNavigationStartDirect for a boarding entry: straight to the point, checked against its proof.
function dock.directPath(N, row)
    local Dock = D()
    local entry = row.entry
    local context = { lastX = nil, lastY = nil }
    return PointPath:new(function(x, y)
        local nav = dock.nav(N, row.zoneId)
        if nav == nil or not Dock:DirectTargetValid(entry, nav) then
            return nil
        end
        local reached = Dock:PointReached(context, entry.x, entry.y, x, y, entry.arrivalRadius)
        return entry.x, entry.y, reached
    end, function()
        WowVisionNavigationPrint(string.format(L["Arrived"] .. " %s", row.n or ""))
    end, function()
        WowVisionNavigationPrint(WowVisionNavigationText("stop_boarding_proof_changed"))
    end)
end
