Settings, receive, send, width, height = unpack(...)

Width, Height = width, height

require("vectorMath")

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
        readyToStartCheck = love.thread.newChannel(),
        doneCheck = love.thread.newChannel(),
    }
}

local threadSafeSettings = copyForThreadSend(Settings)

threads[1].thread:start({ threadSafeSettings, threads[1].send,
    threads[1].receive, width, height, threads[1].readyToStartCheck, threads[1].doneCheck })

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

local pointers = threads[1].receive:demand()
updatePointers(pointers)
send:push(pointers)

local targetFramerate = 1 / 60
local simFrameRate = 1 / 120

local startedOtherThreads = false

while true do
    local startTime = love.timer.getTime()

    local msg = receive:pop()
    local canContinue = false

    while msg or not canContinue do
        if not msg and not canContinue then -- if we're waiting for the go ahead from other threads but don't have a message, demand one
            msg = receive:demand()
        end

        if msg.type == "addParticle" then
            newParticle(msg.data[1], msg.data[2], msg.data[3], true, msg.data[4])
        elseif msg.type == "update" then
            canContinue = true
        end

        -- forward message to other threads
        for _, thread in ipairs(threads) do
            thread.send:push(msg)
        end

        msg = receive:pop()
    end

    for _, thread in ipairs(threads) do
        local msg = thread.receive:pop()

        while msg do
            if msg.type == "dataPointers" then
                updatePointers(msg)
            elseif msg.type == "arrayLengths" then
                sim.startIndicesLength = msg.indicesLength
                sim.spatialLookupLength = msg.lookupLength
            end
            send:push(msg)

            msg = thread.receive:pop()
        end
    end

    if sim.spatialLookupLength <= sim.spatialLookupBufferSize and
        sim.startIndicesLength <= sim.startIndicesBufferSize and startedOtherThreads then
        sim.update(simFrameRate, true, width, height, threads)
    end

    if not startedOtherThreads then
        startedOtherThreads = true
        for _, thread in ipairs(threads) do
            thread.readyToStartCheck:push(true)
        end
    end

    local endTime = love.timer.getTime()

    local sleepTime = targetFramerate - (endTime - startTime)

    love.timer.sleep(sleepTime)
end
