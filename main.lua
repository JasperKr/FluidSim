function love.load()
    Settings = {
        gravity = 10,
        scale = 100, -- 100 pixels = 1 meter
        smoothingRadius = 50,
        targetDensity = 2,
        pressureMultiplier = 700,
        viscosity = 8.5,
        drawRadius = 15,
        mainCanvas = love.graphics.newCanvas(love.graphics.getWidth(), love.graphics.getHeight(), { format = "rgba32f" }),
        waterEffectShader = love.graphics.newShader("waterEffect.glsl"),
        substeps = 1,
        fluidMass = 3,
        debugDraw = true,
        particleRadius = 3,
        chunkUpdateDelay = 60, -- ticks
        -- if the particle moves more than 10 pixels, or the chunkUpdateDelay is reached, update the chunk the particle is in
        moveBoundry = 5,
        maxNeighbours = 100,
    }
    Settings.chunkSize = Settings.smoothingRadius
    Settings.inverseChunkSize = 1 / Settings.chunkSize
    Settings.gravity = Settings.gravity * Settings.scale
    Settings.pressureMultiplier = Settings.pressureMultiplier * Settings.scale
    Settings.targetDensity = Settings.targetDensity / Settings.scale
    Settings.smoothingRadiusSqr = Settings.smoothingRadius * Settings.smoothingRadius
    Settings.moveBoundrySqr = Settings.moveBoundry * Settings.moveBoundry
    Settings.sharedPressureMultiplier = Settings.pressureMultiplier * 0.5

    love.physics.setMeter(Settings.scale)
    Box2DWorld = love.physics.newWorld(0, 1.5 * Settings.scale, true)

    require("vectorMath")

    FluidSimulation = {
        Thread = {
            thread = love.thread.newThread("Threads/fluidThread.lua"),
            send = love.thread.newChannel(),
            receive = love.thread.newChannel(),
        }
    }


    require("vec")
    require("hull")

    sim = require("fluidSimulation")

    for x = -30, 30 do
        for y = -30, 30 do
            newParticle(x * 30 + love.graphics.getWidth() / 2 + love.math.random(),
                y * 20 + love.graphics.getHeight() / 2 + love.math.random(), 0.8, false)
        end
    end

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

    local height = -500

    local shape = love.physics.newRectangleShape(1000, 100)
    local body = love.physics.newBody(Box2DWorld, love.graphics.getWidth() / 2, 300 + height,
        "dynamic")
    local fixture = love.physics.newFixture(body, shape)

    table.insert(Hulls, newHull(body, fixture, shape))

    local shape1 = love.physics.newRectangleShape(50, 400)
    local body1 = love.physics.newBody(Box2DWorld, love.graphics.getWidth() / 2 - 500,
        300 - 200 + height,
        "dynamic")
    local fixture1 = love.physics.newFixture(body1, shape1)

    love.physics.newWeldJoint(body, body1, love.graphics.getWidth() / 2 - 500, 300 - 100)

    table.insert(Hulls, newHull(body1, fixture1, shape1))

    local shape2 = love.physics.newRectangleShape(50, 400)
    local body2 = love.physics.newBody(Box2DWorld, love.graphics.getWidth() / 2 + 500,
        300 - 200 + height,
        "dynamic")
    local fixture2 = love.physics.newFixture(body2, shape2)

    love.physics.newWeldJoint(body, body2, love.graphics.getWidth() / 2 + 500, 300 - 100 + height)

    table.insert(Hulls, newHull(body2, fixture2, shape2))

    local shape4 = love.physics.newRectangleShape(1000, 100)
    local body4 = love.physics.newBody(Box2DWorld, love.graphics.getWidth() / 2, -100 + height,
        "dynamic")
    local fixture4 = love.physics.newFixture(body4, shape4)

    love.physics.newWeldJoint(body1, body4, love.graphics.getWidth() / 2 - 500, -50 + height)
    love.physics.newWeldJoint(body2, body4, love.graphics.getWidth() / 2 + 500, -50 + height)

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

    Timer = {
        timings = {}
    }

    print("start thread")
    FluidSimulation.Thread.thread:start({ copyForThreadSend(Settings), FluidSimulation.Thread.send,
        FluidSimulation.Thread.receive, love.graphics.getWidth(), love.graphics.getHeight() })

    Width, Height = love.graphics.getDimensions()
