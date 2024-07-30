
local zmq = require "lzmq"
local ev = require "ev"

local state = {}

state.subscriber = zmq.context():socket{zmq.SUB,
        subscribe = '',
        connect = "ipc://waa"
}

local function on_io_event(loop, io, revents)
    state.idle_watcher:start(ev.Loop.default)
    state.io_watcher:stop(ev.Loop.default)
end
state.io_watcher = ev.IO.new(on_io_event, state.subscriber:get_fd(), ev.READ)

local function on_idle_event(loop, idle, revents)
    if state.subscriber:has_event(zmq.POLLIN) then
        local msg, err = state.subscriber:recv(zmq.NOBLOCK)
        if msg then
            print(msg)
        elseif err:no() == zmq.errors.EAGAIN then
        else
            print(msg, err)
        end
    else 
        state.idle_watcher:stop(ev.Loop.default)
        state.io_watcher:start(ev.Loop.default)
    end
end
state.idle_watcher = ev.Idle.new(on_idle_event)

state.io_watcher:start(ev.Loop.default)

ev.Loop.default:loop()
