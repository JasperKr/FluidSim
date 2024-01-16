function love.load()
    Settings = {
        gravity = 1,
        scale = 100, -- 100 pixels = 1 meter
        smoothingRadius = 50,
        targetDensity = 0.0001,
        pressureMultiplier = 200000,
    }
    Settings.chunkSize = Settings.smoothingRadius
    Settings.inverseChunkSize = 1 / Settings.chunkSize
    require("tables")
    require("quadtree")
    require("particle")

    Particles = {}

    for x = -20, 20 do
        for y = -20, 20 do
            newParticle(x * 10 + love.graphics.getWidth() / 2 + love.math.random(),
                y * 10 + love.graphics.getHeight() / 2 + love.math.random(), 5, 0.8)
        end
    end

    SpatialLookup = {}
    StartIndices = {}
end

function love.update(dt)
    for i, particle in ipairs(Particles) do
        particle.predictedX = particle.x + particle.velocityX * dt
        particle.predictedY = particle.y + particle.velocityY * dt
    end
    updateSpatialLookup()
    updateParticleDensities()
    for i, particle in ipairs(Particles) do
        local pressureX, pressureY = calculatePressureForce(particle)
        particle.velocityX = particle.velocityX - pressureX * dt * particle.inverseDensity
        particle.velocityY = particle.velocityY - pressureY * dt * particle.inverseDensity
    end
    for i, particle in ipairs(Particles) do
        particle:update(dt)
    end
    if love.keyboard.isDown("e") then
        Settings.gravity = Settings.gravity + 1 * dt
    end
    if love.keyboard.isDown("q") then
        Settings.gravity = Settings.gravity - 1 * dt
    end
end

function love.draw()
    love.graphics.setColor(1, 1, 1, 0.3)
    local particlesInRadius, checkedPoints = getPointsInRadius(love.mouse.getPosition())
    love.graphics.circle("line", love.mouse.getX(), love.mouse.getY(), Settings.smoothingRadius)
    love.graphics.setColor(1, 0, 0, 0.8)
    for i, particle in ipairs(checkedPoints) do
        love.graphics.circle("line", particle.x, particle.y, particle.radius + 3)
    end
    love.graphics.setColor(1, 1, 1, 0.3)
    for i, particle in ipairs(Particles) do
        particle:draw()
    end
    love.graphics.setColor(1, 1, 1)
    love.graphics.print(calculateDensity(love.mouse.getPosition()))
    love.graphics.print("FPS" .. love.timer.getFPS(), 0, 20)
end

function smoothingFunction(radius, distance)
    if distance > radius then
        return 0
    end

    local volume = (math.pi * math.pow(radius, 4)) / 6;
    return (radius - distance) * (radius - distance) / volume
end

function smoothingFunctionDerivative(radius, distance)
    if distance > radius then
        return 0
    end
    local scale = 12 / (math.pi * math.pow(radius, 4))
    return scale * (radius - distance)
end

function normalize(x, y)
    local dist = math.sqrt(x * x + y * y)
    if dist == 0 then
        return 0, 0
    end
    return x / dist, y / dist
end

function length(x, y)
    return math.sqrt(x * x + y * y)
end

function calculateDensity(x, y)
    local density = 0
    local mass = 1

    for index, particle in ipairs(Particles) do
        local distance = length(x - particle.x, y - particle.y)
        local influence = smoothingFunction(Settings.smoothingRadius, distance)

        density = density + mass * influence
    end

    return density
end

function calculateProperty(x, y)
    local property = 0

    local mass = 1

    for index, particle in ipairs(Particles) do
        local distance = length(x - particle.x, y - particle.y)
        local influence = smoothingFunction(Settings.smoothingRadius, distance)
        local density = calculateDensity(x, y)

        if density <= 0.000001 then
            goto continue
        end

        property = property + particle.property * influence * mass / density

        ::continue::
    end

    return property
end

function calculatePressureForce(sampleParticle)
    local pressureX, pressureY = 0, 0

    local mass = 1

    local particles = getPointsInRadius(sampleParticle.predictedX, sampleParticle.predictedY)

    for loopIndex, particle in ipairs(particles) do
        if particle == sampleParticle then
            goto continue
        end
        local dx = sampleParticle.predictedX - particle.predictedX
        local dy = sampleParticle.predictedY - particle.predictedY

        local distance = length(dx, dy)

        local dirX, dirY
        if distance > 0 then
            dirX, dirY = dx / distance, dy / distance
        else
            dirX, dirY = 0, 0
        end

        local influence = smoothingFunctionDerivative(Settings.smoothingRadius, distance)

        local sharedPressure = calculateSharedPressure(particle.density, sampleParticle.density)
        pressureX = pressureX - sharedPressure * dirX * influence * mass * particle.inverseDensity
        pressureY = pressureY - sharedPressure * dirY * influence * mass * particle.inverseDensity
        ::continue::
    end

    return pressureX, pressureY
end

function updateParticleDensities()
    for index, particle in ipairs(Particles) do
        particle.density = calculateDensity(particle.predictedX, particle.predictedY)
        if particle.density <= 0.000001 then
            particle.inverseDensity = 0
            goto continue
        end
        particle.inverseDensity = 1 / particle.density

        ::continue::
    end
end

function densityToPressure(density)
    local diff = density - Settings.targetDensity
    local pressure = Settings.pressureMultiplier * diff
    return pressure
end

function calculateSharedPressure(density, sampleParticleDensity)
    local pressureA = densityToPressure(density)
    local pressureB = densityToPressure(sampleParticleDensity)
    local pressure = (pressureA + pressureB) / 2
    return pressure
end

function positionToIndex(x, y)
    local hashX = 5376
    local hashY = 9737333
    local index = hashX * x + y * hashY
    return index % #Particles
end

function positionToChunkCoord(x, y)
    local chunkX = math.floor(x * Settings.inverseChunkSize)
    local chunkY = math.floor(y * Settings.inverseChunkSize)
    return chunkX, chunkY
end

function updateSpatialLookup()
    for index, particle in ipairs(Particles) do
        local chunkX, chunkY = positionToChunkCoord(particle.predictedX, particle.predictedY)
        local key = positionToIndex(chunkX, chunkY)
        SpatialLookup[index] = { index, key }
        StartIndices[index] = math.huge
    end

    table.sort(SpatialLookup, function(a, b)
        return a[2] > b[2]
    end)

    for index, particle in ipairs(Particles) do
        local key = SpatialLookup[index][2]

        local previousKey = index == 1 and math.huge or SpatialLookup[index - 1][2]

        if key ~= nil and key ~= previousKey then
            StartIndices[key] = index
        end
    end
end

function getPointsInRadius(x, y)
    local radius = Settings.smoothingRadius
    local radiusSqr = radius * radius
    local centerX, centerY = positionToChunkCoord(x, y)

    local points = {}
    local checkedPoints = {}

    for chunkX = centerX - 1, centerX + 1 do
        for chunkY = centerY - 1, centerY + 1 do
            local key = positionToIndex(chunkX, chunkY)
            local startIndex = StartIndices[key]
            if startIndex then
                for index = startIndex, #SpatialLookup do
                    if SpatialLookup[index][2] ~= key then
                        break
                    end

                    local particleIndex = SpatialLookup[index][1]
                    local particle = Particles[particleIndex]
                    local distSqr = (particle.predictedX - x) * (particle.predictedX - x) +
                        (particle.predictedY - y) * (particle.predictedY - y)

                    table.insert(checkedPoints, particle)

                    if distSqr < radiusSqr then
                        table.insert(points, particle)
                    end
                end
            end
        end
    end

    return points, checkedPoints
end
