Settings, receive, send, width, height = unpack(...)

require("vectorMath")
require("particle")
sim = require("fluidSimulation")
require("vec")
require("love.timer")
require("love.math")

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

local threads = {
    {
        name = "lookupThread",
        thread = love.thread.newThread("Threads/lookupThread.lua"),
        send = love.thread.newChannel(),
        receive = love.thread.newChannel(),
    }
}

-- local indices, lookup = sim.startIndices, sim.spatialLookup

-- local indicesPtr = ffi.new("int32_t*", indices)
-- local lookupPtr = ffi.new("spatialLookupEntry*", lookup)

-- local indicesPtrNum = tonumber(ffi.cast("uint64_t", indicesPtr))
-- local lookupPtrNum = tonumber(ffi.cast("uint64_t", lookupPtr))


--threads[1].thread:start({ copyForThreadSend(Settings), threads[1].send,
--    threads[1].receive, width, height, indicesPtrNum, lookupPtrNum })

Particles = {}

local targetFramerate = 1 / 60
local simFrameRate = 1 / 120

while true do
    local startTime = love.timer.getTime()

    local msg = receive:pop()

    while msg do
        if msg.type == "addParticle" then
            newParticle(msg.data[1], msg.data[2], msg.data[3], true, msg.pointer)
        end

        -- forward message to other threads
        for _, thread in ipairs(threads) do
            thread.send:push(msg)
        end

        msg = receive:pop()
    end

    sim.update(simFrameRate, true, width, height)

    local endTime = love.timer.getTime()

    local sleepTime = targetFramerate - (endTime - startTime)

    love.timer.sleep(sleepTime)
end
