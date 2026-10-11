@echo off
rem Builds build\Lanternfall.apk: a signed release for 64-bit ARM phones and tablets.
rem Pass "emulator" to build build\Lanternfall-x86_64.apk for the Android emulator instead.
setlocal
set GODOT=D:\Ayan\Setup\Godot_v4.3-stable_win64.exe\Godot_v4.3-stable_win64_console.exe
set KEYS=D:\Ayan\Setup\Android\keys\lanternfall-release.properties
if not exist "%KEYS%" (
	echo Signing key not found: %KEYS%
	exit /b 1
)
for /f "usebackq tokens=1,* delims==" %%a in ("%KEYS%") do set KS_%%a=%%b
set GODOT_ANDROID_KEYSTORE_RELEASE_PATH=%KS_keystore%
set GODOT_ANDROID_KEYSTORE_RELEASE_USER=%KS_alias%
set GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD=%KS_password%
set PRESET=Android
set OUT=build/Lanternfall.apk
if /i "%~1"=="emulator" (
	set PRESET=Android emulator
	set OUT=build/Lanternfall-x86_64.apk
)
if not exist "%~dp0build" mkdir "%~dp0build"
"%GODOT%" --headless --path "%~dp0." --export-release "%PRESET%" "%OUT%"
if errorlevel 1 exit /b 1
echo.
echo Built %OUT%
