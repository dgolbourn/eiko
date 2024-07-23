local function callback(loop, timer_event)
    print("server event")
end

return {
    callback = callback
}