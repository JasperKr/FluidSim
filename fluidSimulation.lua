local sim = {}

if not ffi then
    ffi = require("ffi")
end

local sortFunction = require("quickSort")

require("tables")

Particles = newIndexedTable()

require("particle")

sim.spatialLookupBufferSize = 10000
sim.startIndicesBufferSize = 10000

sim.spatialLookupBufferIncrement = 2
sim.startIndicesBufferIncrement = 2

sim.spatialLookupLength = 0
sim.startIndicesLength = 0

ffi.cdef [[
    typedef struct {
        int32_t index;
        int32_t key;
    } spatialLookupEntry;
]]

sim.spatialLookupData = love.data.newByteData(ffi.sizeof("spatialLookupEntry") * sim.spatialLookupBufferSize)

local spatialSetter = ffi.new("spatialLookupEntry", -1, -1)

local ptr = ffi.cast("spatialLookupEntry*", sim.spatialLookupData:getFFIPointer())

for i = 0, sim.spatialLookupBufferSize - 1 do
    ptr[i] = spatialSetter
end

sim.spatialLookup = ptr

sim.startIndicesData = love.data.newByteData(ffi.sizeof("int32_t") * sim.startIndicesBufferSize)

local indexSetter = ffi.new("int32_t", -1)

ptr = ffi.cast("int32_t*", sim.startIndicesData:getFFIPointer())

for i = 0, sim.startIndicesBufferSize - 1 do
    ptr[i] = indexSetter
end

sim.startIndices = ptr

local function setSpatialLookupValue(index, key, change)
    if tonumber(sim.spatialLookup[index].key) == -1 then
        sim.spatialLookupLength = sim.spatialLookupLength + 1
        if not change then
            sim.spatialLookup[index].index = -2
            sim.spatialLookup[index].key = -2
        end
    end

    -- -2 because we can't index the last element the next time
    if sim.spatialLookupLength >= sim.spatialLookupBufferSize - 2 or index >= sim.spatialLookupBufferSize - 2 then
        sim.spatialLookupBufferSize = sim.spatialLookupBufferSize * sim.spatialLookupBufferIncrement
        local newData = love.data.newByteData(ffi.sizeof("spatialLookupEntry") * sim.spatialLookupBufferSize)
        local new = ffi.cast("spatialLookupEntry*", newData:getFFIPointer())

        for i = 0, sim.spatialLookupBufferSize - 1 do
            new[i].index = -1
            new[i].key = -1
        end

        ffi.copy(new, sim.spatialLookup, sim.spatialLookupLength * ffi.sizeof("spatialLookupEntry"))

        sim.spatialLookup = new
        sim.spatialLookupData = newData
        sendDataReferences()
    end

    if change then
        sim.spatialLookup[index].index = index
        sim.spatialLookup[index].key = key
    end
end

local function setStartIndicesValue(index, key, change)
    if sim.startIndices[index] == -1 then
        sim.startIndicesLength = sim.startIndicesLength + 1
        if not change then
            sim.startIndices[index] = -2
        end
    end

    -- -2 because we can't index the last element the next time
    if sim.startIndicesLength >= sim.startIndicesBufferSize - 2 or index >= sim.startIndicesBufferSize - 2 then
        sim.startIndicesBufferSize = sim.startIndicesBufferSize * sim.startIndicesBufferIncrement
        local newData = love.data.newByteData(ffi.sizeof("int32_t") * sim.startIndicesBufferSize)
        local new = ffi.cast("int32_t*", newData:getFFIPointer())

        for i = 0, sim.startIndicesBufferSize - 1 do
            new[i] = -1
        end

        ffi.copy(new, sim.startIndices, sim.startIndicesLength * ffi.sizeof("int32_t"))

        sim.startIndicesData = newData
        sim.startIndices = new
        sendDataReferences()
    end

    if change then
        sim.startIndices[index] = key
    end
