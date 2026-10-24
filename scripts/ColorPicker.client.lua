local Logger = require("./Logger.client")()

local root = game.World:FindFirstChild("Core"):FindFirstChild("PaintingManager")
local runtimeobjects = root:FindFirstChild("RuntimeObjects")

local gui = self.Parent.Parent
local pixelTimer = self.Parent:FindFirstChild("PixelTimer")
local pixelCount = self.Parent:FindFirstChild("PixelCount")
local eyedropperButton = self.Parent:FindFirstChild("EyedropperButton")
local placeButton = self.Parent:FindFirstChild("Place")
local placeColor = placeButton and placeButton:FindFirstChild("Color")
local currentColor = self.Parent:FindFirstChild("CurrentColor")
local colorHex = currentColor:FindFirstChild("ColorHex")
local colorName = currentColor:FindFirstChild("ColorName")
local eyedropperCursor = self.Parent:FindFirstChild("EyedropperMouse")
local eyedropperButtonColor = eyedropperButton and eyedropperButton:FindFirstChild("Color")

local maxPixels = 20
local pixelBalance = maxPixels
local pixelNextIn = 0
local pixelStateReceivedAt = os.clock()

local eyedropperEnabled = false
local previousQDown = false
local leftClickToggle = false
local deleteMode = false
local deleteDragging = false
local placePressed = false

local hoveredX, hoveredZ
local selectedX, selectedZ, selectedY
local lastPixel, lastState
local dragStartX, dragStartZ
local dragEndX, dragEndZ

local buttonBaseColor = Color3.fromRGB(238, 65, 117)
local buttonPressedColor = Color3.fromRGB(205, 48, 94)
local placeBaseColor = placeColor and placeColor.BackgroundColor3
local placePressedColor = placeBaseColor and Color3.new(
    placeBaseColor.R * 0.65,
    placeBaseColor.G * 0.65,
    placeBaseColor.B * 0.65
)

if pixelCount then pixelCount.Text = "20/20" end
if eyedropperCursor then eyedropperCursor.Visible = false end
if eyedropperButtonColor then eyedropperButtonColor.BackgroundColor3 = buttonBaseColor end

local function playPlaceSound()
    local bgm = Instance.new("PopSFX")
    bgm:AddComponent("Sound")
    bgm.SoundId = "144115188075856358"
    bgm.Volume = 0.6
    bgm:Play()
end

