param([string]$GameDir = 'E:\SteamLibrary\steamapps\common\ACE COMBAT 8')
$ErrorActionPreference = 'Stop'
$projectRoot = $PSScriptRoot
$gameBin = Join-Path $GameDir 'Game\Binaries\Win64'
$gameExe = Join-Path $gameBin 'AceCombat8.exe'
$proxy = Join-Path $gameBin 'dwmapi.dll'
$runtime = Join-Path $gameBin 'ue4ss'
$package = Join-Path $projectRoot 'tools\ue4ss-package'
$marker = Join-Path $runtime 'AC8Chinese-project.txt'
if (-not (Test-Path -LiteralPath $gameExe)) { throw 'Game executable not found' }
if (Get-Process -Name AceCombat8 -ErrorAction SilentlyContinue) { throw 'Close the game first' }
if (Get-Process | Where-Object { $_.ProcessName -match 'EasyAntiCheat|start_protected_game' }) { throw 'Close the protected launcher and anti-cheat game session first' }
if (Test-Path -LiteralPath $proxy) { throw 'Existing dwmapi.dll detected; refusing to overwrite another loader' }
if ((Test-Path -LiteralPath $runtime) -and (-not (Test-Path -LiteralPath $marker))) { throw 'Existing UE4SS detected; refusing to overwrite another runtime' }
if ((Test-Path -LiteralPath $marker) -and ((Get-Content -LiteralPath $marker -Raw).Trim() -ne $projectRoot)) { throw 'Runtime belongs to a different project' }
if (Test-Path -LiteralPath (Join-Path $gameBin 'override.txt')) { throw 'Existing override.txt detected; inspect the loader configuration first' }
if (-not (Test-Path -LiteralPath (Join-Path $package 'ue4ss\UE4SS.dll'))) { throw 'Prepare the official UE4SS package in tools first' }
New-Item -ItemType Directory -Force -Path $runtime | Out-Null
Set-Content -LiteralPath $marker -Value $projectRoot -Encoding utf8
Copy-Item -LiteralPath (Join-Path $package 'ue4ss\UE4SS.dll') -Destination (Join-Path $runtime 'UE4SS.dll')
$settings = Get-Content -LiteralPath (Join-Path $package 'ue4ss\UE4SS-settings.ini') -Raw
$settings = $settings -replace '(?m)^MajorVersion =.*$', 'MajorVersion = 5'
$settings = $settings -replace '(?m)^MinorVersion =.*$', 'MinorVersion = 4'
Set-Content -LiteralPath (Join-Path $runtime 'UE4SS-settings.ini') -Value $settings -Encoding utf8
$mods = Join-Path $runtime 'Mods'
New-Item -ItemType Directory -Force -Path $mods | Out-Null
Copy-Item -LiteralPath (Join-Path $projectRoot 'mod\AC8Chinese') -Destination $mods -Recurse -Force
Set-Content -LiteralPath (Join-Path $mods 'mods.txt') -Value 'AC8Chinese : 1' -Encoding ascii
$proxyHash = (Get-FileHash -LiteralPath (Join-Path $package 'dwmapi.dll')).Hash
$priorApp = $env:SteamAppId
$priorGame = $env:SteamGameId
$priorNull = $env:EOS_USE_ANTICHEATCLIENTNULL
$appIdFile = Join-Path $gameBin 'steam_appid.txt'
$createdAppId = $false
if (Test-Path -LiteralPath $appIdFile) {
    if ((Get-Content -LiteralPath $appIdFile -Raw).Trim() -ne '2288340') { throw 'Existing Steam app identity does not match AC8' }
} else {
    Set-Content -LiteralPath $appIdFile -Value '2288340' -Encoding ascii
    $createdAppId = $true
}
try {
    Copy-Item -LiteralPath (Join-Path $package 'dwmapi.dll') -Destination $proxy
    $env:SteamAppId = '2288340'
    $env:SteamGameId = '2288340'
    $env:EOS_USE_ANTICHEATCLIENTNULL = '1'
    Write-Host 'Offline Chinese prototype. Keep this launcher open until the game exits.'
    $gameProcess = Start-Process -FilePath $gameExe -ArgumentList '-SaveToUserDir' -WorkingDirectory $gameBin -WindowStyle Normal -PassThru
    $gameProcess.WaitForExit()
    Write-Host "Owned game process exited with code $($gameProcess.ExitCode)."
} finally {
    $env:SteamAppId = $priorApp
    $env:SteamGameId = $priorGame
    $env:EOS_USE_ANTICHEATCLIENTNULL = $priorNull
    if ((Test-Path -LiteralPath $proxy) -and ((Get-FileHash -LiteralPath $proxy).Hash -eq $proxyHash)) {
        Remove-Item -LiteralPath $proxy
    }
    if ($createdAppId -and (Test-Path -LiteralPath $appIdFile) -and ((Get-Content -LiteralPath $appIdFile -Raw).Trim() -eq '2288340')) {
        Remove-Item -LiteralPath $appIdFile
    }
    $log = Join-Path $runtime 'UE4SS.log'
    if (Test-Path -LiteralPath $log) {
        New-Item -ItemType Directory -Force -Path (Join-Path $projectRoot 'work') | Out-Null
        Copy-Item -LiteralPath $log -Destination (Join-Path $projectRoot 'work\UE4SS-test.log') -Force
    }
}
