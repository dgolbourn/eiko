local socket = require "socket"

local function event()
    local state = {
        receiver_watchers = {},
        timer_watchers = {}
    }

    local function unloop()
        state._loop = nil
    end

    local function loop()
        state._loop = true
        while state._loop do
            local socks = {}
            for sock, _ in pairs(state.receiver_watchers) do
            table.insert(socks, sock)
            end
            local canread = socket.select(socks, nil, 1)
            for _, sock in ipairs(canread) do
                state.receiver_watchers[sock]._callback()
            end
            local now = os.time()
            for _, timer in pairs(state.timer_watchers) do
                if timer.now <= now then
                    timer._callback()
                    timer.stop()
                end
            end
        end
    end

    local function receiver(sock, callback)
        local receiver = {}
        receiver.sock = sock
        receiver._callback = callback
        receiver.start = function()
            state.receiver_watchers[receiver.sock] = receiver
        end
        receiver.stop = function()
            state.receiver_watchers[receiver.sock] = nil
        end
        receiver.callback = function(callback)
            receiver._callback = callback
        end
        return receiver
    end

    local function timer(seconds, callback)
        local timer = {}
        timer.seconds = seconds
        timer._callback = callback
        timer.start = function()
            timer.index = #state.timer_watchers + 1
            timer.now = os.time() + seconds
            state.timer_watchers[timer.index] = timer
        end
        timer.stop = function()
            state.timer_watchers[timer.index] = nil
        end
        timer.callback = function(callback)
            timer._callback = callback
        end
        return timer
    end

    return {
        loop = loop,
        receiver = receiver,
        timer = timer,
        unloop = unloop
    }
end

return {
    event = event
}
