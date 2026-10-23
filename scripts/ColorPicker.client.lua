
local Logger = require("./Logger.client")()

local root = game.World:FindFirstChild("Core"):FindFirstChild("PaintingManager")
local runtimeobjects = root:FindFirstChild("RuntimeObjects")

local gui = self.Parent.Parent

local highlight = Instance.new("Part")
highlight.Name = "PixelHighlight"
highlight.Size = Vector3.new(1, 0.1, 1)
highlight.Anchored = true
highlight.Collider = "None"
highlight.Material = "SmoothPlastic"
highlight.Color = Color3.new(0, 0, 0)
highlight.Transparency = 0.35
highlight.Position = Vector3.new(0, -1000, 0)
highlight.Parent = runtimeobjects

local selectionPreview = Instance.new("Part")
selectionPreview.Name = "PixelSelection"
selectionPreview.Anchored = true
selectionPreview.Collider = "None"
selectionPreview.Material = "SmoothPlastic"
selectionPreview.Color = Color3.new(1, 0.1, 0.1)
selectionPreview.Transparency = 0.65
selectionPreview.Size = Vector3.new(1, 0.05, 1)
selectionPreview.Position = Vector3.new(0, -1000, 0)
selectionPreview.Parent = runtimeobjects

local hoveredX, hoveredZ
local lastPixel, lastState
local leftClickToggle = false
local deleteMode = false
local deleteDragging = false
local dragStartX, dragStartZ
local dragEndX, dragEndZ
local lastXDown = false

local ET = game.EventTable

local pixelInput = ET("pixelInput", ET.ToServer, {
    {"data", ET.String}
})

local clearPixel = ET("clearPixel", ET.ToServer, {
    {"data", ET.String}
})

local function getPixel()
    local origin, direction = game.Input.PointerRay()
    local hit = origin and direction and game.Physics.Raycast(origin, direction, 5000)
    local instance = hit and hit.Instance

    if instance and instance.Parent == runtimeobjects and instance.Name == "PixelRun" then
        local position = hit.Position
        return math.floor(position.X), math.floor(position.Z), instance
    end

    return nil, nil, nil
end

local function updateSelection()
    if not deleteDragging or dragStartX == nil or dragEndX == nil then
        selectionPreview.Position = Vector3.new(0, -1000, 0)
        return
    end

    local minX = math.min(dragStartX, dragEndX)
    local maxX = math.max(dragStartX, dragEndX)
    local minZ = math.min(dragStartZ, dragEndZ)
    local maxZ = math.max(dragStartZ, dragEndZ)

    local width = maxX - minX + 1
    local depth = maxZ - minZ + 1

    selectionPreview.Size = Vector3.new(width, 0.05, depth)
    selectionPreview.Position = Vector3.new(
        minX + width / 2,
        -4.42,
        minZ + depth / 2
    )
end

local function setDeleteMode(enabled)
    deleteMode = enabled
    deleteDragging = false
    dragStartX, dragStartZ = nil, nil
    dragEndX, dragEndZ = nil, nil
    selectionPreview.Position = Vector3.new(0, -1000, 0)

    if deleteMode then
        highlight.Color = Color3.new(1, 0.1, 0.1)
        Logger.log("Delete mode enabled")
    else
        highlight.Color = Color3.new(0, 0, 0)
        Logger.log("Delete mode disabled")
    end
end


function Update(dt)

    local color = Color3.fromHSV(self.Hue, self.Saturation, self.Brightness)

    if game.Input.KeyPressed(game.Input.Key.X) then
        setDeleteMode(not deleteMode)
    end

    local x, z, instance = getPixel()
    hoveredX, hoveredZ = x, z

    if instance then
        highlight.Position = Vector3.new(
            x + 0.5,
            instance.Position.Y + instance.Size.Y / 2 + 0.055,
            z + 0.5
        )

        local k = x .. ":" .. z

        if lastPixel ~= k then
            lastPixel = k
        end

        if lastState ~= "hovering" then
            lastState = "hovering"
            Logger.log("Pixel highlight active")
        end
    else
        hoveredX, hoveredZ = nil, nil
        highlight.Position = Vector3.new(0, -1000, 0)

        if lastState ~= "empty" then
            lastState = "empty"
            lastPixel = nil
            Logger.log("Not hovering over a pixel")
        end
    end

    if deleteDragging and hoveredX ~= nil then
        dragEndX, dragEndZ = hoveredX, hoveredZ
        updateSelection()
    end

    local leftDown = game.Input.ButtonDown(0)

    if leftDown and not leftClickToggle then
        leftClickToggle = true

        if hoveredX ~= nil and hoveredZ ~= nil then
            if deleteMode then
                deleteDragging = true
                dragStartX, dragStartZ = hoveredX, hoveredZ
                dragEndX, dragEndZ = hoveredX, hoveredZ
                updateSelection()
                Logger.log("Delete selection started:", hoveredX, hoveredZ)
            elseif color then
                local data = hoveredX .. ":" .. hoveredZ .. ":" ..
                    math.floor(color.R * 255 + 0.5) .. ":" ..
                    math.floor(color.G * 255 + 0.5) .. ":" ..
                    math.floor(color.B * 255 + 0.5)

                pixelInput:Push(data)
                Logger.log("Sent pixel:", data)
            else
                Logger.log("Cannot paint: invalid color picker values")
            end
        elseif not deleteMode then
            Logger.log("Cannot paint: no pixel selected")
        end
    end

    if not leftDown and leftClickToggle then
        leftClickToggle = false

        if deleteDragging then
            deleteDragging = false
            selectionPreview.Position = Vector3.new(0, -1000, 0)

            if dragStartX ~= nil and dragEndX ~= nil then
                local data = "A:"
                    .. dragStartX .. ":"
                    .. dragStartZ .. ":"
                    .. dragEndX .. ":"
                    .. dragEndZ

                clearPixel:Push(data)
                Logger.log("Sent delete area:", data)
            end

            dragStartX, dragStartZ = nil, nil
            dragEndX, dragEndZ = nil, nil
        end
    end
end
