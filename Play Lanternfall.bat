@echo off
rem Launches Lanternfall with the portable Godot 4.3 on this machine.
set "GODOT=D:\Ayan\Setup\Godot_v4.3-stable_win64.exe\Godot_v4.3-stable_win64.exe"
if not exist "%GODOT%" (
	echo Could not find Godot at:
	echo   %GODOT%
	echo Edit this file and point GODOT at your Godot 4.3+ executable.
	pause
	exit /b 1
)
start "" "%GODOT%" --path "%~dp0."
