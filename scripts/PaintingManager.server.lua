local Logger = require("./Logger.client")()

local root = self.Parent.Parent
local runtimeobjects = root:FindFirstChild("RuntimeObjects")

local players = {}
local colors = {}
local owners = {}
local chunks = {}
local wanted = {}
local queue = {}
local queued = {}
local positions = {}
local pending = {}
local writing = {}
local pixelCooldowns = {}

local boardSize = 250
local chunkSize = 16
local radius = 150
local refreshInterval = 3
local saveInterval = 1
local maxChunksPerUpdate = 2
local authorizedClearUserId = 459
local pixelCooldownSeconds = 60

local store
local loaded = false
local opening = false
local refreshing = false
local saving = false

local timer = 0
local saveTimer = 0
local refreshTimer = 0
local jobIndex = 1

local across = math.ceil(boardSize / chunkSize)
local minimum = -boardSize / 2
local WHITE = {255, 255, 255}

local ET = game.EventTable

local pixelInput = ET("pixelInput", ET.ToServer, {
    {"data", ET.String}
})

local clearPixel = ET("clearPixel", ET.ToServer, {
    {"data", ET.String}
})

local function key(x, z)
    return x .. ":" .. z
end

local function chunkKey(x, z)
    return x .. ":" .. z
end

local function inBounds(x, z)
    return x ~= nil
        and z ~= nil
        and x == math.floor(x)
        and z == math.floor(z)
        and x >= minimum
        and z >= minimum
        and x < minimum + boardSize
        and z < minimum + boardSize
end

local function parseCoordinates(k)
    if type(k) ~= "string" then
        return nil, nil
    end

    local xs, zs = k:match("^(%-?%d+):(%-?%d+)$")

    if not xs then
        return nil, nil
    end

    local x = tonumber(xs)
    local z = tonumber(zs)

    if not inBounds(x, z) then
        return nil, nil
    end

    return x, z
end

local function isWhite(color)
    return color
        and color[1] == 255
        and color[2] == 255
        and color[3] == 255
end

local function colorAt(x, z)
    return colors[key(x, z)] or WHITE
end

local function sameColor(a, b)
    if a == nil or b == nil then
        return a == b
    end

    return a[1] == b[1]
        and a[2] == b[2]
        and a[3] == b[3]
end

local function decodePixel(value)
    if type(value) ~= "table"
        or value[1] == nil
        or value[2] == nil
        or value[3] == nil then
        return nil
    end

    local color = {
        math.clamp(math.floor(tonumber(value[1]) or 0), 0, 255),
        math.clamp(math.floor(tonumber(value[2]) or 0), 0, 255),
        math.clamp(math.floor(tonumber(value[3]) or 0), 0, 255)
    }

    if isWhite(color) then
        return nil
    end

    local owner = math.max(0, math.floor(tonumber(value[4]) or 0))

    return {
        color = color,
        owner = owner ~= 0 and owner or nil
    }
end

local function decodeStoredData(data)
    local result = {}

    if type(data) ~= "table" then
        return result
    end

    for k, value in pairs(data) do
        local x, z = parseCoordinates(k)

        if x then
            local pixel = decodePixel(value)

            if pixel then
                result[k] = pixel
            end
        end
    end

    return result
end

local function enqueue(cx, cz)
    if cx < 0 or cz < 0 or cx >= across or cz >= across then
        return
    end

    local k = chunkKey(cx, cz)

    if queued[k] or chunks[k] or not wanted[k] then
        return
    end

    queued[k] = true
    queue[#queue + 1] = {
        x = cx,
        z = cz,
        key = k
    }
end

local function destroyChunk(k)
    local chunk = chunks[k]

    if not chunk then
        return
    end

    for _, part in ipairs(chunk) do
        part:Destroy()
    end

    chunks[k] = nil
end

local function refreshChunk(cx, cz)
    local k = chunkKey(cx, cz)

    if not wanted[k] then
        return
    end

    destroyChunk(k)
    enqueue(cx, cz)
end

