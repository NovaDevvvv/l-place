--[[
    SCRIPT NAME : Freecam Client.client.lua
    AUTHOR      : shark
    DESCRIPTION : Client-side freecam with smooth movement, mouse look,
                  adjustable flight speed, smooth FOV zoom, camera locking,
                  and mouse-controlled panning while locked.
    CONTROLS    : F6           Toggle freecam
                  Q            Lock / unlock camera
                  W A S D      Move camera
                  Space        Move up
                  Left Ctrl    Move down
                  Shift        Increase movement speed
                  Scroll       Adjust movement speed
                  C + Scroll   Adjust camera FOV
                  Q + Left Click + Mouse Move
                               Pan the locked camera
]]

local isFreecamEnabled = false
local wasF6Pressed = false
local wasLockKeyPressed = false

local originalCameraOrbit = nil
local originalCameraPosition = nil
local originalCameraOrientation = nil
local originalCameraSubject = nil
local originalCameraFov = nil

local freecamPosition = vector.create(0, 0, 0)
local freecamYaw = 0
local freecamPitch = 0

local isCameraLocked = false
local lockedPosition = nil
local lockedYaw = 0
local lockedPitch = 0

local movementVelocity = vector.create(0, 0, 0)

local movementAcceleration = 8
local movementDeceleration = 10
local movementSpeed = 20
local minimumMovementSpeed = 1
local maximumMovementSpeed = 200
local scrollSpeedSensitivity = 2
local sprintMultiplier = 3

local fovSensitivity = math.rad(2)
local minimumFov = math.rad(10)
local maximumFov = math.rad(120)
local fovSmoothing = 10
local targetFov = nil

local maximumPitch = 89
local mouseSensitivity = 1 / 20
local panSensitivity = 1 / 20

local worldUp = vector.create(0, 1, 0)

local function ResetMovementVelocity()
    movementVelocity = vector.create(0, 0, 0)
end

local function NormalizeAngle(angle)
    return (angle + 180) % 360 - 180
end

local function GetCameraBasis()
    local pitchRadians = math.rad(freecamPitch)
    local yawRadians = math.rad(freecamYaw)

    local cosPitch = math.cos(pitchRadians)
    local sinPitch = math.sin(pitchRadians)
    local cosYaw = math.cos(yawRadians)
    local sinYaw = math.sin(yawRadians)

    local right = vector.create(cosYaw, 0, -sinYaw)
    local up = vector.create(
        sinYaw * sinPitch,
        cosPitch,
        cosYaw * sinPitch
    )
    local forward = vector.create(
        -sinYaw * cosPitch,
        sinPitch,
        -cosYaw * cosPitch
    )

    return right, up, forward
end

local function ApplyFreecamTransform(camera)
    camera.Position = freecamPosition
    camera.Orientation = vector.create(freecamPitch, freecamYaw, 0)
end

local function SaveCameraState(camera)
    originalCameraOrbit = {}

    for key, value in camera.CameraOrbit do
        originalCameraOrbit[key] = value
    end

    originalCameraPosition = camera.Position
    originalCameraOrientation = camera.Orientation
    originalCameraSubject = camera.CameraOrbit.subject
    originalCameraFov = camera.CameraLens.fovY
end

local function RestoreCameraState(camera)
    if originalCameraOrbit then
        for key, value in originalCameraOrbit do
            pcall(function()
                camera.CameraOrbit[key] = value
            end)
        end
    end

    if originalCameraPosition then
        camera.Position = originalCameraPosition
    end

    if originalCameraOrientation then
        camera.Orientation = originalCameraOrientation
    end

    if originalCameraSubject ~= nil then
        camera.CameraOrbit.subject = originalCameraSubject
    end

    if originalCameraFov ~= nil then
        camera.CameraLens.fovY = originalCameraFov
    end

    originalCameraOrbit = nil
    originalCameraPosition = nil
    originalCameraOrientation = nil
    originalCameraSubject = nil
    originalCameraFov = nil

    targetFov = nil
    isFreecamEnabled = false
    isCameraLocked = false
    lockedPosition = nil

    freecamPosition = camera.Position
    freecamPitch = camera.Orientation.X
    freecamYaw = camera.Orientation.Y

    ResetMovementVelocity()
end

local function EnableFreecam(camera)
    SaveCameraState(camera)

    isFreecamEnabled = true
    isCameraLocked = false
    lockedPosition = nil

    camera.CameraOrbit.subject = nil
    camera.CameraOrbit.distance = 0

    freecamPosition = camera.Position
    freecamPitch = camera.Orientation.X
    freecamYaw = camera.Orientation.Y
    targetFov = camera.CameraLens.fovY

    ResetMovementVelocity()
end

