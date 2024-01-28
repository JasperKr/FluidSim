--- swap two elements in an array
---@param arr table|ffi.cdata*
---@param index1 integer
---@param index2 integer
function default_swap(arr, index1, index2)
    local temp = arr[index1]
    arr[index1] = arr[index2]
    arr[index2] = temp
end

---@param arr table|ffi.cdata*
---@param lower integer
---@param upper integer
---@param compare fun(a: any, b: any): boolean
---@param swap fun(arr: table|ffi.cdata*, index1: integer, index2: integer)
function partition(arr, lower, upper, compare, swap)
    local i = lower - 1

    local pivot = arr[upper]

    for j = lower, upper do
        if compare(arr[j], pivot) then
            i = i + 1
            swap(arr, i, j)
        end
    end

    swap(arr, i + 1, upper)

    return i + 1
end

---@param arr table|ffi.cdata*
---@param lower integer
---@param upper integer
---@param compare fun(a: any, b: any): boolean
---@param swap fun(arr: table|ffi.cdata*, index1: integer, index2: integer)
function quickSort(arr, lower, upper, compare, swap)
    if upper < lower then
        return
    end

    swap = swap or default_swap

    local partitionIndex = partition(arr, lower, upper, compare, swap)

    quickSort(arr, lower, partitionIndex - 1, compare, swap)
    quickSort(arr, partitionIndex + 1, upper, compare, swap)
end

return quickSort
