Settings, receive, send, width, height = unpack(...)

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
    },
    {
        name = "neighboursThread",
        thread = love.thread.newThread("Threads/neighboursThread.lua"),
        send = love.thread.newChannel(),
        receive = love.thread.newChannel(),
        readyToStartCheck = love.thread.newChannel(),
        doneCheck = love.thread.newChannel(),
    }
}

local threadSafeSettings = copyForThreadSend(Settings)

threads[1].thread:start({ threadSafeSettings, threads[1].send,
    threads[1].receive, width, height, threads[1].readyToStartCheck, threads[1].doneCheck })
threads[2].thread:start({ threadSafeSettings, threads[2].send,
    threads[2].receive, width, height, threads[2].readyToStartCheck, threads[2].doneCheck })

local function updatePointers(data)
    assert(data.type == "dataPointers")

    threads[2].send:push(data)

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

updatePointers(threads[1].receive:demand())

print("lookup thread started")



local targetFramerate = 1 / 60
local simFrameRate = 1 / 120

local startedOtherThreads = false

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

    for _, thread in ipairs(threads) do
        local msg = thread.receive:pop()

        while msg do
            if msg.type == "dataPointers" then
                updatePointers(msg)
            elseif msg.type == "arrayLengths" then
                sim.startIndicesLength = msg.indicesLength
                sim.spatialLookupLength = msg.lookupLength
                threads[2].send:push(msg)
            end

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