local function getColorName(color)
    local r = math.floor(color.R * 255 + 0.5)
    local g = math.floor(color.G * 255 + 0.5)
    local b = math.floor(color.B * 255 + 0.5)
    local maximum = math.max(r, g, b)
    local minimum = math.min(r, g, b)
    local delta = maximum - minimum
    local brightness = maximum / 255

    if maximum <= 3 then return "Really Black"
    elseif maximum <= 12 and delta <= 8 then return "Pitch Black"
    elseif maximum <= 28 and delta <= 10 then return "Near Black"
    elseif delta <= 8 then
        if maximum < 45 then return "Charcoal"
        elseif maximum < 75 then return "Dark Gray"
        elseif maximum < 115 then return "Dim Gray"
        elseif maximum < 155 then return "Gray"
        elseif maximum < 190 then return "Silver Gray"
        elseif maximum < 225 then return "Light Gray"
        elseif maximum < 248 then return "Off White" end
        return "White"
    end

    local hue
    if maximum == r then hue = ((g - b) / delta) % 6
    elseif maximum == g then hue = (b - r) / delta + 2
    else hue = (r - g) / delta + 4 end
    hue = hue / 6

    local saturation = maximum == 0 and 0 or delta / maximum
    local name

    if hue < 0.015 or hue >= 0.985 then name = "Red"
    elseif hue < 0.035 then name = "Scarlet"
    elseif hue < 0.055 then name = "Crimson"
    elseif hue < 0.075 then name = "Vermilion"
    elseif hue < 0.095 then name = "Orange Red"
    elseif hue < 0.115 then name = "Orange"
    elseif hue < 0.135 then name = "Amber"
    elseif hue < 0.155 then name = "Gold"
    elseif hue < 0.175 then name = "Golden Yellow"
    elseif hue < 0.195 then name = "Yellow"
    elseif hue < 0.215 then name = "Lemon"
    elseif hue < 0.24 then name = "Yellow Green"
    elseif hue < 0.27 then name = "Lime"
    elseif hue < 0.30 then name = "Lime Green"
    elseif hue < 0.35 then name = "Spring Green"
    elseif hue < 0.40 then name = "Green"
    elseif hue < 0.44 then name = "Forest Green"
    elseif hue < 0.47 then name = "Sea Green"
    elseif hue < 0.50 then name = "Mint"
    elseif hue < 0.53 then name = "Turquoise"
    elseif hue < 0.56 then name = "Teal"
    elseif hue < 0.59 then name = "Cyan"
    elseif hue < 0.62 then name = "Sky Blue"
    elseif hue < 0.65 then name = "Azure"
    elseif hue < 0.69 then name = "Blue"
    elseif hue < 0.72 then name = "Royal Blue"
    elseif hue < 0.75 then name = "Navy Blue"
    elseif hue < 0.78 then name = "Indigo"
    elseif hue < 0.81 then name = "Violet"
    elseif hue < 0.84 then name = "Purple"
    elseif hue < 0.87 then name = "Amethyst"
    elseif hue < 0.90 then name = "Magenta"
    elseif hue < 0.93 then name = "Hot Pink"
    elseif hue < 0.955 then name = "Pink"
    elseif hue < 0.975 then name = "Rose"
    else name = "Red" end

    if saturation < 0.12 then return brightness < 0.5 and "Gray" or "Light Gray"
    elseif brightness < 0.12 then return "Almost Black " .. name
    elseif brightness < 0.22 then return "Very Dark " .. name
    elseif brightness < 0.35 then return "Dark " .. name
    elseif brightness > 0.92 and saturation > 0.75 then return "Brilliant " .. name
    elseif brightness > 0.82 and saturation > 0.75 then return "Bright " .. name
    elseif brightness > 0.88 and saturation < 0.4 then return "Pale " .. name
    elseif brightness > 0.78 and saturation < 0.65 then
        if hue < 0.08 or hue >= 0.94 then return "Salmon"
        elseif hue < 0.15 then return "Peach"
        elseif hue < 0.22 then return "Cream"
        elseif hue < 0.45 then return "Pastel Green"
        elseif hue < 0.62 then return "Pastel Cyan"
        elseif hue < 0.76 then return "Pastel Blue" end
        return "Pastel Pink"
    elseif saturation < 0.3 then return "Muted " .. name
    elseif hue >= 0.02 and hue < 0.10 and brightness < 0.55 then return "Burnt Orange"
    elseif hue >= 0.10 and hue < 0.18 and brightness < 0.65 then return "Ochre"
    elseif hue >= 0.18 and hue < 0.28 and brightness < 0.55 then return "Olive"
    elseif hue >= 0.28 and hue < 0.46 and brightness < 0.4 then return "Dark Forest Green"
    elseif hue >= 0.46 and hue < 0.58 and brightness < 0.45 then return "Deep Teal"
    elseif hue >= 0.58 and hue < 0.70 and brightness < 0.45 then return "Deep Blue"
    elseif hue >= 0.70 and hue < 0.82 and brightness < 0.5 then return "Indigo"
    elseif hue >= 0.82 and hue < 0.94 and brightness < 0.55 then return "Plum" end

    return name
end

local function updateColorDisplay(color)
    if not color then return end
    if colorHex then
        colorHex.Text = string.format("#%02X%02X%02X",
            math.floor(color.R * 255 + 0.5),
            math.floor(color.G * 255 + 0.5),
            math.floor(color.B * 255 + 0.5))
    end
    if colorName then colorName.Text = getColorName(color) end
end

local function makePreview(name, color, transparency, size)
    local part = Instance.new("Part")
    part.Name = name
    part.Size = size
    part.Anchored = true
    part.Collider = "None"
    part.Material = "SmoothPlastic"
    part.Color = color
    part.Transparency = transparency
    part.Position = Vector3.new(0, -1000, 0)
    part.Parent = runtimeobjects
    return part
end

