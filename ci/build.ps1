# Builds build\Lanternfall.exe and build\Lanternfall.apk, and their 3D twins
# build\Lanternfall-3D.exe and build\Lanternfall-3D.apk, with the self-contained
# Godot that ci\fetch-godot.ps1 prepared in -GodotDir. The twins are the same
# game started in the 3D view (their presets carry the "view3d" feature); the
# 3D APK has its own package name, so both install side by side.
#
# The APK is signed with the key in ANDROID_KEYSTORE_BASE64 (plus
# ANDROID_KEYSTORE_USER and ANDROID_KEYSTORE_PASSWORD) when those are set.
# Without them it is signed with a key made on the spot: it installs and runs,
# but cannot update a copy signed with a different key.
param(
	[Parameter(Mandatory = $true)][string]$GodotDir,
	[string]$AndroidSdk = $env:ANDROID_HOME,
	[string]$JavaHome = $env:JAVA_HOME,
	# Stamped into both builds when given, e.g. -VersionName 1.0.7 -VersionCode 7.
	# Android only accepts an update whose version code is higher than the installed one.
	[string]$VersionName = "",
	[int]$VersionCode = 0
)
$ErrorActionPreference = "Stop"

$repo = Split-Path -Parent $PSScriptRoot
$GodotDir = (Resolve-Path $GodotDir).Path
$godot = (Get-ChildItem $GodotDir -Filter "Godot_v*_console.exe" | Select-Object -First 1).FullName
if (-not $godot) { throw "No Godot console executable in $GodotDir" }
if (-not $AndroidSdk -or -not (Test-Path (Join-Path $AndroidSdk "platform-tools"))) { throw "Android SDK not found: '$AndroidSdk'" }
$keytool = Join-Path $JavaHome "bin\keytool.exe"
if (-not (Test-Path $keytool)) { throw "JDK not found: '$JavaHome'" }
$apksigner = (Get-ChildItem (Join-Path $AndroidSdk "build-tools") -Recurse -Filter "apksigner.bat" |
	Sort-Object FullName | Select-Object -Last 1).FullName

