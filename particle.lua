local particleFunctions = {}
local particleMt = { __index = particleFunctions }

local ffi = require("ffi")

ffi.cdef([[
    typedef struct {
        double x;
        double y;
        double velocityX;
        double velocityY;
        double predictedX;
        double predictedY;
        int neighbours[]] .. Settings.maxNeighbours .. [[]; // neighbours id's
        int neighboursAmount;
        float mass;
        float density;
        int id;
    } sharedParticleData;
]])

local particleSize = ffi.sizeof("sharedParticleData")

function newParticle(x, y, restitution, thread, ByteData)
    if not thread then
        ByteData = love.data.newByteData(particleSize)
    end

    local CData = ffi.cast("sharedParticleData*", ByteData:getFFIPointer())

    local self = {
        radius = Settings.particleRadius,
        restitution = restitution or 0.9,
        density = 1,
        inverseDensity = 1,
        mass = 10,
        realMass = 10 * Settings.fluidMass,
        chunkUpdateDelay = Settings.chunkUpdateDelay,
        chunkUpdateTimer = love.math.random(0, Settings.chunkUpdateDelay), -- stagger chunk updates
        updateX = x,
        updateY = y,
        ByteData = ByteData,
        CData = CData,
        id = thread and CData.id or #Particles + 1,
    }
    self.inverseMass = 1 / self.mass

    if not thread then
        CData.x = x
        CData.y = y
        CData.velocityX = 0
        CData.velocityY = 0
        CData.predictedX = x
        CData.predictedY = y
        CData.neighboursAmount = 0
        for i = 0, Settings.maxNeighbours - 1 do
            CData.neighbours[i] = -1
        end
        CData.mass = self.mass
        CData.density = self.density
        CData.id = self.id
    end

    setmetatable(self, particleMt)

    Particles:add(self)

    if not thread then
        FluidSimulation.Thread.send:push({ type = "addParticle", data = { x, y, restitution, ByteData } })
    end

    return self
end

function particleFunctions:update(dt, thread, width, height)
    if thread then
        self.CData.x = self.CData.x + self.CData.velocityX * dt
        self.CData.y = self.CData.y + self.CData.velocityY * dt

        self:resolveCollisions(width, height)

        self.CData.velocityY = self.CData.velocityY + Settings.gravity * dt

        self.CData.predictedX = self.CData.x + self.CData.velocityX * (1 / 60)
        self.CData.predictedY = self.CData.y + self.CData.velocityY * (1 / 60)
    end
end

function particleFunctions:draw(i)
    if Settings.debugDraw then
        local velocity = vectorMath.length(self.CData.velocityX, self.CData.velocityY)
        local gradientMax = 1000

        local r = velocity / gradientMax       --0.2
        local g = self.density * 10            --0.3
        local b = 0.6 - velocity / gradientMax --0.6

        love.graphics.setColor(r, g, b, 1)

        love.graphics.circle("fill", self.CData.x, self.CData.y, self.radius)
    else
        local r = 0.2
        local g = 0.3
        local b = 0.6

        love.graphics.setColor(r, g, b, 1)

        local img = Settings.gradientImage

        love.graphics.draw(img, self.CData.x, self.CData.y, 0, self.radius * 2 * Settings.drawRadius / img:getWidth(),
            self.radius * 2 * Settings.drawRadius / img:getHeight(),
            img:getWidth() / 2, img:getHeight() / 2)
    end
end

function circleInAABB(minX, minY, maxX, maxY, px, py, radius)
    return px >= minX - radius and px <= maxX + radius and py >= minY - radius and py <= maxY + radius
end

---  distance between point and AABB and edge point
--- @param minX number
--- @param minY number
--- @param maxX number
--- @param maxY number
--- @param px number
--- @param py number
---@return number distance
---@return number edgeX
---@return number edgeY
---@return number diffX
---@return number diffY
---@return number sign
function pointAABBDistanceSqr(minX, minY, maxX, maxY, px, py)
    local dx, dy = 0, 0

    if px < minX then
        dx = minX - px
    elseif px > maxX then
        dx = maxX - px
    end

    if py < minY then
        dy = minY - py
    elseif py > maxY then
        dy = maxY - py
    end

    -- if we're inside, get the signed distance to the nearest edge
    if dx == 0 and dy == 0 then
        local distToX = math.min(math.abs(px - minX), math.abs(maxX - px))
        local distToY = math.min(math.abs(py - minY), math.abs(maxY - py))

        if distToX < distToY then
            local edge = px < (minX + maxX) / 2 and minX or maxX

            dx = px - edge

            return dx * dx, edge, py, dx, 0, -1
        else
            local edge = py < (minY + maxY) / 2 and minY or maxY

            dy = py - edge

            return dy * dy, px, edge, 0, dy, -1
        end
    end

    return dx * dx + dy * dy, px + dx, py + dy, dx, dy, 1
end

function particleFunctions:resolveCollisions(width, height)
    local minX, minY = self.CData.x - self.radius, self.CData.y - self.radius
    local maxX, maxY = self.CData.x + self.radius, self.CData.y + self.radius

    if minX < 0 then
        self.CData.x = self.radius
        self.CData.velocityX = math.abs(self.CData.velocityX) * self.restitution
    elseif maxX > width then
        self.CData.x = width - self.radius
        self.CData.velocityX = -math.abs(self.CData.velocityX) * self.restitution
    end

    if minY < -2000 then
        self.CData.y = self.radius
        self.CData.velocityY = math.abs(self.CData.velocityY) * self.restitution
    elseif maxY > height then
        self.CData.y = height - self.radius
        self.CData.velocityY = -math.abs(self.CData.velocityY) * self.restitution
    end
end
