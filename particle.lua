local particleFunctions = {}
local particleMt = { __index = particleFunctions }

local particleCollisionShape = {}
do -- create particle collision shape
    local shape = love.physics.newCircleShape(1.25)
    local body = love.physics.newBody(Box2DWorld, 100, 100, "kinematic")
    local fixture = love.physics.newFixture(body, shape)
    fixture:setSensor(true)
    particleCollisionShape = {
        shape = shape,
        body = body,
        fixture = fixture
    }
end

function newParticle(x, y, restitution)
    local self = {
        x = x,
        y = y,
        velocityX = 0,
        velocityY = 0,
        radius = Settings.particleRadius,
        restitution = restitution or 0.9,
        property = 0,
        density = 1,
        inverseDensity = 1,
        mass = 10,
        pointsInRadius = {},
        chunkUpdateDelay = Settings.chunkUpdateDelay,
        chunkUpdateTimer = love.math.random(0, Settings.chunkUpdateDelay), -- stagger chunk updates
        pointsInRadiusAmount = 0,
        updateX = x,
        updateY = y,
    }
    self.inverseMass = 1 / self.mass
    table.insert(Particles, self)
    return setmetatable(self, particleMt)
end

function particleFunctions:update(dt)
    self.x = self.x + self.velocityX * dt
    self.y = self.y + self.velocityY * dt

    self.velocityY = self.velocityY + Settings.gravity * dt

    self:resolveCollisions()
end

function particleFunctions:draw()
    if Settings.debugDraw then
        local velocity = length(self.velocityX, self.velocityY)
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

function particleFunctions:resolveCollisions()
    local minX, minY = self.x - self.radius, self.y - self.radius
    local maxX, maxY = self.x + self.radius, self.y + self.radius

    if minX < 0 then
        self.x = self.radius
        self.velocityX = math.abs(self.velocityX) * self.restitution
    elseif maxX > love.graphics.getWidth() then
        self.x = love.graphics.getWidth() - self.radius
        self.velocityX = -math.abs(self.velocityX) * self.restitution
    end

    if maxY > love.graphics.getHeight() then
        self.y = love.graphics.getHeight() - self.radius
        self.velocityY = -math.abs(self.velocityY) * self.restitution
    end
end
