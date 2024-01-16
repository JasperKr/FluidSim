local QuadTree = {}
local QuadTreeMt = {}
local QuadTreeFunctions = {}
function QuadTree.create(x, y, size, maxDepth, splitThreshold, depth, parent)
    local tree = {
        x = x,
        y = y,
        size = size,
        objects = newObjectIndexedTable(),
        maxDepth = maxDepth or 8,
        splitThreshold = splitThreshold or 3,
        depth = depth or 0,
        parent = parent,
        nodes = {}
    }
    setmetatable(tree, QuadTreeMt)
    return tree
end

QuadTreeMt.__index = QuadTreeFunctions

function QuadTreeFunctions:split()
    if #self.nodes == 0 then
        local x, y = self.x, self.y
        local size = self.size * 0.5
        table.insert(self.nodes, QuadTree.create(x, y, size, self.maxDepth, self.splitThreshold, self.depth + 1, self))
        table.insert(self.nodes, QuadTree.create(x + size, y, size, self.maxDepth, self.splitThreshold, self.depth + 1,
            self))
        table.insert(self.nodes, QuadTree.create(x, y + size, size, self.maxDepth, self.splitThreshold, self.depth + 1,
            self))
        table.insert(self.nodes, QuadTree.create(x + size, y + size, size, self.maxDepth, self.splitThreshold,
            self.depth + 1, self))
        for i, v in ipairs(self.objects) do
            local index = self:index(v)
            if index > 0 then
                self.nodes[index]:add(v)
            end
        end
    end
end

function QuadTreeFunctions:combine()
    if #self.nodes > 0 then
        for i, v in ipairs(self.nodes) do
            for j, obj in ipairs(v:combine()) do
                self.objects:add(obj)
            end
        end
        self.nodes = {}
    end
    return self.objects
end

function AABB(v, chunk)
    return v.x + v.width > chunk.x and v.y + v.height > chunk.y and v.x < chunk.x + chunk.size and
        v.y < chunk.y + chunk.size
end

function QuadTreeFunctions:index(object)
    local x, y = object.x, object.y
    local w, h = object.width * 0.5, object.height * 0.5
    if x + w < self.x or y + h < self.y or x - w > self.x + self.size or y - h > self.y + self.size then
        return -1
    end
    if y + h < self.y + self.size * 0.5 then     -- top half
        if x + w < self.x + self.size * 0.5 then -- left
            return 1
        elseif x > self.x + self.size * 0.5 then
            return 2
        end
    elseif y > self.y + self.size * 0.5 then
        if x + w < self.x + self.size * 0.5 then -- left
            return 3
        elseif x > self.x + self.size * 0.5 then
            return 4
        end
    end
    return 0
end

function QuadTreeFunctions:add(object)
    local index = self:index(object)
    if index > 0 then
        if #self.nodes > 0 then
            self.nodes[index]:add(object)
        else
            if not self.objects.indexTable[object] then
                self.objects:add(object)
            end
        end
    elseif index == 0 then
        if not self.objects.indexTable[object] then
            self.objects:add(object)
        end
    end
    if #self.objects > self.splitThreshold and self.depth < self.maxDepth and #self.nodes == 0 then
        self:split()
    end
end

function QuadTreeFunctions:total()
    local total = #self.objects
    if #self.nodes > 0 then
        for i, v in ipairs(self.nodes) do
            total = total + v:total()
        end
    end
    return total
end

function QuadTreeFunctions:minimize()
    local total = #self.objects
    if #self.nodes > 0 then
        for i, v in ipairs(self.nodes) do
            total = total + v:minimize()
        end
        if total < self.splitThreshold then
            self:combine()
        end
    end
    return total
end

function QuadTreeFunctions:queryInternal(x, y, width, height, found)
    for i, v in ipairs(self.objects) do
        if v.x + v.width > x and v.y + v.height > y and v.x < x + width and v.y < y + height then
            table.insert(found, v)
        end
    end
    for i, v in ipairs(self.nodes) do
        if v.x + v.size >= x and v.y + v.size >= y and v.x <= x + width and v.y <= y + height then
            v:queryInternal(x, y, width, height, found)
        end
    end
end

function QuadTreeFunctions:query(x, y, width, height, found)
    if not found then
        found = {}
    end
    for i = #self.objects, 1, -1 do
        local v = self.objects[i]
        if v.x + v.width > x and v.y + v.height > y and v.x < x + width and v.y < y + height then
            table.insert(found, v)
        end
    end
    for i, v in ipairs(self.nodes) do
        if v.x + v.size >= x and v.y + v.size >= y and v.x <= x + width and v.y <= y + height then
            v:queryInternal(x, y, width, height, found)
        end
    end
    return found
end

function QuadTreeFunctions:exists(object)
    if self.objects.indexTable[object.id] then return true end
    if #self.nodes > 0 then
        for i, v in ipairs(self.nodes) do
            if v:exists(object) then return true end
        end
    end
    return false
end

function QuadTreeFunctions:remove(object)
    self.objects:removeAsObject(object)
    for i, v in ipairs(self.nodes) do
        v:remove(object)
    end
end

function QuadTreeFunctions:base()
    if self.parent then
        return self.parent:base()
    else
        return self
    end
end

function QuadTreeFunctions:update(object)
    self:remove(object)
    self:add(object)
    self:minimize()
end

return QuadTree
