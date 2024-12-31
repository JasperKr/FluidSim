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
        density = 1.8,
    }
    fixture:setDensity(t.density)
    body:resetMassData()

    body:setLinearDamping(0.4)
    body:setAngularDamping(0.4)

    return setmetatable(t, hullMt)
end

local function checkAndResolve(hull, self)
    local localPosX, localPosY = hull.body:getLocalPoint(self.CData.x, self.CData.y)

    local minX, minY, maxX, maxY = hull.shape:computeAABB(0, 0, 0)

    if circleInAABB(minX, minY, maxX, maxY, localPosX, localPosY, self.radius) then
        local dist, intersectionX, intersectionY, diffX, diffY, sign = pointAABBDistanceSqr(
            minX,
            minY,
            maxX,
            maxY,
            localPosX,
            localPosY
        )

        ---@cast hull {body: love.Body}

        intersectionX, intersectionY = hull.body:getWorldPoint(intersectionX, intersectionY)

        if dist < self.radius * self.radius or sign < 0 then -- collision or inside
            local normalX, normalY = normalize(hull.body:getWorldVector(diffX, diffY))

            local overlap = -math.sqrt(dist) * sign

            local massDivScale = self.realMass / Settings.scale

            local forceInDirection = math.max(0.0, vectorMath.dot(self.CData.velocityX * massDivScale,
                self.CData.velocityY * massDivScale, normalX, normalY))

            self.CData.x = self.CData.x - normalX * overlap
            self.CData.y = self.CData.y - normalY * overlap

            local fx = normalX * forceInDirection
            local fy = normalY * forceInDirection

            self.CData.velocityX = self.CData.velocityX - fx / massDivScale
            self.CData.velocityY = self.CData.velocityY - fy / massDivScale

            hull.body:applyLinearImpulse(fx * massDivScale, fy * massDivScale,
                intersectionX, intersectionY)
        end
    end
end

function hullFunctions:getParticles(checkPredicted)
    local minX, minY, maxX, maxY = self.fixture:getBoundingBox()
    minX = minX - Settings.particleRadius
    minY = minY - Settings.particleRadius
    maxX = maxX + Settings.particleRadius
    maxY = maxY + Settings.particleRadius
    local points = {}

    local shapeMinX, shapeMinY, shapeMaxX, shapeMaxY = self.shape:computeAABB(0, 0, 0)

    minX = math.floor(minX * Settings.inverseChunkSize)
    minY = math.floor(minY * Settings.inverseChunkSize)
    maxX = math.ceil(maxX * Settings.inverseChunkSize)
    maxY = math.ceil(maxY * Settings.inverseChunkSize)

    for x = minX, maxX do
        for y = minY, maxY do
            local key = sim.positionToIndex(x, y)
            local startIndex = tonumber(sim.startIndices[key])

            if startIndex == -2147483648 then
                startIndex = math.huge
            end

            if startIndex and startIndex ~= -1 and startIndex ~= -2 then
                for index = startIndex, sim.spatialLookupLength do
                    if tonumber(sim.spatialLookup[index].key) ~= key then
                        break
                    end

                    local particleIndex = tonumber(sim.spatialLookup[index].index)
                    local particle = Particles[particleIndex]

                    local objectSpaceX, objectSpaceY = self.body:getLocalPoint(particle.CData.x, particle.CData.y)

                    if circleInAABB(shapeMinX, shapeMinY, shapeMaxX, shapeMaxY, objectSpaceX, objectSpaceY, particle.radius) then
                        table.insert(points, particle)
                        -- elseif checkPredicted then
                        --     objectSpaceX, objectSpaceY = self.body:getLocalPoint(particle.predictedX, particle.predictedY)
                        --     if circleInAABB(shapeMinX, shapeMinY, shapeMaxX,
                        --             shapeMaxY, objectSpaceX, objectSpaceY, particle.radius) then
                        --         table.insert(points, particle)
                        --     end
                    end
                end
            end
        end
    end

    return points
end

function hullFunctions:update(dt)
    local particles = self:getParticles()
    if #particles > 0 then
        -- print(#particles)
    end
    for _, particle in ipairs(particles) do
        checkAndResolve(self, particle)
    end
end

function hullFunctions:draw()
    local vertices = { self.shape:getPoints() }
    love.graphics.setColor(0.3, 0.3, 0.3, 0.7)
    love.graphics.polygon("fill", self.body:getWorldPoints(unpack(vertices)))
end
