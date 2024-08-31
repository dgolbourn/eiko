local function _back(current)
    local here = string.sub(current, -1)
    local parent = string.sub(current, 1, -2)
    if here == '0' then
        return parent .. '1'
    elseif here == '1' then
        return parent .. '0'
    elseif here == '2' then
        return _back(parent) .. '3'
    elseif here == '3' then
        return _back(parent) .. '2'
    else
        return ''
    end
end

local function _right(current)
    local here = string.sub(current, -1)
    local parent = string.sub(current, 1, -2)
    if here == '0' then
        return parent .. '3'
    elseif here == '1' then
        return _right(parent) .. '2'
    elseif here == '2' then
        return _right(parent) .. '1'
    elseif here == '3' then
        return parent .. '0'
    else
        return ''
    end
end

local function _left(current)
    local here = string.sub(current, -1)
    local parent = string.sub(current, 1, -2)
    if here == '0' then
        return parent .. '2'
    elseif here == '1' then
        return _left(parent) .. '3'
    elseif here == '2' then
        return parent .. '0'
    elseif here == '3' then
        return _left(parent) .. '1'
    else
        return ''
    end
end

local function _flip(orientation)
    if orientation == '0' then
        return '1'
    elseif orientation == '1' then
        return '0'
    end
end

local function _parity_form(position)
    local major_region = tonumber(string.sub(position, 1, 1))
    local orientation = 1
    if major_region >= 4 then
        major_region = major_region - 4
        orientation = 0
    end
    local minor_regions = string.sub(position, 2, -1)
    local regions = major_region .. minor_regions
    orientation = orientation + tonumber(select(2, string.gsub(regions, '0', '')))
    orientation = orientation % 2
    return orientation .. major_region .. minor_regions
end

local function _implicit_form(position)
    local orientation = tonumber(string.sub(position, 1, 1))
    local major_region = tonumber(string.sub(position, 2, 2))
    local minor_regions = string.sub(position, 3, -1)
    local regions = string.sub(position, 2, -1)
    local parity = tonumber(select(2, string.gsub(regions, '0', ''))) % 2
    if parity == orientation then
        major_region = major_region + 4
    end
    return major_region .. minor_regions
end

local function _move(position, direction)
    local orientation = string.sub(position, 1, 1)
    position = string.sub(position, 2, -1)
    if orientation == '1' then
        direction = direction + 6
    end
    direction = direction % 12
    if direction == 0 then
        position = _flip(orientation) .. _right(_back(_left(position)))
    elseif direction == 1 then
        position = orientation .. _back(_right(position))
    elseif direction == 2 then
        position = _flip(orientation) .. _right(position)
    elseif direction == 3 then
        position = orientation .. _left(_right(position))
    elseif direction == 4 then
        position = _flip(orientation) .. _right(_left(_back(position)))
    elseif direction == 5 then
        position = orientation .. _left(_back(position))
    elseif direction == 6 then
        position = _flip(orientation) .. _back(position)
    elseif direction == 7 then
        position = orientation .. _right(_back(position))
    elseif direction == 8 then
        position = _flip(orientation) .. _left(_right(_back(position)))
    elseif direction == 9 then
        position = orientation .. _right(_left(position))
    elseif direction == 10 then
        position = _flip(orientation) .. _left(position)
    elseif direction == 11 then
        position = orientation .. _back(_left(position))
    end
    return position
end

local function _ray(position, direction, range, regions, idx)
    if range > 0 then
        position = _move(position, direction)
        table.insert(regions[idx], position)
        _ray(position, direction,  range - 1, regions, idx + 1)
    end
end

local function _sector(position, direction, range, regions, idx)
    if range > 0 then
        position = _move(position, direction)
        table.insert(regions[idx], position)
        _sector(position, direction, range - 1, regions, idx + 1)
        _ray(position, direction + 1,  range - 1, regions, idx + 1)
    end
end

local function _area(position, range)
    local regions = {}
    regions[1] = {position}
    for i=2,range+1 do
        regions[i] = {}
    end
    for direction=1,12 do
        _sector(position, direction, range, regions, 2)
    end
    local out = {}
    for _, region in ipairs(regions) do
        for _, tri in ipairs(region) do
            table.insert(out, tri)
        end
    end
    return out
end

local function move(position, direction)
    position = _parity_form(position)
    position = _move(position, direction)
    position = _implicit_form(position)
    return position
end

local function area(position, range)
    position = _parity_form(position)
    local regions = _area(position, range)
    for idx, region in ipairs(regions) do
        regions[idx] = _implicit_form(region)
    end
    return regions
end

local a0 = 1./(3. * math.sqrt(3.))
local b0 = .5 * math.sqrt(3.)

