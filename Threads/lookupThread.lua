Settings, receive, send, width, height, canStart, done = unpack(...)

isLookupThread = true
require("vectorMath")
sim = require("fluidSimulation")
require("vec")
require("love.timer")
require("love.math")

function createAndSentLookupPointers()
    local indices, lookup = sim.startIndices, sim.spatialLookup

    local indicesPtr = ffi.new("int32_t*", indices)
    local lookupPtr = ffi.new("spatialLookupEntry*", lookup)

    local indicesPtrNum = tonumber(ffi.cast("uint64_t", indicesPtr))
    local lookupPtrNum = tonumber(ffi.cast("uint64_t", lookupPtr))

    --[[
        this thread is responsible for updating the spatial lookup table,
        but, the spatial lookup table size can change so we need to recreate it sometimes.
        so we store the pointer to the lookup table in an ffi int64_t and pass it to the other threads when we recreate it.
    ]]

    send:push({
        type = "dataPointers",
        indices = indicesPtrNum,
        lookup = lookupPtrNum,
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

createAndSentLookupPointers()


local targetFramerate = 1 / 120

function handleMessages(msg)
    msg = msg ~= nil and msg or receive:pop() -- so we can use :demand if we want
    local typesHandled = {}

    while msg do
        if msg.type == "addParticle" then
            newParticle(msg.data[1], msg.data[2], msg.data[3], true, msg.pointer)
        end

        table.insert(typesHandled, msg.type)

        msg = receive:pop()
    end

    return typesHandled
end

while true do
    local startTime = love.timer.getTime()

    handleMessages()

    for i, particle in ipairs(Particles) do
        particle.x = particle.Creference.x
        particle.y = particle.Creference.y

        particle.velocityX = particle.Creference.velocityX
        particle.velocityY = particle.Creference.velocityY

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
