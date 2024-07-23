local function callback(loop, timer_event)
    print("game loop")
end

return {
    callback = callback
}