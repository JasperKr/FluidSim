local hullMt = {}
---@class hull
---@field body love.Body
---@field fixture love.Fixture
---@field density number
---@field shape love.PolygonShape
local hullFunctions = {}
hullMt.__index = hullFunctions


--- Creates a new hull object.
---@param body love.Body
---@param fixture love.Fixture
---@param shape love.PolygonShape
function newHull(body, fixture, shape)
    local t = {
        body = body,
        fixture = fixture,
        shape = shape,
        density = 1,
    }

    return setmetatable(t, hullMt)
end

function hullFunctions:update(dt)
    --local mass = self.body:getMass()
    --local vertices = { self.shape:getPoints() }

    -- local vx, vy = self.body:getLinearVelocity()
    -- for index = 1, #vertices, 2 do
    --     local localX, localY = vertices[index], vertices[index + 1]
    --     local x, y = self.body:getWorldPoint(localX, localY)

    --     local pointsInRadius = getPointsInRadius(x, y)

    --     local density = calculateDensity(x, y, pointsInRadius) -- density at the point

    --     local pressureX, pressureY = calculatePressureForce(nil, pointsInRadius, x, y, density)
    --     local viscosityX, viscosityY = calculateViscosityForce(nil, pointsInRadius, x, y, vx, vy)

    --     local ax = -(pressureX - viscosityX * Settings.viscosity) * dt / self.density
    --     local ay = -(pressureY - viscosityY * Settings.viscosity) * dt / self.density

    --     local fx = ax * Settings.scale
    --     local fy = ay * Settings.scale

    --     self.body:applyLinearImpulse(fx, fy, x, y)
    -- end
end

function hullFunctions:draw()
    local vertices = { self.shape:getPoints() }
    love.graphics.setColor(0.3, 0.3, 0.3, 0.7)
    love.graphics.polygon("fill", self.body:getWorldPoints(unpack(vertices)))
end
