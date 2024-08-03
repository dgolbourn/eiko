local config = require "config"
local zmq = require "lzmq"


ipc_context = zmq.context{io_threads = 1}

local command = ipc_context:socket{zmq.PAIR,
    connect = config.command.pair.authenticator
}

authenticator_verify_request = command:recv()
print(authenticator_verify_request)

command:send('{"_kind":"authenticator_verify_response","peername":"::1","id":"JaneBloggs83"}\n')
