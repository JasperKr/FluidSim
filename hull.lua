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

    return setmetatable(t, hullMt)
end

local function checkAndResolve(hull, self, x, y)
    local localPosX, localPosY = hull.body:getLocalPoint(x, y)

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

        intersectionX, intersectionY = hull.body:getWorldPoint(intersectionX, intersectionY)


        if dist < self.radius * self.radius or sign < 0 then -- collision or inside
            local normalX, normalY = normalize(diffX, diffY)
            normalX, normalY = hull.body:getWorldVector(normalX, normalY)

            local overlap = -math.sqrt(dist) * sign

            self.x = self.x - normalX * overlap
            self.y = self.y - normalY * overlap

            local forceInDirection = vectorMath.dot(self.velocityX, self.velocityY, normalX, normalY)

            local fx = normalX * forceInDirection
            local fy = normalY * forceInDirection

            self.velocityX = self.velocityX - fx
            self.velocityY = self.velocityY - fy

            hull.body:applyLinearImpulse(fx * Settings.fluidMass * self.mass, fy * Settings.fluidMass * self.mass,
                intersectionX, intersectionY)
        end
    end
end

local function positionToIndex(x, y)
    return (x * 5376 + y * 9737333) % #Particles
end

function hullFunctions:getParticles(checkPredicted)
    local minX, minY, maxX, maxY = self.fixture:getBoundingBox()
    minX = minX - Settings.particleRadius
    minY = minY - Settings.particleRadius
    maxX = maxX + Settings.particleRadius
    maxY = maxY + Settings.particleRadius
    local points = {}
    local predictedParticles = {}

    local shapeMinX, shapeMinY, shapeMaxX, shapeMaxY = self.shape:computeAABB(0, 0, 0)


    for x = math.floor(minX * Settings.inverseChunkSize), math.ceil(maxX * Settings.inverseChunkSize) do
        for y = math.floor(minY * Settings.inverseChunkSize), math.ceil(maxY * Settings.inverseChunkSize) do
            local key = positionToIndex(x, y)
            local startIndex = StartIndices[key]
            if startIndex then
                for index = startIndex, #SpatialLookup do
                    if SpatialLookup[index][2] ~= key then
                        break
                    end

                    local particleIndex = SpatialLookup[index][1]
                    local particle = Particles[particleIndex]

                    local objectSpaceX, objectSpaceY = self.body:getLocalPoint(particle.x, particle.y)

                    if circleInAABB(shapeMinX, shapeMinY, shapeMaxX, shapeMaxY, objectSpaceX, objectSpaceY, particle.radius) then
                        table.insert(points, particle)
                    elseif checkPredicted then
                        objectSpaceX, objectSpaceY = self.body:getLocalPoint(particle.predictedX, particle.predictedY)
                        if circleInAABB(shapeMinX, shapeMinY, shapeMaxX,
                                shapeMaxY, objectSpaceX, objectSpaceY, particle.radius) then
                            table.insert(points, particle)
                        end
                    end
                end
            end
        end
    end

    return points, predictedParticles
end

function hullFunctions:update(dt)
    local particles, predictedParticles = self:getParticles()
    for _, particle in ipairs(particles) do
        checkAndResolve(self, particle, particle.x, particle.y)
    end
    for _, particle in ipairs(predictedParticles) do
        checkAndResolve(self, particle, particle.predictedX, particle.predictedY)
    end
end

function hullFunctions:draw()
    local vertices = { self.shape:getPoints() }
    love.graphics.setColor(0.3, 0.3, 0.3, 0.7)
    love.graphics.polygon("fill", self.body:getWorldPoints(unpack(vertices)))
end