end

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

        for index = 1, sampleParticle.CData.neighboursAmount do
            local otherParticleIndex = sampleParticle.CData.neighbours[index - 1]

            local particle = Particles[otherParticleIndex]

            local distance = length(sampleParticle.CData.predictedX - particle.CData.x,
                sampleParticle.CData.predictedY - particle.CData.y)
            local influence = sim.smoothingFunction(Settings.smoothingRadius, distance)

            density = density + particle.mass * influence
        end
    end

    return density
end

function calculatePressureForce(sampleParticle, pointsInRadius, x, y, density)
    local pressureX, pressureY = 0, 0

    if sampleParticle then
        for loopIndex = 1, sampleParticle.CData.neighboursAmount do
            local otherParticleIndex = sampleParticle.CData.neighbours[loopIndex - 1]

            local particle = Particles[otherParticleIndex]

            if particle == sampleParticle or not particle then
                goto continue
            end

            local dx = sampleParticle.CData.predictedX - particle.CData.predictedX
            local dy = sampleParticle.CData.predictedY - particle.CData.predictedY

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
            local dx = x - particle.CData.predictedX
            local dy = y - particle.CData.predictedY

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
    return a.key < b.key
end

local swapFunction = function(array, i, j)
    local key, index = array[i].key, array[i].index
    array[i].key, array[i].index = array[j].key, array[j].index
    array[j].key, array[j].index = key, index
end

local function sortSpatialLookup()
    sortFunction(sim.spatialLookup, 1, sim.spatialLookupLength, tableSort, swapFunction)
end

function sim.prepareSpatialLookup()
    for index, particle in ipairs(Particles) do
        local chunkX, chunkY = sim.positionToChunkCoord(particle.predictedX, particle.predictedY)
        local key = sim.positionToIndex(chunkX, chunkY)
        setSpatialLookupValue(index, key, false)
        setStartIndicesValue(index, math.huge, false)
    end
end

function sim.updateSpatialLookup()
    for index, particle in ipairs(Particles) do
        local chunkX, chunkY = sim.positionToChunkCoord(particle.predictedX, particle.predictedY)
        local key = sim.positionToIndex(chunkX, chunkY)
        setSpatialLookupValue(index, key, true)
        setStartIndicesValue(index, math.huge, true)
    end

    sortSpatialLookup()

    for index, particle in ipairs(Particles) do
        local key = tonumber(sim.spatialLookup[index].key)

        local previousKey = index == 1 and math.huge or sim.spatialLookup[index - 1].key

        if key and key == key and key ~= previousKey then
            setStartIndicesValue(key, index, true)
        end
    end
end

