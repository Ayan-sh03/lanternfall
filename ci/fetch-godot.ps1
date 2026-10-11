# Downloads a self-contained Godot editor, the export templates this project
# needs, and rcedit (which stamps the icon into the Windows .exe) into -Dest.
# The folder is cached between CI runs, so this only runs when the cache is cold.
param(
	[string]$Version = "4.3-stable",
	[Parameter(Mandatory = $true)][string]$Dest
)
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"
Add-Type -AssemblyName System.IO.Compression.FileSystem

$base = "https://github.com/godotengine/godot/releases/download/$Version"
$templateDir = Join-Path $Dest ("editor_data\export_templates\" + $Version.Replace("-", "."))
New-Item -ItemType Directory -Force $Dest, $templateDir | Out-Null

function Get-File([string]$Url, [string]$Out) {
	Write-Host "Downloading $Url"
	curl.exe --location --fail --silent --show-error --retry 5 --retry-delay 5 --output $Out $Url
	if ($LASTEXITCODE -ne 0) { throw "Download failed: $Url" }
}

# The editor. A file named ._sc_ beside it makes Godot keep its settings and
# templates in .\editor_data instead of the user profile.
$zip = Join-Path $Dest "godot.zip"
Get-File "$base/Godot_v${Version}_win64.exe.zip" $zip
[System.IO.Compression.ZipFile]::ExtractToDirectory($zip, $Dest)
Remove-Item $zip
New-Item -ItemType File -Force (Join-Path $Dest "._sc_") | Out-Null

# The template archive is about 1 GB; only three files in it are needed.
$tpz = Join-Path $Dest "templates.tpz"
Get-File "$base/Godot_v${Version}_export_templates.tpz" $tpz
$want = "version.txt", "windows_release_x86_64.exe", "android_release.apk", "android_debug.apk"
$archive = [System.IO.Compression.ZipFile]::OpenRead($tpz)
try {
	foreach ($name in $want) {
		$entry = $archive.GetEntry("templates/$name")
		if ($null -eq $entry) { throw "templates/$name is missing from the template archive" }
		[System.IO.Compression.ZipFileExtensions]::ExtractToFile($entry, (Join-Path $templateDir $name), $true)
	}
} finally {
	$archive.Dispose()
}
Remove-Item $tpz

Get-File "https://github.com/electron/rcedit/releases/download/v2.0.0/rcedit-x64.exe" (Join-Path $Dest "rcedit-x64.exe")

Get-ChildItem $Dest -Recurse -File | ForEach-Object { "{0,8:N1} MB  {1}" -f ($_.Length / 1MB), $_.FullName.Substring($Dest.Length + 1) }
