Settings, receive, send, width, height, indicesPtrNum, lookupPtrNum = unpack(...)

isLookupThread = true
require("vectorMath")
require("particle")
sim = require("fluidSimulation")
require("vec")
require("love.timer")
require("love.math")


local indicesCastPtr = ffi.cast("void*", indicesPtrNum)
local lookupCastPtr = ffi.cast("void*", lookupPtrNum)

local indicesPtr = ffi.cast("int32_t*", indicesCastPtr)
local lookupPtr = ffi.cast("spatialLookupEntry*", lookupCastPtr)

sim.startIndices = indicesPtr
sim.spatialLookup = lookupPtr

Particles = {}

local targetFramerate = 1 / 60
local simFrameRate = 1 / 120

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

    local succes, err = coroutine.resume(sim.coroutines.updateLookup)
    if not succes then
        error(err)
    end

    local endTime = love.timer.getTime()

    local sleepTime = targetFramerate - (endTime - startTime)

    love.timer.sleep(sleepTime)
end
