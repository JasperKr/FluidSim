local particleFunctions = {}
local particleMt = { __index = particleFunctions }

function newParticle(x, y, radius, restitution)
    local self = {
        x = x,
        y = y,
        velocityX = 0,
        velocityY = 0,
        radius = radius,
        restitution = restitution or 0.9,
        property = 0,
        density = 1,
        inverseDensity = 1,
    }
    table.insert(Particles, self)
    return setmetatable(self, particleMt)
end

function particleFunctions:update(dt)
    self.x = self.x + self.velocityX * dt
    self.y = self.y + self.velocityY * dt

    self.velocityY = self.velocityY + Settings.gravity

    self:resolveCollisions()
end

function particleFunctions:draw()
    love.graphics.circle("fill", self.x, self.y, self.radius)
end

function particleFunctions:resolveCollisions()
    local minX, minY = self.x - self.radius, self.y - self.radius
    local maxX, maxY = self.x + self.radius, self.y + self.radius

    if minX < 0 then
        self.x = self.radius
        self.velocityX = -self.velocityX * self.restitution
    elseif maxX > love.graphics.getWidth() then
        self.x = love.graphics.getWidth() - self.radius
        self.velocityX = -self.velocityX * self.restitution
    end

    if minY < 0 then
        self.y = self.radius
        self.velocityY = -self.velocityY * self.restitution
    elseif maxY > love.graphics.getHeight() then
        self.y = love.graphics.getHeight() - self.radius
        self.velocityY = -self.velocityY * self.restitution
    end
end
