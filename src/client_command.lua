local function callback(loop, timer_event)
    print("client command")
end

return {
    callback = callback
}