local function ToggleCameraLock()
    isCameraLocked = not isCameraLocked

    if isCameraLocked then
        lockedPosition = freecamPosition
        lockedYaw = freecamYaw
        lockedPitch = freecamPitch

        ResetMovementVelocity()
        return
    end

    freecamPosition = lockedPosition or freecamPosition
    freecamYaw = lockedYaw
    freecamPitch = lockedPitch
    lockedPosition = nil

    ResetMovementVelocity()
end

local function UpdateTargetFov(camera, scrollDelta)
    if targetFov == nil then
        targetFov = camera.CameraLens.fovY
    end

    targetFov = math.clamp(
        targetFov - scrollDelta * fovSensitivity,
        minimumFov,
        maximumFov
    )
end

local function UpdateFovSmoothing(deltaTime, camera)
    if targetFov == nil then
        targetFov = camera.CameraLens.fovY
    end

    local currentFov = camera.CameraLens.fovY
    local interpolation = 1 - math.exp(-fovSmoothing * deltaTime)

    camera.CameraLens.fovY = currentFov
        + (targetFov - currentFov) * interpolation
end

local function UpdateMovementSpeed(scrollDelta)
    movementSpeed = math.clamp(
        movementSpeed + scrollDelta * scrollSpeedSensitivity,
        minimumMovementSpeed,
        maximumMovementSpeed
    )
end

local function UpdateCameraRotation(deltaTime, camera)
    local mouseDelta = game.Input.MouseDelta

    freecamYaw = NormalizeAngle(
        freecamYaw - mouseDelta.X * mouseSensitivity
    )

    freecamPitch = math.clamp(
        freecamPitch - mouseDelta.Y * mouseSensitivity,
        -maximumPitch,
        maximumPitch
    )

    local right, _, forward = GetCameraBasis()
    local movementDirection = vector.create(0, 0, 0)

    if game.Input.KeyDown(87) then
        movementDirection = movementDirection + forward
    end

    if game.Input.KeyDown(83) then
        movementDirection = movementDirection - forward
    end

    if game.Input.KeyDown(65) then
        movementDirection = movementDirection - right
    end

    if game.Input.KeyDown(68) then
        movementDirection = movementDirection + right
    end

    if game.Input.KeyDown(32) then
        movementDirection = movementDirection + worldUp
    end

    if game.Input.KeyDown(162) then
        movementDirection = movementDirection - worldUp
    end

    local isMoving = movementDirection.Magnitude > 0

    if isMoving then
        movementDirection = movementDirection.Unit
    end

    local currentSpeed = movementSpeed

    if game.Input.KeyDown(16) then
        currentSpeed = currentSpeed * sprintMultiplier
    end

    local targetVelocity = movementDirection * currentSpeed
    local acceleration = isMoving and movementAcceleration or movementDeceleration
    local interpolation = math.min(acceleration * deltaTime, 1)

    movementVelocity = movementVelocity
        + (targetVelocity - movementVelocity) * interpolation

    freecamPosition = freecamPosition + movementVelocity * deltaTime

    ApplyFreecamTransform(camera)
end

local function UpdateCameraPan(camera)
    local mouseDelta = game.Input.MouseDelta
    local right, up = GetCameraBasis()

    local panOffset = right * (-mouseDelta.X * panSensitivity)
        + up * (mouseDelta.Y * panSensitivity)

    freecamPosition = freecamPosition + panOffset
    lockedPosition = freecamPosition

    ApplyFreecamTransform(camera)
end

function Update(deltaTime)
    local camera = game.World.Camera

    local isF6Pressed = game.Input.KeyDown(117)
    local isLockKeyPressed = game.Input.KeyDown(81)
    local isFovModifierPressed = game.Input.KeyDown(67)

    if isF6Pressed and not wasF6Pressed then
        if isFreecamEnabled then
            RestoreCameraState(camera)
        else
            EnableFreecam(camera)
        end
    end

    wasF6Pressed = isF6Pressed

    if not isFreecamEnabled then
        return
    end

    if isLockKeyPressed and not wasLockKeyPressed then
        ToggleCameraLock()
    end

    wasLockKeyPressed = isLockKeyPressed

    local scrollDelta = game.Input.Scroll

    if scrollDelta and scrollDelta ~= 0 then
        if isFovModifierPressed then
            UpdateTargetFov(camera, scrollDelta)
        else
            UpdateMovementSpeed(scrollDelta)
        end
    end

    UpdateFovSmoothing(deltaTime, camera)

    if isF6Pressed then
        return
    end

    if isCameraLocked then
        if lockedPosition then
            freecamPosition = lockedPosition

            if game.Input.ButtonDown(0) then
				UpdateCameraPan(camera)
			else
				freecamYaw = lockedYaw
				freecamPitch = lockedPitch
				ApplyFreecamTransform(camera)
			end
        end

        return
    end

    UpdateCameraRotation(deltaTime, camera)
end