local function _grid_form(position)
    local major_region = string.sub(position, 1, 1)
    local o, x1, y1
    if major_region == '0' then
        o, x1, y1 = -1, 0., 0.
    elseif major_region == '1' then
        o, x1, y1 = 1, 0., 2./3.
    elseif major_region == '2' then
        o, x1, y1 = 1, .5, -1./3.
    elseif major_region == '3' then
        o, x1, y1 = 1, -.5, -1./3.
    elseif major_region == '4' then
        o, x1, y1 = 1, -1., 2./3.
    elseif major_region == '5' then
        o, x1, y1 = -1, -1., 0.
    elseif major_region == '6' then
        o, x1, y1 = -1, .5, 1.
    elseif major_region == '7' then
        o, x1, y1 = -1, -.5, 1.
    end
    local minor_regions = string.sub(position, 2, -1)
    local x, y = 0, 0
    for i=#minor_regions,1,-1 do
        local minor_region = string.sub(minor_regions, i, i)
        local o2, x2, y2
        if minor_region == '0' then
            o2, x2, y2 = -1, 0, 0.
        elseif minor_region == '1' then
            o2, x2, y2 = 1, 0, 1./3.
        elseif minor_region == '2' then
            o2, x2, y2 = 1, 1./4., -1./6.
        elseif minor_region == '3' then
            o2, x2, y2 = 1, -1./4., -1./6.
        end
        x, y = o2 * .5 * x + x2, o2 * .5 * y + y2
    end
    x, y = x1 + o * x, y1 + o * y
    x, y = x + a0 * (3. * y - 1.), y
    x, y = .5 * x, .5 * y
    x, y = x + .5, y + .5
    x, y = math.fmod(x, 1.), math.fmod(y, 1.)
    x, y = x - .5, y - .5
    x, y = 2. * x, 2. * y
    x, y = x + a0 * (1. - 3. * y), y
    return x, y
end

local function _distance(position0, position1)
    local x0, y0 = _grid_form(position0)
    local x1, y1 = _grid_form(position1)
    local dx, dy = x1 - x0, y1 - y0
    if dx < 0. then
        dx = -dx
    end
    if dy < 0. then
        dy = -dy
    end
    if dx > 1. then
        dx = 2. - dx
    end
    if dy > 1. then
        dy = 2. - dy
    end
    dy = b0 * dy
    return dx * dx + dy * dy
end

local function segment(position0, position1)
    local steps = {position0}
    if position0 == position1 then
        return steps
    end
    local distance = math.huge
    local position_pf_next
    local direction_next
    local position_next
    local position_pf_current = _parity_form(position0)
    for direction=1,12 do
        local position_pf_this = _move(position_pf_current, direction)
        local position_this = _implicit_form(position_pf_this)
        local distance_this = _distance(position_this, position1)
        if distance_this < distance then
            position_next = position_this
            position_pf_next = position_pf_this
            direction_next = direction
            distance = distance_this
        end
    end
    local position_current = position_next
    position_pf_current = position_pf_next
    local direction_current = direction_next
    table.insert(steps, position_current)
    while position_current ~= position1 do
        for direction=-1,1 do
            local direction_this = direction_current + direction
            local position_pf_this = _move(position_pf_current, direction_this)
            local position_this = _implicit_form(position_pf_this)
            local distance_this = _distance(position_this, position1)
            if distance_this < distance then
                position_next = position_this
                position_pf_next = position_pf_this
                direction_next = direction_this
                distance = distance_this
            end
        end
        position_current = position_next
        position_pf_current = position_pf_next
        direction_current = direction_next
        table.insert(steps, position_current)
    end
    return steps
end

local function _los_ray(position, direction, range, regions, idx, cover)
    if range > 0 then
        position = _move(position, direction)
        if cover[position] then
        else
            table.insert(regions[idx], position)
            _los_ray(position, direction,  range - 1, regions, idx + 1, cover)
        end
    end
end

local function _los_sector(position, direction, range, regions, idx, cover)
    if range > 0 then
        local forward = _move(position, direction)
        local clear = true
        local partial = false
        if cover[forward] then
            clear = false
        else
            local right = _move(position, direction + 1)
            if cover[right] then
                partial = true
                local left = _move(position, direction - 1)
                if cover[left] then
                    clear = false
                end
            end
        end
        if clear then
            table.insert(regions[idx], forward)
            if partial then
                _los_ray(forward, direction,  range - 1, regions, idx + 1, cover)
            else
                _los_sector(forward, direction, range - 1, regions, idx + 1, cover)
                _los_ray(forward, direction + 1,  range - 1, regions, idx + 1, cover)
            end
        end
    end
end

local function _los_area(position, range, cover)
    local regions = {}
    regions[1] = {position}
    for i=2,range+1 do
        regions[i] = {}
    end
    for direction=1,12 do
        _los_sector(position, direction, range, regions, 2, cover)
    end
    local out = {}
    for _, region in ipairs(regions) do
        for _, tri in ipairs(region) do
            table.insert(out, tri)
        end
    end
    return out
end

local function los(position, range, covers)
    local cover_set = {}
    for _, cover in ipairs(covers) do
        cover_set[_parity_form(cover)] = true
    end
    position = _parity_form(position)
    local regions = _los_area(position, range, cover_set)
    for idx, region in ipairs(regions) do
        regions[idx] = _implicit_form(region)
    end
    return regions
end

local function info(position)
    local x, y = _grid_form(position)
    y = b0 * y
    local orientation = string.sub(_parity_form(position), 1, 1)
    local length = 2.^-(#position - 1)
    local neighbours = area(position, 1)
    table.remove(neighbours, 1)
    local vertices 
    if orientation == 0 then
        vertices = {
            {x, y + b0 * length * 2./3.}, 
            {x + 0.5 * length, y - b0 * length/3.},
            {x - 0.5 * length, y - b0 * length/3.}
        }
    else
        vertices = {
            {x, y - b0 * length * 2./3.}, 
            {x - 0.5 * length, y + b0 * length/3.},
            {x + 0.5 * length, y + b0 * length/3.}
        }        
    end
    return {
        id = position,
        centroid = {x, y},
        orientation = orientation,
        length = length,
        area = 0.25 * math.sqrt(3) * length * length,
        neighbours = neighbours,
        vertices = vertices,
        parent = string.sub(position, 1, -2),
        children = {position .. '0', position .. '1', position .. '2', position .. '3'}
    }
end

return {
    move = move,
    area = area,
    segment = segment,
    los = los,
    info = info
}
