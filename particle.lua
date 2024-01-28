local particleFunctions = {}
local particleMt = { __index = particleFunctions }

local ffi = require("ffi")

ffi.cdef [[
    typedef struct {
        float x;
        float y;
    } vec2;

    typedef struct {
        float x;
        float y;
        float velocityX;
        float velocityY;
    } sharedParticleData;
]]

function newParticle(x, y, restitution, thread, pointer)
    local self = {
        x = x,
        y = y,
        velocityX = 0,
        velocityY = 0,
        radius = Settings.particleRadius,
        restitution = restitution or 0.9,
        density = 1,
        inverseDensity = 1,
        mass = 10,
        pointsInRadius = {},
        chunkUpdateDelay = Settings.chunkUpdateDelay,
        chunkUpdateTimer = love.math.random(0, Settings.chunkUpdateDelay), -- stagger chunk updates
        pointsInRadiusAmount = 0,
        updateX = x,
        updateY = y,
        Creference = (not thread) and ffi.new("sharedParticleData", { x = x, y = y, velocityX = 0, velocityY = 0 }),
    }
    self.inverseMass = 1 / self.mass
    if not thread then
        self.CPointer = ffi.new("sharedParticleData*", self.Creference)
    end

    table.insert(Particles, self)

    if not thread then
        local pointerNum = tonumber(ffi.cast("uint64_t", self.CPointer))
        FluidSimulation.Thread.send:push({ type = "addParticle", data = { x, y, restitution }, pointer = pointerNum })
    end

    if thread then
        local ptr = pointer
        local castPtr = ffi.cast("void*", ptr)

        self.Creference = ffi.cast("sharedParticleData*", castPtr)
    end

    return setmetatable(self, particleMt)
end

function particleFunctions:update(dt, thread, width, height)
    if thread then
        self.x = self.x + self.velocityX * dt
        self.y = self.y + self.velocityY * dt

        self:resolveCollisions(width, height)

        self.velocityY = self.velocityY + Settings.gravity * dt

        self.Creference.x = self.x
        self.Creference.y = self.y

        self.Creference.velocityX = self.velocityX
        self.Creference.velocityY = self.velocityY
    else
        self.x = self.Creference.x
        self.y = self.Creference.y

        self.velocityX = self.Creference.velocityX
        self.velocityY = self.Creference.velocityY

        self.predictedX = self.x + self.velocityX * (1 / 60)
        self.predictedY = self.y + self.velocityY * (1 / 60)
    end
end

function particleFunctions:draw()
    if Settings.debugDraw then
        local velocity = vectorMath.length(self.velocityX, self.velocityY)
        local gradientMax = 1000

        local r = velocity / gradientMax       --0.2
        local g = self.density * 10            --0.3
        local b = 0.6 - velocity / gradientMax --0.6

        love.graphics.setColor(r, g, b, 1)

        love.graphics.circle("fill", self.x, self.y, self.radius)
    else
        local r = 0.2
        local g = 0.3
        local b = 0.6

        love.graphics.setColor(r, g, b, 1)

        local img = Settings.gradientImage

        love.graphics.draw(img, self.x, self.y, 0, self.radius * 2 * Settings.drawRadius / img:getWidth(),
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
    local minX, minY = self.x - self.radius, self.y - self.radius
    local maxX, maxY = self.x + self.radius, self.y + self.radius

    if minX < 0 then
        self.x = self.radius
        self.velocityX = math.abs(self.velocityX) * self.restitution
    elseif maxX > width then
        self.x = width - self.radius
        self.velocityX = -math.abs(self.velocityX) * self.restitution
    end

    if maxY > height then
        self.y = height - self.radius
        self.velocityY = -math.abs(self.velocityY) * self.restitution
    end
end
