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
local queuedJobs = {}
local positions = {}
local pending = {}
local writing = {}
local pixelInventories = {}

local boardSize = 250
local chunkSize = 16
local radius = 150
local refreshInterval = 3
local saveInterval = 1
local inventorySaveInterval = 5
local maxChunksPerUpdate = 2
local authorizedClearUserId = 459
local pixelCooldownSeconds = 60
local maxPixels = 20

local store
local loaded = false
local inventoriesLoaded = false
local opening = false
local refreshing = false
local saving = false
local inventorySaving = false
local inventorySavePending = false
local loadFailed = false

local timer = 0
local saveTimer = 0
local refreshTimer = 0
local inventoryTimer = 0
local inventorySaveTimer = 0
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

local pixelState = ET("pixelState", ET.ToClients, {
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

    local x, z = tonumber(xs), tonumber(zs)

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

local function enqueue(cx, cz, force)
    if cx < 0 or cz < 0 or cx >= across or cz >= across then
        return
    end

    local k = chunkKey(cx, cz)

    if not wanted[k] then
        return
    end

    if queued[k] then
        if force and queuedJobs[k] then
            queuedJobs[k].replace = true
        end
        return
    end

    if chunks[k] and not force then
        return
    end

    local job = {
        x = cx,
        z = cz,
        key = k,
        replace = force == true
    }

    queued[k] = true
    queuedJobs[k] = job
    queue[#queue + 1] = job
end

local function destroyParts(parts)
    if not parts then
        return
    end

    for _, part in ipairs(parts) do
        if part then
            part:Destroy()
        end
    end
end

local function destroyChunk(k)
    local chunk = chunks[k]

    if not chunk then
        return
    end

    chunks[k] = nil
    destroyParts(chunk)
end

local function refreshChunk(cx, cz)
    local k = chunkKey(cx, cz)

    if not wanted[k] then
        return
    end

    enqueue(cx, cz, true)
end

local function renderChunk(job)
    local x0 = minimum + job.x * chunkSize
    local z0 = minimum + job.z * chunkSize
    local width = math.min(chunkSize, boardSize - job.x * chunkSize)
    local depth = math.min(chunkSize, boardSize - job.z * chunkSize)
    local parts = {}

    local ok, err = pcall(function()
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
    end)

    if not ok then
        destroyParts(parts)
        warn("Chunk render failed:", job.key, err)
        return false
    end

    if not wanted[job.key] then
        destroyParts(parts)
        return false
    end

    local previous = chunks[job.key]
    chunks[job.key] = parts
    destroyParts(previous)

    return true
end

local function saveInventories()
    if not store or not inventoriesLoaded then
        return
    end

    if inventorySaving then
        inventorySavePending = true
        return
    end

    inventorySaving = true
    inventorySavePending = false

    local ok, result = pcall(function()
        store:update("PixelInventories", function(data)
            local saved = {}

            if type(data) == "table" then
                for userId, inventory in pairs(data) do
                    saved[tostring(userId)] = inventory
                end
            end

            for userId, inventory in pairs(pixelInventories) do
                saved[tostring(userId)] = {
                    count = inventory.count,
                    nextAt = inventory.nextAt
                }
            end

            return saved
        end, function(version, err)
            inventorySaving = false

            if err then
                inventorySavePending = true
                warn("Inventory save failed:", err)
            elseif inventorySavePending then
                saveInventories()
            end
        end)
    end)

    if not ok then
        inventorySaving = false
        inventorySavePending = true
        warn("Inventory save failed:", result)
    end
end

local function syncPixelState(player)
    if not inventoriesLoaded or not player then
        return
    end

    local userId = player.UserId
    local inventory = pixelInventories[userId]

    if not inventory then
        inventory = {
            count = maxPixels,
            nextAt = os.time() + pixelCooldownSeconds
        }

        pixelInventories[userId] = inventory
        saveInventories()
    end

    local now = os.time()

    if inventory.count < maxPixels and now >= inventory.nextAt then
        local gained = math.floor(
            (now - inventory.nextAt) / pixelCooldownSeconds
        ) + 1

        inventory.count = math.min(maxPixels, inventory.count + gained)

        if inventory.count >= maxPixels then
            inventory.nextAt = now + pixelCooldownSeconds
        else
            inventory.nextAt += gained * pixelCooldownSeconds
        end

        saveInventories()
    end

    local remaining = 0

    if inventory.count < maxPixels then
        remaining = math.max(0, inventory.nextAt - now)
    end

    pixelState:FireClient(
        player,
        tostring(inventory.count) .. ":" .. tostring(remaining)
    )
end

local function rebuild()
    local nextWanted = {}
    local validPlayers = 0

    for _, player in ipairs(players) do
        local character = player.Character

        if character then
            local p = character.Position

            if p then
                validPlayers += 1

                local minX = math.max(
                    0,
                    math.floor((p.X - radius - minimum) / chunkSize)
                )

                local maxX = math.min(
                    across - 1,
                    math.floor((p.X + radius - minimum) / chunkSize)
                )

                local minZ = math.max(
                    0,
                    math.floor((p.Z - radius - minimum) / chunkSize)
                )

                local maxZ = math.min(
                    across - 1,
                    math.floor((p.Z + radius - minimum) / chunkSize)
                )

                for cz = minZ, maxZ do
                    for cx = minX, maxX do
                        local x0 = minimum + cx * chunkSize
                        local z0 = minimum + cz * chunkSize

                        local dx = math.max(
                            x0 - p.X,
                            0,
                            p.X - (x0 + chunkSize)
                        )

                        local dz = math.max(
                            z0 - p.Z,
                            0,
                            p.Z - (z0 + chunkSize)
                        )

                        if dx * dx + dz * dz <= radius * radius then
                            nextWanted[chunkKey(cx, cz)] = true
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
    end

    if validPlayers == 0 then
        return
    end

    wanted = nextWanted

    for k in pairs(chunks) do
        if not wanted[k] then
            destroyChunk(k)
        end
    end

    for k in pairs(queued) do
        if not wanted[k] then
            queued[k] = nil
            queuedJobs[k] = nil
        end
    end

    for k in pairs(wanted) do
        if not chunks[k] then
            local cx, cz = k:match("^(%d+):(%d+)$")
            if cx then
                enqueue(tonumber(cx), tonumber(cz))
            end
        end
    end
end

local function addPlayer(player)
    for _, existing in ipairs(players) do
        if existing == player then
            return
        end
    end

    players[#players + 1] = player
    positions[player.UserId] = nil

    if inventoriesLoaded then
        syncPixelState(player)
    end
end

local function removePlayer(player)
    for i, p in ipairs(players) do
        if p == player then
            table.remove(players, i)
            break
        end
    end

    positions[player.UserId] = nil
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

    local ok, result = pcall(function()
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

                if not sameColor(oldColor, remoteColor)
                    or oldOwner ~= remoteOwner then
                    colors[k] = remoteColor
                    owners[k] = remoteOwner

                    local x, z = parseCoordinates(k)

                    if x then
                        local cx = math.floor((x - minimum) / chunkSize)
                        local cz = math.floor((z - minimum) / chunkSize)
                        local ck = chunkKey(cx, cz)

                        if wanted[ck] then
                            changedChunks[ck] = {
                                x = cx,
                                z = cz
                            }
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
    end)

    if not ok then
        refreshing = false
        warn("Pixel refresh request failed:", result)
    end
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
    loadFailed = false

    local ok, result = pcall(function()
        return game.CloudStore.open("PixelBoard")
    end)

    if not ok then
        opening = false
        warn("CloudStore open failed:", result)
        return
    end

    store = result

    local pixelsReady = false
    local inventoryReady = false

    local function failLoading(message, err)
        if loadFailed then
            return
        end

        loadFailed = true
        opening = false
        store = nil
        warn(message, err)
    end

    local function finishLoading()
        if loadFailed or not pixelsReady or not inventoryReady then
            return
        end

        opening = false
        loaded = true
        inventoriesLoaded = true

        for _, player in ipairs(players) do
            syncPixelState(player)
        end

        rebuild()
        Logger.log("Pixel board and inventories loaded")
    end

    store:fetch("Pixels", function(data, version, err)
        if loadFailed then
            return
        end

        if err then
            failLoading("Pixel load failed:", err)
            return
        end

        loadPixels(data)
        pixelsReady = true
        finishLoading()
    end)

    store:fetch("PixelInventories", function(data, version, err)
        if loadFailed then
            return
        end

        if err then
            failLoading("Inventory load failed:", err)
            return
        end

        pixelInventories = {}

        if type(data) == "table" then
            for userId, value in pairs(data) do
                if type(value) == "table" then
                    local count = tonumber(value.count)
                    local nextAt = tonumber(value.nextAt)
                    local numericUserId = tonumber(userId)

                    if count and nextAt and numericUserId then
                        pixelInventories[numericUserId] = {
                            count = math.clamp(
                                math.floor(count),
                                0,
                                maxPixels
                            ),
                            nextAt = math.max(0, math.floor(nextAt))
                        }
                    end
                end
            end
        end

        inventoryReady = true
        finishLoading()
    end)
end

pixelInput.OnServerEvent:Connect(function(sender, data)
    if not loaded or not inventoriesLoaded or type(data) ~= "string" then
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

    syncPixelState(sender)

    local inventory = pixelInventories[sender.UserId]

    if not inventory or inventory.count <= 0 then
        Logger.log("No pixels remaining. UserId:", sender.UserId)
        return
    end

    inventory.count -= 1

    if inventory.count == maxPixels - 1 then
        inventory.nextAt = os.time() + pixelCooldownSeconds
    end

    saveInventories()

    updatePixel(
        x,
        z,
        Color3.fromRGB(r, g, b),
        sender.UserId
    )

    syncPixelState(sender)

    Logger.log(
        "Painted pixel:",
        x,
        z,
        r,
        g,
        b,
        "UserId:",
        sender.UserId,
        "Remaining:",
        inventory.count
    )
end)

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

        x1, z1 = tonumber(xs), tonumber(zs)
        x2, z2 = tonumber(xe), tonumber(ze)
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

                changedChunks[chunkKey(cx, cz)] = {
                    x = cx,
                    z = cz
                }
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

function Update(dt)
    if not store then
        openStore()
        return
    end

    if not loaded or not inventoriesLoaded then
        return
    end

    timer += dt
    saveTimer += dt
    refreshTimer += dt
    inventoryTimer += dt
    inventorySaveTimer += dt

    if refreshTimer >= refreshInterval then
        refreshTimer %= refreshInterval
        refreshPixels()
    end

    if inventoryTimer >= 1 then
        inventoryTimer %= 1

        for _, player in ipairs(players) do
            syncPixelState(player)
        end
    end

    if timer >= 0.25 then
        timer %= 0.25

        local moved = false

        for _, player in ipairs(players) do
            local character = player.Character

            if character then
                local p = character.Position
                local old = positions[player.UserId]

                if p and (
                    not old
                    or math.abs(math.floor(p.X) - old.X) >= 1
                    or math.abs(math.floor(p.Z) - old.Z) >= 1
                ) then
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
        queuedJobs[job.key] = nil

        if wanted[job.key] and (not chunks[job.key] or job.replace) then
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

    if inventorySaveTimer >= inventorySaveInterval then
        inventorySaveTimer %= inventorySaveInterval
        saveInventories()
    end
end