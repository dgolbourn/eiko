local lu = require "luaunit"
local context = require "context"
local lanes = require "lanes"

Test = {}

function Test:test_remote()
    local verification_request = lanes.gen('*',
        function(url)
            local ltn12 = require 'ltn12'
            local https = require 'ssl.https'
            local parts = {}
            local status, code, headers = https.request {
                url = url,
                sink = ltn12.sink.table(parts)
            }
            print(status, code, headers)
            if code == 200 then
                local response = table.concat(parts)
                return response
            end
        end
    )
    print(verification_request("https://google.com")[1])
end

os.exit(lu.LuaUnit.run())
