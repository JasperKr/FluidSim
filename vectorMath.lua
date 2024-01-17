vectorMath = {}

function vectorMath.dot(x1, y1, x2, y2)
    return x1 * x2 + y1 * y2
end

function vectorMath.normalize(x, y)
    local len = math.sqrt(x * x + y * y)

    if len == 0 then
        return 0, 0
    end

    return x / len, y / len
end

function vectorMath.length(x, y)
    return math.sqrt(x * x + y * y)
end

function vectorMath.distance(x1, y1, x2, y2)
    return math.sqrt((x2 - x1) ^ 2 + (y2 - y1) ^ 2)
end

function vectorMath.distanceSqr(x1, y1, x2, y2)
    return (x2 - x1) ^ 2 + (y2 - y1) ^ 2
end

function vectorMath.angle(x1, y1, x2, y2)
    return math.atan2(y2 - y1, x2 - x1)
end

function vectorMath.lengthSqr(x, y)
    return x * x + y * y
end

function vectorMath.rotate(x, y, angle)
    local sin = math.sin(angle)
    local cos = math.cos(angle)

    return x * cos - y * sin, x * sin + y * cos
end

function vectorMath.rotateAround(x, y, angle, ox, oy)
    local sin = math.sin(angle)
    local cos = math.cos(angle)

    local dx = x - ox
    local dy = y - oy

    return dx * cos - dy * sin + ox, dx * sin + dy * cos + oy
end

function vectorMath.lerp(x1, y1, x2, y2, t)
    return x1 + (x2 - x1) * t, y1 + (y2 - y1) * t
end

function vectorMath.lerpAngle(a1, a2, t)
    local max = math.pi * 2
    local da = (a2 - a1) % max

    if da > math.pi then
        da = da - max
    end

    return a1 + da * t
end

function vectorMath.lerpAngleAround(a1, a2, t, around)
    local max = math.pi * 2
    local da = (a2 - a1) % max

    if da > math.pi then
        da = da - max
    end

    return a1 + da * t
end