local hoverPreview = makePreview("PixelHoverPreview", Color3.new(0, 0, 0), 0.35, Vector3.new(1, 0.1, 1))
local selectedPreview = makePreview("PixelSelectedPreview", buttonBaseColor, 0.35, Vector3.new(1, 0.12, 1))
local selectionPreview = makePreview("PixelDeleteSelection", Color3.new(1, 0.1, 0.1), 0.65, Vector3.new(1, 0.05, 1))

local outlineColor = Color3.fromRGB(0, 0, 0)
local outlineThickness = 0.1
local outlineLength = 0.25
local outlineHeight = 0.01
local outlineOffset = 0.005

local selectedOutline = {
    makePreview("PixelCornerNW1", outlineColor, 0, Vector3.new(outlineLength, outlineHeight, outlineThickness)),
    makePreview("PixelCornerNW2", outlineColor, 0, Vector3.new(outlineThickness, outlineHeight, outlineLength)),
    makePreview("PixelCornerNE1", outlineColor, 0, Vector3.new(outlineLength, outlineHeight, outlineThickness)),
    makePreview("PixelCornerNE2", outlineColor, 0, Vector3.new(outlineThickness, outlineHeight, outlineLength)),
    makePreview("PixelCornerSW1", outlineColor, 0, Vector3.new(outlineLength, outlineHeight, outlineThickness)),
    makePreview("PixelCornerSW2", outlineColor, 0, Vector3.new(outlineThickness, outlineHeight, outlineLength)),
    makePreview("PixelCornerSE1", outlineColor, 0, Vector3.new(outlineLength, outlineHeight, outlineThickness)),
    makePreview("PixelCornerSE2", outlineColor, 0, Vector3.new(outlineThickness, outlineHeight, outlineLength))
}

for _, part in ipairs(selectedOutline) do
    part.Material = "SmoothPlastic"
end

local function hidePreview(part)
    part.Position = Vector3.new(0, -1000, 0)
end

local function hideSelectedOutline()
    for _, part in ipairs(selectedOutline) do
        hidePreview(part)
    end
end

local ET = game.EventTable

local pixelInput = ET("pixelInput", ET.ToServer, {{"data", ET.String}})
local clearPixel = ET("clearPixel", ET.ToServer, {{"data", ET.String}})
local pixelState = ET("pixelState", ET.ToClients, {{"data", ET.String}})

pixelState.OnClientEvent:Connect(function(data)
    if type(data) ~= "string" then return end
    local count, remaining = data:match("^(%d+):(%d+)$")
    count, remaining = tonumber(count), tonumber(remaining)
    if count == nil or remaining == nil then return end
    pixelBalance = math.clamp(count, 0, maxPixels)
    pixelNextIn = math.max(0, remaining)
    pixelStateReceivedAt = os.clock()
end)

local function updatePixelTimer()
    if pixelCount then pixelCount.Text = pixelBalance .. "/" .. maxPixels end
    if pixelTimer then
        local remaining = 0
        if pixelBalance < maxPixels then
            remaining = math.max(0, math.ceil(pixelNextIn - (os.clock() - pixelStateReceivedAt)))
        end
        pixelTimer.Text = string.format("Next In %02d:%02d", math.floor(remaining / 60), remaining % 60)
    end
end

local function getPixel()
    local origin, direction = game.Input.PointerRay()
    local hit = origin and direction and game.Physics.Raycast(origin, direction, 5000)
    local instance = hit and hit.Instance
    if instance and instance.Parent == runtimeobjects and instance.Name == "PixelRun" then
        return math.floor(hit.Position.X), math.floor(hit.Position.Z), instance
    end
    return nil, nil, nil
end

local function updateDeleteSelection()
    if not deleteDragging or dragStartX == nil or dragEndX == nil then
        hidePreview(selectionPreview)
        return
    end
    local minX, maxX = math.min(dragStartX, dragEndX), math.max(dragStartX, dragEndX)
    local minZ, maxZ = math.min(dragStartZ, dragEndZ), math.max(dragStartZ, dragEndZ)
    local width, depth = maxX - minX + 1, maxZ - minZ + 1
    selectionPreview.Size = Vector3.new(width, 0.05, depth)
    selectionPreview.Position = Vector3.new(minX + width / 2, -4.42, minZ + depth / 2)