function Slash([string]$p) { $p.Replace("\", "/") }

function New-Keystore([string]$Path, [string]$Alias, [string]$Pass) {
	& $keytool -genkeypair -keyalg RSA -keysize 2048 -validity 10000 -storetype pkcs12 `
		-alias $Alias -keypass $Pass -storepass $Pass -keystore $Path -dname "CN=Lanternfall CI" 2>&1 | Out-Null
	if ($LASTEXITCODE -ne 0) { throw "keytool could not create $Path" }
}

# --- Tell this copy of Godot where the Android tools are -------------------------
# Keys live in a temporary folder, never in -GodotDir: that folder is cached.
# Safe save (write a .tmp, then rename it over the file) is off: on the CI runner
# a scanner can hold the fresh .tmp open, the rename fails and the export with it
# ("Safe save failed ... packtmp").
$work = Join-Path ([IO.Path]::GetTempPath()) "lanternfall-ci"
New-Item -ItemType Directory -Force $work, (Join-Path $GodotDir "editor_data") | Out-Null
$debugKey = Join-Path $work "debug.keystore"
if (-not (Test-Path $debugKey)) { New-Keystore $debugKey "androiddebugkey" "android" }
@"
[gd_resource type="EditorSettings" format=3]

[resource]
export/android/java_sdk_path = "$(Slash $JavaHome)"
export/android/android_sdk_path = "$(Slash $AndroidSdk)"
export/android/debug_keystore = "$(Slash $debugKey)"
export/android/debug_keystore_user = "androiddebugkey"
export/android/debug_keystore_pass = "android"
export/windows/rcedit = "$(Slash (Join-Path $GodotDir "rcedit-x64.exe"))"
filesystem/on_save/safe_save_on_backup_then_rename = false
"@ | Set-Content -Encoding utf8 (Join-Path $GodotDir "editor_data\editor_settings-4.3.tres")

# --- The key the APK is signed with ----------------------------------------------
$releaseKey = Join-Path $work "release.keystore"
if ($env:ANDROID_KEYSTORE_BASE64) {
	[IO.File]::WriteAllBytes($releaseKey, [Convert]::FromBase64String($env:ANDROID_KEYSTORE_BASE64))
	$env:GODOT_ANDROID_KEYSTORE_RELEASE_USER = $env:ANDROID_KEYSTORE_USER
	$env:GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD = $env:ANDROID_KEYSTORE_PASSWORD
	Write-Host "Signing the APK with the key from ANDROID_KEYSTORE_BASE64."
} else {
	Remove-Item $releaseKey -ErrorAction SilentlyContinue
	$pass = [Guid]::NewGuid().ToString("N")
	New-Keystore $releaseKey "lanternfall" $pass
	$env:GODOT_ANDROID_KEYSTORE_RELEASE_USER = "lanternfall"
	$env:GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD = $pass
	Write-Host "::warning::No signing key configured: this APK is signed with a throwaway key and cannot update an installed copy."
}
$env:GODOT_ANDROID_KEYSTORE_RELEASE_PATH = Slash $releaseKey

# --- Version numbers -------------------------------------------------------------
if ($VersionName) {
	$presets = Join-Path $repo "export_presets.cfg"
	$text = Get-Content $presets -Raw
	$text = $text -replace '(?m)^version/name=".*"$', "version/name=`"$VersionName`""
	if ($VersionCode -gt 0) { $text = $text -replace '(?m)^version/code=\d+$', "version/code=$VersionCode" }
	if ($VersionName -match '^\d+(\.\d+){0,3}$') {
		# Windows wants exactly four numbers.
		$four = (($VersionName.Split(".") + "0", "0", "0") | Select-Object -First 4) -join "."
		$text = $text -replace '(?m)^application/(file|product)_version=".*"$', "application/`$1_version=`"$four`""
	}
	Set-Content -Path $presets -Value $text -NoNewline -Encoding utf8
	Write-Host "Version $VersionName (code $VersionCode)"
}

# --- Check, then export ----------------------------------------------------------
function Invoke-Godot([string[]]$GodotArgs, [string]$What) {
	Write-Host "::group::$What"
	$out = & $godot --headless --path $repo @GodotArgs 2>&1 | ForEach-Object { "$_" }
	$code = $LASTEXITCODE
	$out | Where-Object { $_ -notmatch "^\s*(ADDING:|savepack: step|$)" } | ForEach-Object { Write-Host $_ }
	Write-Host "::endgroup::"
	if ($code -ne 0) { throw "$What failed (exit code $code)" }
	if ($out -match "SCRIPT ERROR|Parse Error|Failed to load script") { throw "$What reported script errors" }
}

$build = Join-Path $repo "build"
New-Item -ItemType Directory -Force $build | Out-Null
$exes = "Lanternfall.exe", "Lanternfall-3D.exe" | ForEach-Object { Join-Path $build $_ }
$apks = "Lanternfall.apk", "Lanternfall-3D.apk" | ForEach-Object { Join-Path $build $_ }
Remove-Item ($exes + $apks) -ErrorAction SilentlyContinue

Invoke-Godot @("--import") "Import the project"
Invoke-Godot @("--quit-after", "120") "Start the game and run it for 120 frames"
# Plays a little of depth 1 in each view and checks that parries, struck-back
# hexes and the lamp's oil do what they should; exits non-zero if not.
Invoke-Godot @("--", "--autotest", "--mechanics", "--2d") "Check the mechanics in the flat view"
Invoke-Godot @("--", "--autotest", "--mechanics", "--3d") "Check the mechanics in the 3D view"
# The fair-death and progression rules: mercy, resolve, embers, deeds, the
# town's lamps and the kindlings that combine.
Invoke-Godot @("--", "--autotest", "--progress", "--2d") "Check deaths, embers, the town and deeds (flat view)"
Invoke-Godot @("--", "--autotest", "--progress", "--3d") "Check deaths, embers, the town and deeds (3D view)"
# Oil and fire, the snuffed lamp, Wren's echo and the nemesis.
Invoke-Godot @("--", "--autotest", "--wild", "--2d") "Check oil, fire, the snuffed lamp, the echo and the nemesis (flat view)"
Invoke-Godot @("--", "--autotest", "--wild", "--3d") "Check oil, fire, the snuffed lamp, the echo and the nemesis (3D view)"
Invoke-Godot @("--export-release", "Windows Desktop", "build/Lanternfall.exe") "Export the Windows build"
Invoke-Godot @("--export-release", "Android", "build/Lanternfall.apk") "Export the Android build"
Invoke-Godot @("--export-release", "Windows Desktop 3D", "build/Lanternfall-3D.exe") "Export the Windows 3D build"
Invoke-Godot @("--export-release", "Android 3D", "build/Lanternfall-3D.apk") "Export the Android 3D build"

# Godot can report success without writing a usable file, so look at the results.
foreach ($f in $exes + $apks) {
	if (-not (Test-Path $f) -or (Get-Item $f).Length -lt 20MB) { throw "$f is missing or too small" }
}
foreach ($apk in $apks) {
	& $apksigner verify $apk
	if ($LASTEXITCODE -ne 0) { throw "The signature of $apk does not verify" }
}
Remove-Item (Join-Path $build "*.idsig"), $releaseKey -ErrorAction SilentlyContinue

Get-Item ($exes + $apks) | ForEach-Object { "{0,8:N1} MB  {1}" -f ($_.Length / 1MB), $_.Name }

# What the finished files say about themselves.
$aapt = Join-Path (Split-Path $apksigner) "aapt2.exe"
foreach ($apk in $apks) {
	(& $aapt dump badging $apk | Select-String "^package:").Line -replace " platformBuild.*", ""
}
foreach ($exe in $exes) {
	"{0}: version {1}" -f (Split-Path $exe -Leaf), (Get-Item $exe).VersionInfo.FileVersion
}
# The fingerprint of the key the APKs were signed with (public, safe to show).
(& $apksigner verify --print-certs $apks[0] | Select-String "SHA-256 digest").Line
