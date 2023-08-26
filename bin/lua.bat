@echo off
setlocal
SET PROJECT_PATH=%~dp0..\
SET LUA_PATH=%LUA_PATH%;%PROJECT_PATH%src\?.lua
SET PATH=%PATH%;%PROJECT_PATH%external\luarocks\install\systree\bin
SET LUA_PATH=%LUA_PATH%;%PROJECT_PATH%external\luarocks\install\systree\share\lua\5.1\?.lua;D:\Users\golbo\OneDrive\Documents\GitHub\ladymarigold\external\luarocks\install\systree\share\lua\5.1\?\init.lua
SET LUA_CPATH=%LUA_CPATH%;%PROJECT_PATH%external\luarocks\install\systree\lib\lua\5.1\?.dll
call "%PROJECT_PATH%external\luajit\src\luajit.exe" %*