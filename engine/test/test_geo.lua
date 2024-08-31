local lu = require "luaunit"

Test = {}

function Test:test_geo()
    local geo = require "eiko-engine.geo"
    lu.assertEquals('002', geo.move('000', 10))
    lu.assertEquals('003', geo.move('000', 2))
    lu.assertEquals('001', geo.move('000', 6))
    lu.assertEquals('0101', geo.move('0123', 10))
end

function Test:test_major()
    local geo = require "eiko-engine.geo"
    print(geo.move('0', 12))
    print(geo.move('0', 2))
    print(geo.move('0', 10))
    print(geo.move('0', 6))
    print(geo.move('0', 8))
    print(geo.move('0', 4))
end

function Test:test_area()
    local geo = require "eiko-engine.geo"
    local area = geo.area('00000',3)
    -- for _, position in ipairs(area) do
    --     print(position)
    -- end
    -- print(#area)
end

function Test:test_segment()
    local geo = require "eiko-engine.geo"
    local positions = geo.segment('6102003000','0010100000')
    -- for _, position in ipairs(positions) do
    --     print(position)
    -- end
end

function Test:test_los()
    local geo = require "eiko-engine.geo"
    local area = geo.los('00000',3, {'00001'})
    -- for _, position in ipairs(area) do
    --     print(position)
    -- end
    -- print(#area)
end

function Test:test_info()
    local geo = require "eiko-engine.geo"
    local cjson = require "cjson"
    local info = geo.info('0')
    --print(cjson.encode(info))
end

os.exit(lu.LuaUnit.run())
