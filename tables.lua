local indexedTableMetatable = {}
---@class indexedTable
local indexedTableFunctions = { indexTable = {} }
---@return indexedTable
function newIndexedTable()
    local t = {
        indexTable = {}
    }
    setmetatable(t, indexedTableMetatable)
    return t
end

indexedTableMetatable.__index = indexedTableFunctions

function indexedTableFunctions:add(v)
    table.insert(self, v)
    self.indexTable[v.id] = #self
end

---removes something from the table
---@param i number
function indexedTableFunctions:remove(i)
    local w = self[i]
    if i == #self then
        table.remove(self, i)
        self.indexTable[w.id] = nil
    else
        local lastIndex = #self
        local lastObject = self[lastIndex]
        self[i] = lastObject
        self.indexTable[lastObject.id] = i
        self.indexTable[w.id] = nil
        table.remove(self, #self)
    end
end

function indexedTableFunctions:removeAsObject(v)
    if v and v.id then
        local i = self.indexTable[v.id]
        if i then
            if i == #self then
                self.indexTable[v.id] = nil
                table.remove(self, i)
            else
                local lastObject = self[#self]
                self[i] = lastObject
                if lastObject then
                    self.indexTable[lastObject.id] = i
                end
                self.indexTable[v.id] = nil
                table.remove(self, #self)
            end
        end
    end
end

local objectIndexedTableMetatable = {}
---@class objectIndexedTable
local objectIndexedTableFunctions = { indexTable = {} }
---@return objectIndexedTable
function newObjectIndexedTable()
    return setmetatable({ indexTable = {} }, objectIndexedTableMetatable)
end

objectIndexedTableMetatable.__index = objectIndexedTableFunctions

function objectIndexedTableFunctions:add(v)
    table.insert(self, v)
    self.indexTable[v] = #self
end

---removes something from the table
---@param i number
function objectIndexedTableFunctions:remove(i)
    local w = self[i]
    if i == #self then
        self.indexTable[w] = nil
        return table.remove(self, i)
    else
        local lastIndex = #self
        local lastObject = self[lastIndex]
        self[i] = lastObject
        self.indexTable[lastObject] = i
        self.indexTable[w] = nil
        return table.remove(self, #self)
    end
end

function objectIndexedTableFunctions:removeAsObject(v)
    if v then
        local i = self.indexTable[v]
        if i then
            if i == #self then
                self.indexTable[v] = nil
                return table.remove(self, i)
            else
                local lastObject = self[#self]
                self[i] = lastObject
                if lastObject then
                    self.indexTable[lastObject] = i
                end
                self.indexTable[v] = nil
                return table.remove(self, #self)
            end
        end
    end
end

--- pops the last object from the table
function objectIndexedTableFunctions:pop()
    local i = #self
    local w = self[i]
    self.indexTable[w] = nil
    return table.remove(self, i)
end
