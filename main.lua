function love.load()
    Settings = {
        gravity = 10,
        scale = 100, -- 100 pixels = 1 meter
        smoothingRadius = 50,
        targetDensity = 1.5,
        pressureMultiplier = 3000,
        viscosity = 11,
        drawRadius = 10,
        mainCanvas = love.graphics.newCanvas(love.graphics.getWidth(), love.graphics.getHeight(), { format = "rgba32f" }),
        waterEffectShader = love.graphics.newShader("waterEffect.glsl"),
        substeps = 1,
        fluidMass = 0.005,
        debugDraw = false,
        particleRadius = 5
    }
    Settings.chunkSize = Settings.smoothingRadius
    Settings.inverseChunkSize = 1 / Settings.chunkSize
    Settings.gravity = Settings.gravity * Settings.scale
    Settings.pressureMultiplier = Settings.pressureMultiplier * Settings.scale
    Settings.targetDensity = Settings.targetDensity / Settings.scale

    love.physics.setMeter(Settings.scale)
    Box2DWorld = love.physics.newWorld(0, 9.81 * Settings.scale, true)

    require("tables")
    require("quadtree")
    require("particle")
    require("vec")
    require("hull")

    Particles = {}

    for x = -40, 40 do
        for y = -30, 30 do
            newParticle(x * 12 + love.graphics.getWidth() / 2 + love.math.random(),
                y * 12 + love.graphics.getHeight() / 2 + love.math.random(), 0.8)
        end
    end

    SpatialLookup = {}
    StartIndices = {}

    local gradientImageData = love.image.newImageData(100, 100)

    gradientImageData:mapPixel(function(x, y)
        local dx = x - 50
        local dy = y - 50

        local dist = math.sqrt(dx * dx + dy * dy)

        return 1 - dist / 50, 1 - dist / 50, 1 - dist / 50, 1
    end)

    Settings.gradientImage = love.graphics.newImage(gradientImageData)

    ---@type {[1]: hull}
    Hulls = {}

    local shape = love.physics.newRectangleShape(1000, 100)
    local body = love.physics.newBody(Box2DWorld, love.graphics.getWidth() / 2, 300,
        "dynamic")
    local fixture = love.physics.newFixture(body, shape)

    table.insert(Hulls, newHull(body, fixture, shape))

    local shape1 = love.physics.newRectangleShape(50, 400)
    local body1 = love.physics.newBody(Box2DWorld, love.graphics.getWidth() / 2 - 500,
        300 - 200,
        "dynamic")
    local fixture1 = love.physics.newFixture(body1, shape1)

    love.physics.newWeldJoint(body, body1, love.graphics.getWidth() / 2 - 500, 300 - 100)

    table.insert(Hulls, newHull(body1, fixture1, shape1))

    local shape2 = love.physics.newRectangleShape(50, 400)
    local body2 = love.physics.newBody(Box2DWorld, love.graphics.getWidth() / 2 + 500,
        300 - 200,
        "dynamic")
    local fixture2 = love.physics.newFixture(body2, shape2)

    love.physics.newWeldJoint(body, body2, love.graphics.getWidth() / 2 + 500, 300 - 100)

    table.insert(Hulls, newHull(body2, fixture2, shape2))

    local shape4 = love.physics.newRectangleShape(1000, 100)
    local body4 = love.physics.newBody(Box2DWorld, love.graphics.getWidth() / 2, -100,
        "dynamic")
    local fixture4 = love.physics.newFixture(body4, shape4)

    love.physics.newWeldJoint(body1, body4, love.graphics.getWidth() / 2 - 500, -50)
    love.physics.newWeldJoint(body2, body4, love.graphics.getWidth() / 2 + 500, -50)

    table.insert(Hulls, newHull(body4, fixture4, shape4))

    do -- create a floor and walls
        local body = love.physics.newBody(Box2DWorld, 0, love.graphics.getHeight(), "static")
        local shape = love.physics.newEdgeShape(0, 0, love.graphics.getWidth(), 0)
        local fixture = love.physics.newFixture(body, shape)

        local body = love.physics.newBody(Box2DWorld, 0, 0, "static")
        local shape = love.physics.newEdgeShape(0, 0, 0, love.graphics.getHeight())
        local fixture = love.physics.newFixture(body, shape)

        local body = love.physics.newBody(Box2DWorld, love.graphics.getWidth(), 0, "static")
        local shape = love.physics.newEdgeShape(0, 0, 0, love.graphics.getHeight())
        local fixture = love.physics.newFixture(body, shape)
    end
end

