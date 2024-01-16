ChunkFunctions = {}
ChunkMt = { __index = ChunkFunctions }

function love.load()
    Spheres = {}
    require("vec")
    require("tables")
    require("quadtree")
    Settings = {
        drag = 0.0,
        size = 100.0, -- pixels per meter
        gravity = vec2(0.0, 9.81),
        chunkSize = 300
    }
    Settings.gravity = Settings.gravity * Settings.size
    Settings.inverseChunkSize = 1.0 / Settings.chunkSize

    local radius = 10
    local seperation = 2.0 * radius + 1
    for x = 0, 100 do
        for y = 0, 20 do
            newSphere(100 + x * seperation + love.math.random() * 0.01, 100 + y * seperation, 1.0,
                radius * (love.math.random() * 0.3 + 0.7),
                { 0.2, 0.4, love.math.random() * 0.5 + 0.5, 1.0 },
                3)
        end
    end

    local gradientImageData = love.image.newImageData(64, 64)
    gradientImageData:mapPixel(function(x, y)
        local dx = x - 32
        local dy = y - 32
        local distance = math.sqrt(dx * dx + dy * dy)
        local alpha = 1.0 - distance / 32.0
        return 1.0, 1.0, 1.0, alpha - 0.5
    end)


    Graphics = {
        mainCanvas = love.graphics.newCanvas(love.graphics.getWidth(), love.graphics.getHeight(), { format = "rgba32f" }),
        gradientImage = love.graphics.newImage(gradientImageData),
        thresholdShader = love.graphics.newShader("thresholdShader.glsl")
    }

    Substeps = 4
    Chunks = {}
end

function newChunk(x, y)
    return setmetatable({
        x = x,
        y = y,
        spheres = newObjectIndexedTable()
    }, ChunkMt)
end

function getChunk(x, y)
    if Chunks[x] == nil then
        Chunks[x] = {}
    end
    if Chunks[x][y] == nil then
        Chunks[x][y] = newChunk(x, y)
    end
    return Chunks[x][y]
end

function toChunkCoords(x, y)
    return math.floor(x * Settings.inverseChunkSize), math.floor(y * Settings.inverseChunkSize)
end

function toInChunkCoords(x, y)
    return x % Settings.chunkSize, y % Settings.chunkSize
end

function ChunkFunctions:addSphere(sphere)
    if self.spheres.indexTable[sphere] then
        return
    end
    self.spheres:add(sphere)
end

function ChunkFunctions:removeSphere(sphere)
    self.spheres:removeAsObject(sphere)
end

function moveSphere(sphere, oldX, oldY)
    local oldChunks, oldFound = getChunks(getAABB(oldX, oldY, sphere.radius))
    local newChunks, newFound = getChunks(getAABB(sphere.x, sphere.y, sphere.radius))

    for chunk, _ in pairs(oldFound) do
        if not newFound[chunk] then
            chunk:removeSphere(sphere)
        else
            newFound[chunk] = nil -- if we found it in both, we don't need to add it
        end
    end
    for chunk, _ in pairs(newFound) do
        chunk:addSphere(sphere)
    end
end

function findCollisions(sphere)
    local minX, minY, maxX, maxY = getAABB(sphere.x, sphere.y, sphere.radius)
    local chunks = getChunks(minX, minY, maxX, maxY)
    local collisions = {}
    for i, chunk in ipairs(chunks) do
        for i, other in ipairs(chunk.spheres) do
            if other ~= sphere then
                local dx = other.x - sphere.x
                local dy = other.y - sphere.y
                local distanceSqr = dx * dx + dy * dy
                if distanceSqr < (other.radius + sphere.radius) * (other.radius + sphere.radius) then
                    table.insert(collisions, { other, dx, dy, distanceSqr })
                end
            end
        end
    end
    return collisions
end

function getAABB(x, y, radius)
    return x - radius, y - radius, x + radius, y + radius
end

function getChunks(minX, minY, maxX, maxY)
    local minChunkX, minChunkY = toChunkCoords(minX, minY)
    local maxChunkX, maxChunkY = toChunkCoords(maxX, maxY)
    local chunks = {}
    local found = {}
    for x = minChunkX, maxChunkX do
        for y = minChunkY, maxChunkY do
            local chunk = getChunk(x, y)
            if not found[chunk] then
                table.insert(chunks, chunk)
                found[chunk] = true
            end
        end
    end
    return chunks, found
end

function newSphere(x, y, mass, radius, color, restitution)
    local t = {
        x = x,
        y = y,
        oldX = x,
        oldY = y,
        accelerationX = 0.0,
        accelerationY = 0.0,
        mass = mass,
        radius = radius,
        radiusSqr = radius * radius,
        color = color,
        restitution = restitution
    }

    t.inverseMass = 1.0 / mass

    table.insert(Spheres, t)
end