end

local function setDeleteMode(enabled)
    deleteMode = enabled
    deleteDragging = false
    dragStartX, dragStartZ, dragEndX, dragEndZ = nil, nil, nil, nil
    hidePreview(selectionPreview)
    hoverPreview.Color = enabled and Color3.new(1, 0.1, 0.1) or Color3.new(0, 0, 0)
    Logger.log(enabled and "Delete mode enabled" or "Delete mode disabled")
end

local function setEyedropperMode(enabled)
    eyedropperEnabled = enabled
    if eyedropperCursor then eyedropperCursor.Visible = enabled end
    Logger.log(enabled and "Eyedropper mode enabled" or "Eyedropper mode disabled")
end

local function samplePixel(instance, x, z)
    if not instance then
        Logger.log("Eyedropper click ignored: no pixel under cursor")
        return false
    end
    local pixelColor = instance.Color
    local r, g, b = pixelColor.R, pixelColor.G, pixelColor.B
    local maximum, minimum = math.max(r, g, b), math.min(r, g, b)
    local delta = maximum - minimum
    local hue = 0
    local saturation = maximum == 0 and 0 or delta / maximum
    if delta > 0 then
        if maximum == r then hue = ((g - b) / delta) % 6
        elseif maximum == g then hue = (b - r) / delta + 2
        else hue = (r - g) / delta + 4 end
        hue = hue / 6
    end
    self.Hue, self.Saturation, self.Brightness = hue, saturation, maximum
    updateColorDisplay(pixelColor)
    setEyedropperMode(false)
    Logger.log("Eyedropped pixel:", x, z)
    return true
end

local function placeSelectedPixel()
    if eyedropperEnabled or deleteMode then
        Logger.log("Placement unavailable in the current mode")
        return
    end
    if selectedX == nil or selectedZ == nil then
        Logger.log("Select a pixel before placing")
        return
    end
    if pixelBalance <= 0 then
        Logger.log("Cannot paint: no pixels available")
        return
    end
    local color = Color3.fromHSV(self.Hue, self.Saturation, self.Brightness)
    local data = selectedX .. ":" .. selectedZ .. ":" ..
        math.floor(color.R * 255 + 0.5) .. ":" ..
        math.floor(color.G * 255 + 0.5) .. ":" ..
        math.floor(color.B * 255 + 0.5)
    pixelInput:FireServer(data)
    Logger.log("Sent pixel:", data)
end

if placeButton then
    placeButton.UIClickable = true
    placeButton.Activated:Connect(function()
        if placeColor and placeBaseColor and placePressedColor then
            placeColor.BackgroundColor3 = placePressedColor
            task.spawn(function()
                task.wait(0.25)
                placeColor.BackgroundColor3 = placeBaseColor
            end)
        end

        playPlaceSound()
        placeSelectedPixel()
    end)
else
    Logger.log("Place button not found")
end