function love.update(dt)
    dt = math.min(dt, 1 / 60)
    Box2DWorld:update(dt)

    local substepDt = dt / Settings.substeps
    love.graphics.setCanvas(Settings.mainCanvas)
    love.graphics.clear(0, 0, 0, 1)
    for substep = 1, Settings.substeps do -- update particles
        for i, particle in ipairs(Particles) do
            particle.predictedX = particle.x + particle.velocityX * 0.0083333333
            particle.predictedY = particle.y + particle.velocityY * 0.0083333333
        end
        updateSpatialLookup()
        updateParticleDensities()

        for i, particle in ipairs(Particles) do
            local pressureX, pressureY = calculatePressureForce(particle)
            local viscosityX, viscosityY = calculateViscosityForce(particle)
            particle.velocityX = particle.velocityX -
                (pressureX - viscosityX * Settings.viscosity) * substepDt * particle.mass * particle.inverseDensity
            particle.velocityY = particle.velocityY -
                (pressureY - viscosityY * Settings.viscosity) * substepDt * particle.mass * particle.inverseDensity
        end
        for i, particle in ipairs(Particles) do
            particle:update(substepDt)
        end
    end
    love.graphics.setCanvas()

    do -- update hulls
        for i, hull in ipairs(Hulls) do
            hull:update(dt)
        end
    end

    do -- mouse interactions
        if love.mouse.isDown(1, 2) then
            for i, particle in ipairs(Particles) do
                local force = updateMouseForces(500, love.mouse.isDown(2) and -5000 or 5000, particle)
                particle.velocityX = particle.velocityX + force.x * dt
                particle.velocityY = particle.velocityY + force.y * dt
            end
        end
    end
end

function love.draw()
    do -- draw fluid
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.setCanvas(Settings.mainCanvas)
        love.graphics.setBlendMode("add", "premultiplied")
        for i, particle in ipairs(Particles) do
            particle:draw()
        end
        love.graphics.setBlendMode("alpha")
        love.graphics.setCanvas()
        love.graphics.setColor(1, 1, 1, 1)
        if not Settings.debugDraw then
            love.graphics.setShader(Settings.waterEffectShader)
        end
        love.graphics.draw(Settings.mainCanvas)
        if not Settings.debugDraw then
            love.graphics.setShader()
        end
    end

    do -- draw hulls
        for i, hull in ipairs(Hulls) do
            hull:draw()
        end
    end


    love.graphics.setColor(1, 1, 1)
    love.graphics.print(calculateDensity(love.mouse.getPosition()))
    love.graphics.print("FPS" .. love.timer.getFPS(), 0, 20)
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
    local volume = (math.pi * math.pow(radius, 4)) * 0.1666666667;
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

function calculateDensity(x, y, pointsInRadius)
    local density = 0

    local particles
    if type(x) == "number" then
        particles = pointsInRadius or getPointsInRadius(x, y)
    else
        particles = x.pointsInRadius
        y = x.predictedY
        x = x.predictedX
    end
    for index, particle in ipairs(particles) do
        local distance = length(x - particle.x, y - particle.y)
        local influence = smoothingFunction(Settings.smoothingRadius, distance)

        density = density + particle.mass * influence
    end

    return density
end

function calculatePressureForce(sampleParticle, pointsInRadius, x, y, density)
    local pressureX, pressureY = 0, 0

    for loopIndex, particle in ipairs(pointsInRadius or sampleParticle.pointsInRadius) do
        if particle == sampleParticle then
            goto continue
        end
        local dx = x or sampleParticle.predictedX - particle.predictedX
        local dy = y or sampleParticle.predictedY - particle.predictedY

        local distance = length(dx, dy)

        local dirX, dirY
        if distance > 0 then
            dirX, dirY = dx / distance, dy / distance
        else
            dirX, dirY = 0, 0
        end

        local influence = smoothingFunctionDerivative(Settings.smoothingRadius, distance)

        local sharedPressure = calculateSharedPressure(particle.density, density or sampleParticle.density)
        pressureX = pressureX -
            sharedPressure * dirX * influence * Settings.scale
        pressureY = pressureY -
            sharedPressure * dirY * influence * Settings.scale
        ::continue::
    end

    return pressureX, pressureY
end

function updateParticleDensities()
    for index, particle in ipairs(Particles) do
        particle.density = calculateDensity(particle)
        if particle.density <= 0.000001 then
            particle.inverseDensity = 1000000
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

    local volume = math.pi * math.pow(radius, 8) * 0.25;
    local value = radius * radius - distance * distance
    return value * value * value / volume
end

function calculateViscosityForce(particle, pointsInRadius, x, y, vx, vy)
    local forceX, forceY = 0, 0
    x, y = x or particle.predictedX, y or particle.predictedY

    for index, otherParticle in ipairs(pointsInRadius or particle.pointsInRadius) do
        if otherParticle == particle then
            --goto continue
        end

        local distance = length(x - otherParticle.predictedX, y - otherParticle.predictedY)

        local influence = viscositySmoothingFunction(distance, Settings.smoothingRadius)
        forceX = forceX + influence * (otherParticle.velocityX - (vx or particle.velocityX))
        forceY = forceY + influence * (otherParticle.velocityY - (vy or particle.velocityY))

        ::continue::
    end

    return forceX, forceY
end

function dot(x1, y1, x2, y2)
    return x1 * x2 + y1 * y2
end