end

function copyForThreadSend(x, t)
    local newTable = t or {}
    for k, v in pairs(x) do
        if type(v) == "table" then
            newTable[k] = copyForThreadSend(v)
        elseif type(v) == "number" or type(v) == "boolean" or type(v) == "string" then
            newTable[k] = v
        end
    end

    return newTable
end

local function addTiming(name)
    if Timer.lastTime then
        table.insert(Timer.timings, {
            name .. ": " .. (love.timer.getTime() - Timer.lastTime), love.timer.getTime() - Timer.lastTime
        })
    end
    Timer.lastTime = love.timer.getTime()
end

local function updatePointers(data)
    assert(data.type == "dataPointers")

    sim.startIndicesData = data.indices
    sim.spatialLookupData = data.lookup

    sim.startIndices = ffi.cast("int32_t*", sim.startIndicesData:getFFIPointer())
    sim.spatialLookup = ffi.cast("spatialLookupEntry*", sim.spatialLookupData:getFFIPointer())

    sim.startIndicesLength = data.indicesLength
    sim.spatialLookupLength = data.lookupLength

    sim.startIndicesBufferSize = data.indicesMaxSize
    sim.spatialLookupBufferSize = data.lookupMaxSize
end

function love.update(dt)
    dt = math.min(dt, 1 / 60)
    addTiming("start")
    Box2DWorld:update(dt)
    addTiming("box2d")

    local msg = FluidSimulation.Thread.receive:pop()
    while msg do
        if msg.type == "dataPointers" then
            updatePointers(msg)
        elseif msg.type == "arrayLengths" then
            sim.startIndicesLength = msg.indicesLength
            sim.spatialLookupLength = msg.lookupLength
        else
            print("Unknown message type: " .. msg.type)
        end

        msg = FluidSimulation.Thread.receive:pop()
    end

    sim.update(dt, false, love.graphics.getWidth(), love.graphics.getHeight())
    addTiming("fluid")

    do -- update hulls
        for i, hull in ipairs(Hulls) do
            hull:update(dt)
        end
    end
    addTiming("hulls")

    do -- mouse interactions
        if love.mouse.isDown(1, 2) then
            for i, particle in ipairs(Particles) do
                local force = updateMouseForces(500, love.mouse.isDown(2) and -5000 or 5000, particle)
                particle.CData.velocityX = particle.CData.velocityX + force.x * dt
                particle.CData.velocityY = particle.CData.velocityY + force.y * dt
            end
        end
    end
end

function love.draw()
    do -- draw fluid
        addTiming("start draw")
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.setCanvas(Settings.mainCanvas)
        love.graphics.clear(0, 0, 0, 1)
        love.graphics.setBlendMode("add", "premultiplied")
        for i, particle in ipairs(Particles) do
            particle:draw(i)
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
        addTiming("draw fluid")
    end

    do -- draw hulls
        for i, hull in ipairs(Hulls) do
            hull:draw()
        end
    end
    addTiming("draw hulls")

    love.graphics.setColor(1, 1, 1)

    local total = 0
    for i, timing in ipairs(Timer.timings) do
        love.graphics.print(timing[1], 0, 20 * i + 20)
        total = total + timing[2]
    end
    love.graphics.print("Total: " .. total, 0, 20 * (#Timer.timings + 1) + 20)
    love.graphics.print("FPS: " .. 1 / total, 0, 20 * (#Timer.timings + 2) + 20)


    Timer.timings = {}
    Timer.lastTime = nil


    love.graphics.setColor(1, 1, 1)
    --love.graphics.print(calculateDensity(love.mouse.getPosition()))
    love.graphics.print("FPS" .. love.timer.getFPS(), 0, 20)
end

function updateMouseForces(radius, strength, particle)
    local mousePos = vec2(love.mouse.getPosition())

    local force = vec2()
    local offset = mousePos - vec2(particle.CData.x, particle.CData.y)

    local distSqr = offset:lengthSqr()

    if distSqr < radius * radius then
        local dist = math.sqrt(distSqr)
        local dir = dist <= 0.0001 and vec2() or offset / dist

        local centerT = 1 - dist / radius

        force = (dir * strength - vec2(particle.CData.velocityX, particle.CData.velocityY)) * centerT
    end

    return force
end
