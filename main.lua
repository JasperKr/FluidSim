function love.load()
    Settings = {
        gravity = 1,
        scale = 100, -- 100 pixels = 1 meter
        smoothingRadius = 40,
        targetDensity = 0.0001,
        pressureMultiplier = 800000,
        viscosity = 0.1,
    }
    Settings.chunkSize = Settings.smoothingRadius
    Settings.inverseChunkSize = 1 / Settings.chunkSize
    Settings.gravity = Settings.gravity * Settings.scale
    require("tables")
    require("quadtree")
    require("particle")
    require("vec")

    Particles = {}

    --for x = -30, 30 do
    --    for y = -30, 30 do
    --        newParticle(x * 10 + love.graphics.getWidth() / 2 + love.math.random(),
    --            y * 10 + love.graphics.getHeight() / 2 + love.math.random(), 5, 0.8)
    --    end
    --end

    SpatialLookup = {}
    StartIndices = {}
end

function love.update(dt)
    newParticle(love.graphics.getWidth() / 2 + love.math.random() * 100 - 50,
        love.graphics.getHeight() / 2 + love.math.random() * 100 - 50, 5, 0.8)
    timings = {}
    local startTime = love.timer.getTime()
    for i, particle in ipairs(Particles) do
        particle.predictedX = particle.x + particle.velocityX / 120
        particle.predictedY = particle.y + particle.velocityY / 120
    end
    table.insert(timings, { time = love.timer.getTime() - startTime, name = "predict" })
    startTime = love.timer.getTime()
    updateSpatialLookup()
    table.insert(timings, { time = love.timer.getTime() - startTime, name = "lookup" })
    startTime = love.timer.getTime()
    updateParticleDensities()
    table.insert(timings, { time = love.timer.getTime() - startTime, name = "density" })
    startTime = love.timer.getTime()
    for i, particle in ipairs(Particles) do
        local pressureX, pressureY = calculatePressureForce(particle)
        local viscosityX, viscosityY = calculateViscosityForce(particle)
        particle.velocityX = particle.velocityX -
            (pressureX - viscosityX * Settings.viscosity) * dt * particle.inverseDensity
        particle.velocityY = particle.velocityY -
            (pressureY - viscosityY * Settings.viscosity) * dt * particle.inverseDensity
    end
    table.insert(timings, { time = love.timer.getTime() - startTime, name = "pressure" })
    startTime = love.timer.getTime()
    for i, particle in ipairs(Particles) do
        particle:update(dt)
    end
    table.insert(timings, { time = love.timer.getTime() - startTime, name = "update" })

    if love.mouse.isDown(1, 2) then
        for i, particle in ipairs(Particles) do
            local force = updateMouseForces(500, love.mouse.isDown(2) and -5000 or 5000, particle)
            particle.velocityX = particle.velocityX + force.x * dt
            particle.velocityY = particle.velocityY + force.y * dt
        end
    end
end

function love.draw()
    love.graphics.setColor(1, 1, 1, 0.3)
    for i, particle in ipairs(Particles) do
        particle:draw()
    end
    love.graphics.setColor(1, 1, 1)
    love.graphics.print(calculateDensity(love.mouse.getPosition()))
    love.graphics.print("FPS" .. love.timer.getFPS(), 0, 20)

    for i, timing in ipairs(timings) do
        love.graphics.print(timing.name .. ": " .. timing.time, 0, 20 * i + 20)
    end
end

function updateMouseForces(radius, strength, particle)
    local mousePos = vec2(love.mouse.getPosition())

    local force = vec2()
    local offset = mousePos - vec2(particle.x, particle.y)

    local distSqr = offset:lengthSqr()

    if distSqr < radius * radius then
        local dist = math.sqrt(distSqr)
        local dir = dist <= 0.0001 and vec2() or offset / dist

        local centerT = 1 - dist / radius

        force = (dir * strength - vec2(particle.velocityX, particle.velocityY)) * centerT
    end

    return force
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

    local particles
    if type(x) == "number" then
        particles = getPointsInRadius(x, y)
    else
        particles = x.pointsInRadius
        y = x.predictedY
        x = x.predictedX
    end
    for index, particle in ipairs(particles) do
        local distance = length(x - particle.x, y - particle.y)
        local influence = smoothingFunction(Settings.smoothingRadius, distance)

        density = density + mass * influence
    end

    return density
end

function calculatePressureForce(sampleParticle)
    local pressureX, pressureY = 0, 0

    local mass = 1

    for loopIndex, particle in ipairs(sampleParticle.pointsInRadius) do
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
        particle.density = calculateDensity(particle)
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
    for index, particle in ipairs(Particles) do
        particle.pointsInRadius = getPointsInRadius(particle.predictedX, particle.predictedY)
    end
end

function getPointsInRadius(x, y)
    local radius = Settings.smoothingRadius
    local radiusSqr = radius * radius
    local centerX, centerY = positionToChunkCoord(x, y)

    local points = {}

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

                    if distSqr < radiusSqr then
                        table.insert(points, particle)
                    end
                end
            end
        end
    end

    return points
end

function viscositySmoothingFunction(distance, radius)
    if distance > radius then
        return 0
    end

    local volume = math.pi * math.pow(radius, 8) / 4;
    local value = radius * radius - distance * distance
    return value * value * value / volume
end

function calculateViscosityForce(particle)
    local forceX, forceY = 0, 0
    local x, y = particle.predictedX, particle.predictedY

    for index, otherParticle in ipairs(particle.pointsInRadius) do
        local dx = x - particle.predictedX
        local dy = y - particle.predictedY

        local distance = length(dx, dy)

        local influence = viscositySmoothingFunction(distance, Settings.smoothingRadius)
        forceX = forceX + influence * (otherParticle.velocityX - particle.velocityX)
        forceY = forceY + influence * (otherParticle.velocityY - particle.velocityY)
    end

    return forceX, forceY
end
