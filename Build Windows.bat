@echo off
rem Builds build\Lanternfall.exe: the whole game in one file, no Godot needed to run it.
setlocal
set GODOT=D:\Ayan\Setup\Godot_v4.3-stable_win64.exe\Godot_v4.3-stable_win64_console.exe
if not exist "%~dp0build" mkdir "%~dp0build"
"%GODOT%" --headless --path "%~dp0." --export-release "Windows Desktop" "build/Lanternfall.exe"
if errorlevel 1 exit /b 1
echo.
echo Built build/Lanternfall.exe