function sim.getPointsInRadius(x, y)
    local centerX, centerY = sim.positionToChunkCoord(x, y)

    local points = {}

    for chunkX = centerX - 1, centerX + 1 do
        for chunkY = centerY - 1, centerY + 1 do
            local key = sim.positionToIndex(chunkX, chunkY)
            local startIndex = tonumber(sim.startIndices[key])
            if startIndex and startIndex ~= -1 and startIndex ~= -2 then
                for index = startIndex, sim.spatialLookupLength do
                    if tonumber(sim.spatialLookup[index].key) ~= key then
                        break
                    end

                    local particleIndex = tonumber(sim.spatialLookup[index].index)
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

    local pdx = sampleParticle.updateX - sampleParticle.CData.predictedX
    local pdy = sampleParticle.updateY - sampleParticle.CData.predictedY

    if sampleParticle.chunkUpdateTimer <= 0 or pdx * pdx + pdy * pdy > Settings.moveBoundrySqr then
        local centerX, centerY = sim.positionToChunkCoord(sampleParticle.CData.predictedX,
            sampleParticle.CData.predictedY)

        local pointsIndex = 0

        for chunkX = centerX - 1, centerX + 1 do
            for chunkY = centerY - 1, centerY + 1 do
                local key = sim.positionToIndex(chunkX, chunkY)
                local startIndex = tonumber(sim.startIndices[key])
                if not startIndex or startIndex == -1 or startIndex == -2 then
                    goto continue
                end

                if startIndex == -2147483648 then
                    startIndex = math.huge
                end

                for index = startIndex, sim.spatialLookupLength do
                    if tonumber(sim.spatialLookup[index].key) ~= key then
                        break
                    end

                    local particleIndex = tonumber(sim.spatialLookup[index].index)
                    local particle = Particles[particleIndex]

                    local dx = particle.CData.predictedX - sampleParticle.CData.predictedX
                    local dy = particle.CData.predictedY - sampleParticle.CData.predictedY

                    if dx * dx + dy * dy < Settings.smoothingRadiusSqr and pointsIndex <= Settings.maxNeighbours then
                        sampleParticle.CData.neighbours[pointsIndex] = particleIndex
                        pointsIndex = pointsIndex + 1
                    end
                end

                ::continue::
            end
        end

        sampleParticle.CData.neighboursAmount = pointsIndex
        sampleParticle.chunkUpdateTimer = sampleParticle.chunkUpdateDelay
        sampleParticle.updateX = sampleParticle.CData.predictedX
        sampleParticle.updateY = sampleParticle.CData.predictedY
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
        for index = 1, particle.CData.neighboursAmount do
            local otherParticleIndex = particle.CData.neighbours[index - 1]

            local otherParticle = Particles[otherParticleIndex]

            if not otherParticle then
                goto continue
            end

            local dx = particle.CData.predictedX - otherParticle.CData.predictedX
            local dy = particle.CData.predictedY - otherParticle.CData.predictedY
            local distanceSqr = dx * dx + dy * dy

            local influence = sim.viscositySmoothingFunction(distanceSqr, Settings.smoothingRadiusSqr)
            forceX = forceX + influence * (otherParticle.CData.velocityX - particle.CData.velocityX)
            forceY = forceY + influence * (otherParticle.CData.velocityY - particle.CData.velocityY)

            ::continue::
        end
    end

    return forceX * Settings.viscosity, forceY * Settings.viscosity
end

sim.coroutines = {
    updateDensities = coroutine.create(function()
        while true do
            sim.updateParticleDensities()
            coroutine.yield()
        end
    end),
    updateLookup = coroutine.create(function()
        while true do
            sim.updateSpatialLookup()
            coroutine.yield()
        end
    end),
    updateLookupRadius = coroutine.create(function()
        while true do
            for index, particle in ipairs(Particles) do
                sim.updatePointsInRadius(particle)
            end
            coroutine.yield()
        end
    end),

    updatePressureForces = coroutine.create(function(dt)
        while true do
            for i, particle in ipairs(Particles) do
                local pressureX, pressureY = calculatePressureForce(particle)
                local viscosityX, viscosityY = sim.calculateViscosityForce(particle)
                particle.CData.velocityX = particle.CData.velocityX -
                    (pressureX - viscosityX) * dt * particle.mass * particle.inverseDensity
                particle.CData.velocityY = particle.CData.velocityY -
                    (pressureY - viscosityY) * dt * particle.mass * particle.inverseDensity
            end
            coroutine.yield()
        end
    end),
}



function sim.update(dt, isThread, width, height, threads)
    if not isThread then
        FluidSimulation.Thread.send:push({ type = "update" })
    end
    if isThread then
        for i, particle in ipairs(Particles) do
            particle.CData.predictedX = particle.CData.x + particle.CData.velocityX * 0.0083333333
            particle.CData.predictedY = particle.CData.y + particle.CData.velocityY * 0.0083333333
        end

        -- wait for the partitioning to be done
        threads[1].doneCheck:demand()
        -- we can't have the partitioning and the lookup running at the same time

        for index, particle in ipairs(Particles) do
            sim.updatePointsInRadius(particle)
        end

        ran, err = coroutine.resume(sim.coroutines.updateDensities) -- runs
        assert(ran, err)

        ran, err = coroutine.resume(sim.coroutines.updatePressureForces, dt)
        assert(ran, err)

        threads[1].readyToStartCheck:push(true) -- tell the partitioning thread to start
    end
    for i, particle in ipairs(Particles) do
        particle:update(dt, isThread, width, height)
    end
end

return sim
