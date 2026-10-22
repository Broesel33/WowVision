-- Camera helpers shared by turn to waypoint and the pitch lock, and the
-- one-time camera settings both need.
--
-- Addons cannot turn the character (SetFacing and the turn functions are
-- protected), but the camera turns freely, and a MouselookStart/Stop pulse
-- copies the camera's yaw AND pitch onto the character. The pulse takes
-- effect one frame later.
local camera = {}

-- The saved view slot WowVision resets and snaps to: ResetView puts it at
-- the game's default, behind the character and nearly level. This
-- overwrites whatever a player saved in slot 5 (Save View 5 binding), the
-- slot least likely to be in use.
camera.VIEW_SLOT = 5

-- Set once per character on the first login with WowVision:
-- - "Always adjust camera": with the other following styles the camera
--   keeps an offset after a pulse, and turns went to random places
--   (measured on WoW Forever).
-- - Instant view switching: the snap to the view slot must be complete
--   in the same frame, or the sweep starts from a camera still blending.
camera.SETTINGS = {
    { name = "cameraSmoothStyle", value = "2" },
    { name = "cameraViewBlendStyle", value = "2" },
}

-- state.cameraStyleSet records that this character was handled, so a
-- player who changes the style back keeps it. Returns true when a setting
-- was changed.
function camera.applyOnce(state, getCVar, setCVar)
    if state.cameraStyleSet then
        return false
    end
    if getCVar == nil or setCVar == nil then
        return false
    end
    local changed = false
    for _, setting in ipairs(camera.SETTINGS) do
        local okRead, value = pcall(getCVar, setting.name)
        if not okRead then
            return false
        end
        if tostring(value) ~= setting.value then
            if not pcall(setCVar, setting.name, setting.value) then
                -- Refused: try again next login.
                return false
            end
            changed = true
        end
    end
    state.cameraStyleSet = true
    return changed
end

-- Put the camera straight behind the character, nearly level.
function camera.align()
    pcall(ResetView, camera.VIEW_SLOT)
    pcall(SetView, camera.VIEW_SLOT)
end

-- Turn the character to where the camera looks (the mouselook pulse).
function camera.transfer()
    MouselookStart()
    MouselookStop()
end

-- With the gamepad interface on, the character follows the camera only as
-- Options, Gamepad, Turn With Camera says; its default (3) is "moving, in
-- combat or casting", so standing still the sweep turned the camera alone
-- and the turn key did nothing (user test 2026-10-22, keyboard I and the
-- right stick press alike). For the length of one turn the setting is
-- "always" (2), then the player's own value comes back.
camera.TURN_WITH_CAMERA = "GamePadTurnWithCamera"
local savedTurnWithCamera = nil

local function gamepadOn()
    local gamePad = C_GamePad
    if gamePad == nil or type(gamePad.IsEnabled) ~= "function" then
        return false
    end
    local ok, enabled = pcall(gamePad.IsEnabled)
    return ok and enabled == true
end

function camera.beginTurn()
    if savedTurnWithCamera ~= nil or not gamepadOn() then
        return
    end
    local ok, value = pcall(GetCVar, camera.TURN_WITH_CAMERA)
    if not ok or value == nil or tostring(value) == "2" then
        return
    end
    if pcall(SetCVar, camera.TURN_WITH_CAMERA, "2") then
        savedTurnWithCamera = tostring(value)
    end
end

function camera.endTurn()
    if savedTurnWithCamera == nil then
        return
    end
    pcall(SetCVar, camera.TURN_WITH_CAMERA, savedTurnWithCamera)
    savedTurnWithCamera = nil
end

-- For the turn log: the setting now ("-" without a gamepad).
function camera.turnWithCameraText()
    if not gamepadOn() then
        return "-"
    end
    local ok, value = pcall(GetCVar, camera.TURN_WITH_CAMERA)
    return ok and tostring(value) or "?"
end

WowVision.navigationCamera = camera