local function renderChunk(job)
    local x0 = minimum + job.x * chunkSize
    local z0 = minimum + job.z * chunkSize
    local width = math.min(chunkSize, boardSize - job.x * chunkSize)
    local depth = math.min(chunkSize, boardSize - job.z * chunkSize)
    local parts = {}

    for rz = 0, depth - 1 do
        local x = 0

        while x < width do
            local color = colorAt(x0 + x, z0 + rz)
            local r, g, b = color[1], color[2], color[3]
            local start = x

            x += 1

            while x < width do
                local nextColor = colorAt(x0 + x, z0 + rz)

                if nextColor[1] ~= r
                    or nextColor[2] ~= g
                    or nextColor[3] ~= b then
                    break
                end

                x += 1
            end

            local part = Instance.new("Part")
            part.Name = "PixelRun"
            part.Anchored = true
            part.Material = "SmoothPlastic"
            part.Size = Vector3.new(x - start, 1, 1)
            part.Position = Vector3.new(
                x0 + (start + x) / 2,
                -5,
                z0 + rz + 0.5
            )
            part.Color = Color3.new(r / 255, g / 255, b / 255)
            part.Parent = runtimeobjects

            parts[#parts + 1] = part
        end
    end

    chunks[job.key] = parts
end

local function rebuild()
    wanted = {}

    for _, player in ipairs(players) do
        local character = player.Character

        if character then
            local p = character.Position

            local minX = math.max(0, math.floor((p.X - radius - minimum) / chunkSize))
            local maxX = math.min(across - 1, math.floor((p.X + radius - minimum) / chunkSize))
            local minZ = math.max(0, math.floor((p.Z - radius - minimum) / chunkSize))
            local maxZ = math.min(across - 1, math.floor((p.Z + radius - minimum) / chunkSize))

            for cz = minZ, maxZ do
                for cx = minX, maxX do
                    local x0 = minimum + cx * chunkSize
                    local z0 = minimum + cz * chunkSize

                    local dx = math.max(x0 - p.X, 0, p.X - (x0 + chunkSize))
                    local dz = math.max(z0 - p.Z, 0, p.Z - (z0 + chunkSize))

                    if dx * dx + dz * dz <= radius * radius then
                        local k = chunkKey(cx, cz)
                        wanted[k] = true

                        if not chunks[k] then
                            enqueue(cx, cz)
                        end
                    end
                end
            end

            positions[player.UserId] = Vector3.new(
                math.floor(p.X),
                0,
                math.floor(p.Z)
            )
        end
    end

    for k in pairs(chunks) do
        if not wanted[k] then
            destroyChunk(k)
        end
    end
end

local function addPlayer(player)
    players[#players + 1] = player
    positions[player.UserId] = nil
end

local function removePlayer(player)
    for i, p in ipairs(players) do
        if p == player then
            table.remove(players, i)
            break
        end
    end

    positions[player.UserId] = nil
    pixelCooldowns[player.UserId] = nil
end

game.Players.PlayerAdded:Connect(addPlayer)
game.Players.PlayerRemoving:Connect(removePlayer)

local function updatePixel(x, z, color, userId)
    if not inBounds(x, z) then
        return
    end

    local k = key(x, z)

    if color then
        local c = {
            math.floor(color.R * 255 + 0.5),
            math.floor(color.G * 255 + 0.5),
            math.floor(color.B * 255 + 0.5)
        }

        if isWhite(c) then
            colors[k] = nil
            owners[k] = nil
            pending[k] = false
        else
            colors[k] = c
            owners[k] = userId
            pending[k] = {
                color = c,
                owner = userId
            }
        end
    else
        colors[k] = nil
        owners[k] = nil
        pending[k] = false
    end

    refreshChunk(
        math.floor((x - minimum) / chunkSize),
        math.floor((z - minimum) / chunkSize)
    )
end

local function loadPixels(data)
    local decoded = decodeStoredData(data)

    colors = {}
    owners = {}

    for k, pixel in pairs(decoded) do
        colors[k] = pixel.color
        owners[k] = pixel.owner
    end

    return true
end

local function refreshPixels()
    if refreshing or saving or not store or not loaded then
        return
    end

    refreshing = true

    store:fetch("Pixels", function(data, version, err)
        refreshing = false

        if err then
            warn("Pixel refresh failed:", err)
            return
        end

        local remote = decodeStoredData(data)
        local changedChunks = {}
        local checked = {}

        local function checkPixel(k)
            if checked[k] or pending[k] ~= nil or writing[k] ~= nil then
                return
            end

            checked[k] = true

            local remotePixel = remote[k]
            local remoteColor = remotePixel and remotePixel.color or nil
            local remoteOwner = remotePixel and remotePixel.owner or nil
            local oldColor = colors[k]
            local oldOwner = owners[k]

            if not sameColor(oldColor, remoteColor) or oldOwner ~= remoteOwner then
                colors[k] = remoteColor
                owners[k] = remoteOwner

                local x, z = parseCoordinates(k)

                if x then
                    local cx = math.floor((x - minimum) / chunkSize)
                    local cz = math.floor((z - minimum) / chunkSize)
                    local ck = chunkKey(cx, cz)

                    if wanted[ck] then
                        changedChunks[ck] = {x = cx, z = cz}
                    end
                end
            end
        end

        for k in pairs(colors) do
            checkPixel(k)
        end

        for k in pairs(remote) do
            checkPixel(k)
        end

        for _, chunk in pairs(changedChunks) do
            refreshChunk(chunk.x, chunk.z)
        end
    end)
end

local function savePixels()
    if saving or not next(pending) or not store then
        return
    end

    saving = true

    local batch = pending
    pending = {}

    for k, value in pairs(batch) do
        writing[k] = value
    end

    local ok, result = pcall(function()
        store:update("Pixels", function(data)
            local result = {}

            if type(data) == "table" then
                for k, value in pairs(data) do
                    local x, z = parseCoordinates(k)

                    if x then
                        local pixel = decodePixel(value)

                        if pixel then
                            result[k] = {
                                pixel.color[1],
                                pixel.color[2],
                                pixel.color[3],
                                pixel.owner or 0
                            }
                        end
                    end
                end
            end

            for k, value in pairs(batch) do
                if value == false then
                    result[k] = nil
                else
                    result[k] = {
                        value.color[1],
                        value.color[2],
                        value.color[3],
                        value.owner or 0
                    }
                end
            end

            return result
        end, function(version, err)
            saving = false

            for k, value in pairs(batch) do
                if writing[k] == value then
                    writing[k] = nil
                end

                if err and pending[k] == nil then
                    pending[k] = value
                end
            end

            if err then
                warn("Pixel save failed:", err)
            end
        end)
    end)

    if not ok then
        saving = false

        for k, value in pairs(batch) do
            if writing[k] == value then
                writing[k] = nil
            end

            if pending[k] == nil then
                pending[k] = value
            end
        end

        warn("Pixel save failed:", result)
    end
end

local function openStore()
    if opening or store then
        return
    end

    opening = true

    local ok, result = pcall(function()
        return game.CloudStore.open("PixelBoard")
    end)

    if not ok then
        opening = false
        warn("CloudStore open failed:", result)
        return
    end

    store = result

    store:fetch("Pixels", function(data, version, err)
        opening = false

        if err then
            warn("Pixel load failed:", err)
            store = nil
            return
        end

        loadPixels(data)
        loaded = true
        rebuild()

        Logger.log("Pixel board loaded")
    end)
end

pixelInput.OnServerEvent:Connect(function(sender, data)
    if not loaded or type(data) ~= "string" then
        return
    end

    local xs, zs, rs, gs, bs = data:match(
        "^(%-?%d+):(%-?%d+):(%d+):(%d+):(%d+)$"
    )

    if not xs then
        return
    end

    local x, z = tonumber(xs), tonumber(zs)
    local r, g, b = tonumber(rs), tonumber(gs), tonumber(bs)

    if not inBounds(x, z)
        or r < 0 or r > 255
        or g < 0 or g > 255
        or b < 0 or b > 255 then
        return
    end

    local now = os.clock()
    local lastPaint = pixelCooldowns[sender.UserId]

    if lastPaint and now - lastPaint < pixelCooldownSeconds then
        local remaining = math.ceil(pixelCooldownSeconds - (now - lastPaint))
        Logger.log("Paint cooldown:", remaining, "seconds remaining. UserId:", sender.UserId)
        return
    end

    pixelCooldowns[sender.UserId] = now
    updatePixel(x, z, Color3.fromRGB(r, g, b), sender.UserId)

    Logger.log("Painted pixel:", x, z, r, g, b, "UserId:", sender.UserId)
end)

clearPixel.OnServerEvent:Connect(function(sender, data)
    if sender.UserId ~= authorizedClearUserId then
        warn("Unauthorized pixel clear request:", sender.UserId)
        return
    end

    if not loaded then
        return
    end

    local x, z = parseCoordinates(data)

    if not x then
        return
    end

    updatePixel(x, z, nil, nil)

    Logger.log("Cleared pixel:", x, z, "By:", sender.UserId)
end)

function Update(dt)
    if not store then
        openStore()
        return
    end

    if not loaded then
        return
    end

    timer += dt
    saveTimer += dt
    refreshTimer += dt

    if refreshTimer >= refreshInterval then
        refreshTimer %= refreshInterval
        refreshPixels()
    end

    if timer >= 0.25 then
        timer %= 0.25

        local moved = false

        for _, player in ipairs(players) do
            local character = player.Character

            if character then
                local p = character.Position
                local old = positions[player.UserId]

                if not old
                    or math.abs(math.floor(p.X) - old.X) >= 1
                    or math.abs(math.floor(p.Z) - old.Z) >= 1 then
                    moved = true
                    break
                end
            end
        end

        if moved then
            rebuild()
        end
    end

    local built = 0

    while jobIndex <= #queue and built < maxChunksPerUpdate do
        local job = queue[jobIndex]
        jobIndex += 1

        queued[job.key] = nil

        if wanted[job.key] and not chunks[job.key] then
            renderChunk(job)
            built += 1
        end
    end

    if jobIndex > #queue then
        queue = {}
        jobIndex = 1
    end

    if saveTimer >= saveInterval then
        saveTimer %= saveInterval
        savePixels()
    end
end

clearPixel.OnServerEvent:Connect(function(sender, data)
    if sender.UserId ~= authorizedClearUserId then
        warn("Unauthorized pixel clear request:", sender.UserId)
        return
    end

    if not loaded or type(data) ~= "string" then
        return
    end

    local x1, z1, x2, z2

    if data:sub(1, 2) == "A:" then
        local xs, zs, xe, ze = data:match(
            "^A:(%-?%d+):(%-?%d+):(%-?%d+):(%-?%d+)$"
        )

        if not xs then
            return
        end

        x1, z1, x2, z2 = tonumber(xs), tonumber(zs), tonumber(xe), tonumber(ze)
    else
        x1, z1 = parseCoordinates(data)

        if not x1 then
            return
        end

        x2, z2 = x1, z1
    end

    local minX = math.max(minimum, math.min(x1, x2))
    local maxX = math.min(minimum + boardSize - 1, math.max(x1, x2))
    local minZ = math.max(minimum, math.min(z1, z2))
    local maxZ = math.min(minimum + boardSize - 1, math.max(z1, z2))

    if not inBounds(minX, minZ) or not inBounds(maxX, maxZ) then
        return
    end

    local changedChunks = {}
    local removed = 0

    for z = minZ, maxZ do
        for x = minX, maxX do
            local k = key(x, z)
            local owner = owners[k]

            if colors[k] then
                if owner then
                    Logger.log("Deleting pixel:", x, z, "Drawn by UserId:", owner)
                else
                    Logger.log("Deleting pixel:", x, z, "Painter unknown")
                end

                colors[k] = nil
                owners[k] = nil
                pending[k] = false
                removed += 1

                local cx = math.floor((x - minimum) / chunkSize)
                local cz = math.floor((z - minimum) / chunkSize)
                changedChunks[chunkKey(cx, cz)] = {x = cx, z = cz}
            end
        end
    end

    for _, chunk in pairs(changedChunks) do
        refreshChunk(chunk.x, chunk.z)
    end

    Logger.log(
        "Deleted",
        removed,
        "pixels. Area:",
        minX,
        minZ,
        "to",
        maxX,
        maxZ,
        "By UserId:",
        sender.UserId
    )
end)