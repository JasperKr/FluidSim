Settings, receive, send, width, height, canStart, done = unpack(...)

isLookupThread = true
require("vectorMath")

sim = require("fluidSimulation")
require("vec")
require("love.timer")
require("love.math")



local targetFramerate = 1 / 120

local function updatePointers(data)
    assert(data.type == "dataPointers")
    local indicesPtrNum = data.indices
    local lookupPtrNum = data.lookup

    local indicesCastPtr = ffi.cast("void*", indicesPtrNum)
    local lookupCastPtr = ffi.cast("void*", lookupPtrNum)

    local indicesPtr = ffi.cast("int32_t*", indicesCastPtr)
    local lookupPtr = ffi.cast("spatialLookupEntry*", lookupCastPtr)

    sim.startIndices = indicesPtr
    sim.spatialLookup = lookupPtr

    sim.startIndicesLength = data.indicesLength
    sim.spatialLookupLength = data.lookupLength

    sim.startIndicesBufferSize = data.indicesMaxSize
    sim.spatialLookupBufferSize = data.lookupMaxSize
end

function handleMessages(msg)
    msg = msg ~= nil and msg or receive:pop() -- so we can use :demand if we want
    local typesHandled = {}

    while msg do
        if msg.type == "addParticle" then
            newParticle(msg.data[1], msg.data[2], msg.data[3], true, msg.pointer)
        elseif msg.type == "dataPointers" then
            updatePointers(msg)
        elseif msg.type == "arrayLengths" then
            sim.startIndicesLength = msg.indicesLength
            sim.spatialLookupLength = msg.lookupLength
        end

        table.insert(typesHandled, msg.type)

        msg = receive:pop()
    end

    return typesHandled
end

while true do
    local startTime = love.timer.getTime()

    handleMessages()

    if canStart:demand() then
        -- main loop

        for i, particle in ipairs(Particles) do
            particle.x = particle.Creference.x
            particle.y = particle.Creference.y

            particle.velocityX = particle.Creference.velocityX
            particle.velocityY = particle.Creference.velocityY

            particle.predictedX = particle.x + particle.velocityX * 0.0083333333
            particle.predictedY = particle.y + particle.velocityY * 0.0083333333
        end

        for index, particle in ipairs(Particles) do
            sim.updatePointsInRadius(particle)
        end

        done:push(true)
    end


    local endTime = love.timer.getTime()

    local sleepTime = targetFramerate - (endTime - startTime)

    love.timer.sleep(sleepTime)
end