function love.update(dt)
    local substepDt = 0.01 / Substeps
    for substep = 1, Substeps do
        for index, sphere in ipairs(Spheres) do
            local oldX = sphere.x
            local oldY = sphere.y
            local accelerationX, accelerationY = applyForces(sphere)
            sphere.accelerationX = sphere.accelerationX + accelerationX
            sphere.accelerationY = sphere.accelerationY + accelerationY
            constrainPosition(sphere)
            local collisions = findCollisions(sphere)
            for i, data in ipairs(collisions) do
                solveCollision(sphere, unpack(data))
            end
            verlet(sphere, substepDt)
            moveSphere(sphere, oldX, oldY)
        end
    end
    if love.mouse.isDown(1) or love.mouse.isDown(2) then
        local pushRadius = 200.0
        local pushForce = 50000.0 * (love.mouse.isDown(2) and -1.0 or 1.0)
        local mouseX, mouseY = love.mouse.getPosition()

        local aabb = { getAABB(mouseX, mouseY, pushRadius) }
        local chunks = getChunks(unpack(aabb))

        for i, chunk in ipairs(chunks) do
            for i, sphere in ipairs(chunk.spheres) do
                local dx = sphere.x - mouseX
                local dy = sphere.y - mouseY
                local distanceSqr = dx * dx + dy * dy
                if distanceSqr < pushRadius * pushRadius then
                    local distance = math.sqrt(distanceSqr)
                    sphere.accelerationX = sphere.accelerationX + dx / distance * pushForce
                    sphere.accelerationY = sphere.accelerationY + dy / distance * pushForce
                end
            end
        end
    end
end

function love.draw()
    love.graphics.setCanvas(Graphics.mainCanvas)
    love.graphics.setBlendMode("multiply", "premultiplied")
    --love.graphics.setColor(0.99, 0.99, 0.99, 1.0)
    --love.graphics.rectangle("fill", 0, 0, love.graphics.getWidth(), love.graphics.getHeight())
    love.graphics.clear()
    love.graphics.setBlendMode("alpha")
    for i, sphere in ipairs(Spheres) do
        love.graphics.setColor(sphere.color)
        local drawRadius = sphere.radius * 10.0
        love.graphics.draw(Graphics.gradientImage, sphere.x - drawRadius, sphere.y - drawRadius,
            0.0, drawRadius * 2.0 / 64.0, drawRadius * 2.0 / 64.0, 32.0, 32.0)
        --love.graphics.circle("fill", sphere.x, sphere.y, sphere.radius)
    end
    love.graphics.setCanvas()
    love.graphics.setColor(1.0, 1.0, 1.0, 1.0)
    love.graphics.setShader(Graphics.thresholdShader)
    love.graphics.draw(Graphics.mainCanvas)
    love.graphics.setShader()

    -- draw chunks
    love.graphics.setColor(0.0, 0.0, 1.0, 0.5)
    for x, column in pairs(Chunks) do
        for y, chunk in pairs(column) do
            love.graphics.rectangle("line", x * Settings.chunkSize, y * Settings.chunkSize,
                Settings.chunkSize, Settings.chunkSize)
        end
    end

    love.graphics.setColor(1.0, 1.0, 1.0, 1.0)
    love.graphics.print("FPS: " .. love.timer.getFPS(), 10, 10)
    love.graphics.print("Sphere count: " .. #Spheres, 10, 90)
end

function verlet(sphere, dt)
    local velocityX = sphere.x - sphere.oldX
    local velocityY = sphere.y - sphere.oldY

    velocityX = velocityX * (1.0 - Settings.drag)
    velocityY = velocityY * (1.0 - Settings.drag)

    sphere.oldX = sphere.x
    sphere.oldY = sphere.y

    sphere.x = sphere.x + velocityX + sphere.accelerationX * dt * dt
    sphere.y = sphere.y + velocityY + sphere.accelerationY * dt * dt

    sphere.accelerationX = 0.0
    sphere.accelerationY = 0.0
end

function normalize(x, y)
    local length = math.sqrt(x * x + y * y)
    if length == 0 then
        return 0, 0
    end
    return x / length, y / length
end

function length(x, y)
    return math.sqrt(x * x + y * y)
end

function applyForces(sphere)
    return Settings.gravity.x, Settings.gravity.y
end

function constrainPosition(sphere)
    local width, height = love.graphics.getDimensions()
    local maxForce = 1
    if sphere.x + sphere.radius > width then
        sphere.x = sphere.x - math.min(sphere.x + sphere.radius - width, maxForce)
    end
    if sphere.x - sphere.radius < 0 then
        sphere.x = sphere.x + math.min(sphere.radius - sphere.x, maxForce)
    end
    if sphere.y + sphere.radius > height then
        sphere.y = sphere.y - math.min(sphere.y + sphere.radius - height, maxForce)
    end
    if sphere.y - sphere.radius < 0 then
        sphere.y = sphere.y + math.min(sphere.radius - sphere.y, maxForce)
    end
end

function solveCollisionsNaive(sphere)
    for index, value in ipairs(Spheres) do
        if value ~= sphere then
            local dx = value.x - sphere.x
            local dy = value.y - sphere.y
            local distanceSqr = dx * dx + dy * dy
            if distanceSqr < value.radiusSqr + sphere.radiusSqr then
                solveCollision(sphere, value, dx, dy, distanceSqr)
            end
        end
    end
end

function solveCollision(sphere, other, dx, dy, distanceSqr)
    local dist = math.max(math.sqrt(distanceSqr), sphere.radius)

    assert(dist <= sphere.radius + other.radius,
        "dist <= sphere.radius + other.radius: " .. dist .. " <= " .. sphere.radius + other.radius)

    local overlap = (sphere.radius + other.radius) - dist
    local halfOverlap = math.min(overlap * 0.5, sphere.radius * 0.01)

    local nx, ny = dx / dist, dy / dist

    sphere.x = sphere.x - nx * halfOverlap
    sphere.y = sphere.y - ny * halfOverlap

    other.x = other.x + nx * halfOverlap
    other.y = other.y + ny * halfOverlap
end
