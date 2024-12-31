Settings, receive, send, width, height, canStart, done = unpack(...)

isLookupThread = true
require("vectorMath")
sim = require("fluidSimulation")
require("vec")
require("love.timer")
require("love.math")

function sendDataReferences()
    send:push({
        type = "dataPointers",
        indices = sim.startIndicesData,
        lookup = sim.spatialLookupData,
        indicesLength = sim.startIndicesLength,
        lookupLength = sim.spatialLookupLength,
        indicesMaxSize = sim.startIndicesBufferSize,
        lookupMaxSize = sim.spatialLookupBufferSize
    })
end

local lastIndicesLength
local lastLookupLength

function updateArrayLengths()
    if lastIndicesLength == sim.startIndicesLength and lastLookupLength == sim.spatialLookupLength then
        return
    end

    send:push({
        type = "arrayLengths",
        indicesLength = sim.startIndicesLength,
        lookupLength = sim.spatialLookupLength
    })

    lastIndicesLength = sim.startIndicesLength
    lastLookupLength = sim.spatialLookupLength
end

sendDataReferences()

local targetFramerate = 1 / 120

function handleMessages(msg)
    msg = msg ~= nil and msg or receive:pop() -- so we can use :demand if we want

    while msg do
        if msg.type == "addParticle" then
            newParticle(msg.data[1], msg.data[2], msg.data[3], true, msg.data[4])
        end

        msg = receive:pop()
    end
end

while true do
    local startTime = love.timer.getTime()

    handleMessages()

    for i, particle in ipairs(Particles) do
        particle.x = particle.CData.x
        particle.y = particle.CData.y

        particle.velocityX = particle.CData.velocityX
        particle.velocityY = particle.CData.velocityY

        particle.predictedX = particle.x + particle.velocityX * 0.0083333333
        particle.predictedY = particle.y + particle.velocityY * 0.0083333333
    end

    sim.prepareSpatialLookup()

    if canStart:pop() then
        sim.updateSpatialLookup()

        done:push(true)
    end

    updateArrayLengths()

    local endTime = love.timer.getTime()

    local sleepTime = targetFramerate - (endTime - startTime)

    love.timer.sleep(sleepTime)
end
