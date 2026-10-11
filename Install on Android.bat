@echo off
rem Installs build\Lanternfall.apk on a phone connected by USB and starts it.
rem The phone needs "USB debugging" switched on (Settings, Developer options).
rem Pass "emulator" to start the Android emulator and install the x86_64 build there instead.
setlocal
set SDK=D:\Ayan\Setup\Android\Sdk
set ADB=%SDK%\platform-tools\adb.exe
set APK=%~dp0build\Lanternfall.apk
if /i not "%~1"=="emulator" goto install

set ANDROID_AVD_HOME=D:\Ayan\Setup\Android\avd
set APK=%~dp0build\Lanternfall-x86_64.apk
start "" "%SDK%\emulator\emulator.exe" -avd lanternfall_test -gpu host
echo Waiting for the emulator to start...
"%ADB%" wait-for-device
:booting
for /f %%b in ('"%ADB%" shell getprop sys.boot_completed') do if "%%b"=="1" goto install
timeout /t 2 /nobreak >nul
goto booting

:install
if not exist "%APK%" (
	echo %APK% not found. Run "Build Android.bat" first.
	exit /b 1
)
"%ADB%" install -r "%APK%"
if errorlevel 1 (
	echo.
	echo Could not install. Is the phone connected, with USB debugging allowed?
	exit /b 1
)
"%ADB%" shell monkey -p com.ayansheikh.lanternfall -c android.intent.category.LAUNCHER 1 >nul 2>&1
echo Lanternfall is installed and running.
