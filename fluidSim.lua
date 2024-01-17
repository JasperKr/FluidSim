local sim = {}

local function pow4(x)
    local x2 = x * x
    return x2 * x2
end

function sim.smoothingFunction(radius, distance)
    if distance >= radius then
        return 0
    end
    local volume = (math.pi * pow4(radius));
    local dx = radius - distance
    return dx * dx * 6 / volume
end

function sim.smoothingFunctionDerivative(radius, distance)
    if distance >= radius then
        return 0
    end
    local scale = 12 / (math.pi * pow4(radius))
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

function lengthSqr(x, y)
    return x * x + y * y
end

function sim.calculateDensity(x, y, pointsInRadius)
    local density = 0
    if type(x) == "number" then
        local particles = pointsInRadius or sim.getPointsInRadius(x, y)
        for index, particle in ipairs(particles) do
            local distance = length(x - particle.x, y - particle.y)
            local influence = sim.smoothingFunction(Settings.smoothingRadius, distance)

            density = density + particle.mass * influence
        end
    else
        local sampleParticle = x

        for index = 1, sampleParticle.pointsInRadiusAmount do
            local particle = sampleParticle.pointsInRadius[index]
            local distance = length(sampleParticle.predictedX - particle.x, sampleParticle.predictedY - particle.y)
            local influence = sim.smoothingFunction(Settings.smoothingRadius, distance)

            density = density + particle.mass * influence
        end
    end

    return density
end

function calculatePressureForce(sampleParticle, pointsInRadius, x, y, density)
    local pressureX, pressureY = 0, 0

    if sampleParticle then
        for loopIndex = 1, sampleParticle.pointsInRadiusAmount do
            local particle = sampleParticle.pointsInRadius[loopIndex]

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

            local influence = sim.smoothingFunctionDerivative(Settings.smoothingRadius, distance)

            local sharedPressure = sim.calculateSharedPressure(particle.density, sampleParticle.density)
            pressureX = pressureX -
                sharedPressure * dirX * influence
            pressureY = pressureY -
                sharedPressure * dirY * influence
            ::continue::
        end
    else
        for loopIndex, particle in ipairs(pointsInRadius) do
            local dx = x - particle.predictedX
            local dy = y - particle.predictedY

            local distance = length(dx, dy)

            local dirX, dirY
            if distance > 0 then
                dirX, dirY = dx / distance, dy / distance
            else
                dirX, dirY = 0, 0
            end

            local influence = sim.smoothingFunctionDerivative(Settings.smoothingRadius, distance)

            local sharedPressure = sim.calculateSharedPressure(particle.density, density)
            pressureX = pressureX -
                sharedPressure * dirX * influence
            pressureY = pressureY -
                sharedPressure * dirY * influence
        end
    end

    return pressureX * Settings.scale, pressureY * Settings.scale
end

function sim.updateParticleDensities()
    for index, particle in ipairs(Particles) do
        particle.density = sim.calculateDensity(particle)
        if particle.density <= 0.000001 then
            particle.inverseDensity = 1000000
            goto continue
        end
        particle.inverseDensity = 1 / particle.density

        ::continue::
    end
end

function sim.densityToPressure(density)
    return Settings.sharedPressureMultiplier * (density - Settings.targetDensity)
end

function sim.calculateSharedPressure(density, sampleParticleDensity)
    return sim.densityToPressure(density) + sim.densityToPressure(sampleParticleDensity)
end

function sim.positionToIndex(x, y)
    return (x * 5376 + y * 9737333) % #Particles
end

function sim.positionToChunkCoord(x, y)
    return math.floor(x * Settings.inverseChunkSize), math.floor(y * Settings.inverseChunkSize)
end

local tableSort = function(a, b)
    return a[2] > b[2]
end

function sim.updateSpatialLookup()
    for index, particle in ipairs(Particles) do
        local chunkX, chunkY = sim.positionToChunkCoord(particle.predictedX, particle.predictedY)
        local key = sim.positionToIndex(chunkX, chunkY)
        SpatialLookup[index] = { index, key }
        StartIndices[index] = math.huge
    end

    table.sort(SpatialLookup, tableSort)

    for index, particle in ipairs(Particles) do
        local key = SpatialLookup[index][2]

        local previousKey = index == 1 and math.huge or SpatialLookup[index - 1][2]

        if key and key ~= previousKey then
            StartIndices[key] = index
        end
    end
end

function sim.getPointsInRadius(x, y)
    local centerX, centerY = sim.positionToChunkCoord(x, y)

    local points = {}

    for chunkX = centerX - 1, centerX + 1 do
        for chunkY = centerY - 1, centerY + 1 do
            local key = sim.positionToIndex(chunkX, chunkY)
            local startIndex = StartIndices[key]
            if startIndex then
                for index = startIndex, #SpatialLookup do
                    if SpatialLookup[index][2] ~= key then
                        break
                    end

                    local particleIndex = SpatialLookup[index][1]
                    local particle = Particles[particleIndex]

                    local dx = particle.predictedX - x
                    local dy = particle.predictedY - y

                    local distSqr = dx * dx + dy * dy

                    if distSqr < Settings.smoothingRadiusSqr then
                        table.insert(points, particle)
                    end
                end
            end
        end
    end

    return points