function Update(dt)
    if placePressed then
        if placeColor and placeBaseColor then
            placeColor.BackgroundColor3 = placeBaseColor
        end
        placePressed = false
    end

    local qDown = game.Input.KeyDown(game.Input.Key.Q)
    if eyedropperButtonColor then
        eyedropperButtonColor.BackgroundColor3 = qDown and buttonPressedColor or buttonBaseColor
    end
    if qDown and not previousQDown then setEyedropperMode(true)
    elseif not qDown and previousQDown then setEyedropperMode(false) end
    previousQDown = qDown

    local color = Color3.fromHSV(self.Hue, self.Saturation, self.Brightness)
    updateColorDisplay(color)
    updatePixelTimer()

    if game.Input.KeyPressed(game.Input.Key.X) then setDeleteMode(not deleteMode) end

    local leftDown = game.Input.ButtonDown(0)
    local x, z, instance = getPixel()
    hoveredX, hoveredZ = x, z

    if instance then
        hoverPreview.Position = Vector3.new(x + 0.5, instance.Position.Y + instance.Size.Y / 2 + 0.055, z + 0.5)
        if eyedropperCursor then eyedropperCursor.BackgroundColor3 = instance.Color end
        local key = x .. ":" .. z
        if lastPixel ~= key then lastPixel = key end
        if lastState ~= "hovering" then
            lastState = "hovering"
            Logger.log("Pixel hover preview active")
        end
    else
        hidePreview(hoverPreview)
        if lastState ~= "empty" then
            lastState = "empty"
            lastPixel = nil
            Logger.log("Not hovering over a pixel")
        end
    end

    if selectedX ~= nil and selectedZ ~= nil and selectedY ~= nil then
        selectedPreview.Position = Vector3.new(selectedX + 0.5, selectedY, selectedZ + 0.5)
        local y = selectedY - 0.08 + outlineOffset + outlineHeight / 2
        local half = outlineThickness / 2
        local len = outlineLength / 2
        local x1, x2 = selectedX - half + len, selectedX + 1 + half - len
        local z1, z2 = selectedZ - half + len, selectedZ + 1 + half - len

        selectedOutline[1].Position = Vector3.new(x1, y, selectedZ - half)
        selectedOutline[2].Position = Vector3.new(selectedX - half, y, z1)
        selectedOutline[3].Position = Vector3.new(x2, y, selectedZ - half)
        selectedOutline[4].Position = Vector3.new(selectedX + 1 + half, y, z1)
        selectedOutline[5].Position = Vector3.new(x1, y, selectedZ + 1 + half)
        selectedOutline[6].Position = Vector3.new(selectedX - half, y, z2)
        selectedOutline[7].Position = Vector3.new(x2, y, selectedZ + 1 + half)
        selectedOutline[8].Position = Vector3.new(selectedX + 1 + half, y, z2)
    else
        hidePreview(selectedPreview)
        hideSelectedOutline()
    end

    if leftDown and not leftClickToggle then
        leftClickToggle = true
        if eyedropperEnabled then
            if instance then samplePixel(instance, x, z)
            else Logger.log("Eyedropper click ignored: no pixel selected") end
        elseif hoveredX ~= nil and hoveredZ ~= nil then
            if game.Input.KeyDown(game.Input.Key.Z) then
                return
            elseif deleteMode then
                deleteDragging = true
                dragStartX, dragStartZ = hoveredX, hoveredZ
                dragEndX, dragEndZ = hoveredX, hoveredZ
                updateDeleteSelection()
                Logger.log("Delete selection started:", hoveredX, hoveredZ)
            else
                selectedX, selectedZ = hoveredX, hoveredZ
                selectedY = instance.Position.Y + instance.Size.Y / 2 + 0.08
                selectedPreview.Color = color
                Logger.log("Selected pixel:", selectedX, selectedZ)
            end
        elseif not deleteMode and not game.Input.KeyDown(game.Input.Key.Z) then
            Logger.log("Cannot select: no pixel under cursor")
        end
    end

    if not leftDown and leftClickToggle then
        leftClickToggle = false
        if deleteDragging then
            deleteDragging = false
            hidePreview(selectionPreview)
            if dragStartX ~= nil and dragEndX ~= nil then
                local minX, maxX = math.min(dragStartX, dragEndX), math.max(dragStartX, dragEndX)
                local minZ, maxZ = math.min(dragStartZ, dragEndZ), math.max(dragStartZ, dragEndZ)
                local data = "A:" .. dragStartX .. ":" .. dragStartZ .. ":" .. dragEndX .. ":" .. dragEndZ
                clearPixel:FireServer(data)
                Logger.log("Sent delete area:", data)
                if selectedX and selectedZ and selectedX >= minX and selectedX <= maxX and selectedZ >= minZ and selectedZ <= maxZ then
                    selectedX, selectedZ, selectedY = nil, nil, nil
                    hidePreview(selectedPreview)
                    hideSelectedOutline()
                end
            end
            dragStartX, dragStartZ, dragEndX, dragEndZ = nil, nil, nil, nil
        end
    end

    if deleteDragging and hoveredX ~= nil and hoveredZ ~= nil then
        dragEndX, dragEndZ = hoveredX, hoveredZ
        updateDeleteSelection()
    end
end