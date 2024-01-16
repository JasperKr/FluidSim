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
        mass = 10
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
    local velocity = length(self.velocityX, self.velocityY)
    local gradientMax = 1000

    local r = velocity / gradientMax       --0.2
    local g = self.density * 10            --0.3
    local b = 0.6 - velocity / gradientMax --0.6

    love.graphics.setColor(r, g, b, 1)

    local img = Settings.gradientImage

    --love.graphics.draw(img, self.x, self.y, 0, self.radius * 2 * Settings.drawRadius / img:getWidth(),
    --    self.radius * 2 * Settings.drawRadius / img:getHeight(),
    --    img:getWidth() / 2, img:getHeight() / 2)

    love.graphics.circle("fill", self.x, self.y, self.radius)
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

    if minY < 0 then
        self.y = self.radius
        self.velocityY = math.abs(self.velocityY) * self.restitution
    elseif maxY > love.graphics.getHeight() then
        self.y = love.graphics.getHeight() - self.radius
        self.velocityY = -math.abs(self.velocityY) * self.restitution
    end

    local wallProximityForceMultiplier = 30

    if minX < 10 then
        self.velocityX = self.velocityX + (10 - minX) * wallProximityForceMultiplier
    end

    if maxX > love.graphics.getWidth() - 10 then
        self.velocityX = self.velocityX - (maxX - love.graphics.getWidth() + 10) * wallProximityForceMultiplier
    end

    if minY < 10 then
        self.velocityY = self.velocityY + (10 - minY) * wallProximityForceMultiplier
    end

    if maxY > love.graphics.getHeight() - 10 then
        self.velocityY = self.velocityY - (maxY - love.graphics.getHeight() + 10) * wallProximityForceMultiplier
    end

    for _, hull in ipairs(Hulls) do
        -- test collision with hull using particleCollisionShape
        particleCollisionShape.body:setPosition(self.x, self.y)

        local dist, x1, y1, x2, y2 = love.physics.getDistance(particleCollisionShape.fixture, hull.fixture)
        local dx, dy = x2 - x1, y2 - y1

        if dist < self.radius or hull.shape:testPoint(hull.body:getX(), hull.body:getY(), hull.body:getAngle(), self.x, self.y) then
            local normalX, normalY = normalize(dx, dy)

            if normalX == 0 and normalY == 0 then
                local dx = hull.body:getX() - self.x
                local dy = hull.body:getY() - self.y
                normalX, normalY = normalize(dx, dy)
            end

            local overlap = self.radius - dist

            local intersectionX = self.x
            local intersectionY = self.y

            self.x = self.x - normalX * overlap
            self.y = self.y - normalY * overlap

            local forceInDirection = dot(self.velocityX, self.velocityY, normalX, normalY)

            local fx = normalX * forceInDirection
            local fy = normalY * forceInDirection

            self.velocityX = self.velocityX - fx
            self.velocityY = self.velocityY - fy

            hull.body:applyLinearImpulse(fx * Settings.fluidMass * self.mass, fy * Settings.fluidMass * self.mass,
                intersectionX, intersectionY)

            self.wasInHull = true
        end
    end
end