end

function sim.updatePointsInRadius(sampleParticle)
    sampleParticle.chunkUpdateTimer = sampleParticle.chunkUpdateTimer - 1

    local dx = sampleParticle.updateX - sampleParticle.predictedX
    local dy = sampleParticle.updateY - sampleParticle.predictedY

    if sampleParticle.chunkUpdateTimer <= 0 or dx * dx + dy * dy > Settings.moveBoundrySqr then
        local centerX, centerY = sim.positionToChunkCoord(sampleParticle.predictedX, sampleParticle.predictedY)

        local pointsIndex = 1

        for chunkX = centerX - 1, centerX + 1 do
            for chunkY = centerY - 1, centerY + 1 do
                local key = sim.positionToIndex(chunkX, chunkY)
                local startIndex = StartIndices[key]
                if startIndex then
                    for index = startIndex, #SpatialLookup do
                        if SpatialLookup[index][2] ~= key then
                            break
                        end

                        local particleIndex = SpatialLookup[index][1]
                        local particle = Particles[particleIndex]

                        local dx = particle.predictedX - sampleParticle.predictedX
                        local dy = particle.predictedY - sampleParticle.predictedY

                        local distSqr = dx * dx + dy * dy

                        if distSqr < Settings.smoothingRadiusSqr then
                            sampleParticle.pointsInRadius[pointsIndex] = particle
                            pointsIndex = pointsIndex + 1
                        end
                    end
                end
            end
        end

        sampleParticle.pointsInRadiusAmount = pointsIndex - 1
        sampleParticle.chunkUpdateTimer = sampleParticle.chunkUpdateDelay
        sampleParticle.updateX = sampleParticle.predictedX
        sampleParticle.updateY = sampleParticle.predictedY
    end
end

function sim.viscositySmoothingFunction(distanceSqr, radiusSqr)
    if distanceSqr >= radiusSqr then
        return 0
    end

    local volume = math.pi * math.pow(radiusSqr, 4) * 0.25;
    local value = radiusSqr - distanceSqr
    return value * value * value / volume
end

function sim.calculateViscosityForce(particle, pointsInRadius, x, y, vx, vy)
    local forceX, forceY = 0, 0

    if pointsInRadius then
        for index, otherParticle in ipairs(pointsInRadius) do
            local dx = x - otherParticle.predictedX
            local dy = y - otherParticle.predictedY
            local distanceSqr = dx * dx + dy * dy

            local influence = sim.viscositySmoothingFunction(distanceSqr, Settings.smoothingRadiusSqr)
            forceX = forceX + influence * (otherParticle.velocityX - vx)
            forceY = forceY + influence * (otherParticle.velocityY - vy)
        end
    else
        for index = 1, particle.pointsInRadiusAmount do
            local otherParticle = particle.pointsInRadius[index]
            local dx = particle.predictedX - otherParticle.predictedX
            local dy = particle.predictedY - otherParticle.predictedY
            local distanceSqr = dx * dx + dy * dy

            local influence = sim.viscositySmoothingFunction(distanceSqr, Settings.smoothingRadiusSqr)
            forceX = forceX + influence * (otherParticle.velocityX - particle.velocityX)
            forceY = forceY + influence * (otherParticle.velocityY - particle.velocityY)
        end
    end

    return forceX * Settings.viscosity, forceY * Settings.viscosity
end

function sim.update(dt)
    local substepDt = dt / Settings.substeps
    for substep = 1, Settings.substeps do -- update particles
        for i, particle in ipairs(Particles) do
            particle.predictedX = particle.x + particle.velocityX * 0.0083333333
            particle.predictedY = particle.y + particle.velocityY * 0.0083333333
        end
        sim.updateSpatialLookup()

        for index, particle in ipairs(Particles) do
            sim.updatePointsInRadius(particle)
        end
        sim.updateParticleDensities()

        for i, particle in ipairs(Particles) do
            local pressureX, pressureY = calculatePressureForce(particle)
            local viscosityX, viscosityY = sim.calculateViscosityForce(particle)
            particle.velocityX = particle.velocityX -
                (pressureX - viscosityX) * substepDt * particle.mass * particle.inverseDensity
            particle.velocityY = particle.velocityY -
                (pressureY - viscosityY) * substepDt * particle.mass * particle.inverseDensity
        end
        for i, particle in ipairs(Particles) do
            particle:update(substepDt)
        end
    end
end

return sim
