Settings, receive, send, width, height = unpack(...)

require("vectorMath")
require("particle")
sim = require("fluidSimulation")
require("vec")
require("love.timer")
require("love.math")

Particles = {}

local targetFramerate = 1 / 60

while true do
    local startTime = love.timer.getTime()

    local msg = receive:pop()

    while msg do
        if msg.type == "addParticle" then
            local particle = newParticle(msg.data[1], msg.data[2], msg.data[3], true, msg.pointer)
            table.insert(Particles, particle)
        end

        msg = receive:pop()
    end

    coroutine.resume(sim.coroutines.updateLookup)

    local endTime = love.timer.getTime()

    local sleepTime = targetFramerate - (endTime - startTime)

    love.timer.sleep(sleepTime)
end
