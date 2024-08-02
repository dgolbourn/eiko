local lu = require "luaunit"
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
            return{status=status, code=code, headers=header, body=table.concat(parts)}
        end
    )
    local response, err = verification_request("https://www.google.com"):join()
    lu.assertEquals(response.code, 200)
end

os.exit(lu.LuaUnit.run())
