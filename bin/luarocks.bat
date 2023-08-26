@echo off
setlocal
SET PROJECT_PATH=%~dp0..\
SET OPENSSL_PATH=E:\Program Files\Git\mingw64\bin
SET PATH=%PATH%;%OPENSSL_PATH%
call "%PROJECT_PATH%external\luarocks\install\luarocks.bat" %*