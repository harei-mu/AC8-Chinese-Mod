param(
    [string]$GameDir = 'E:\SteamLibrary\steamapps\common\ACE COMBAT 8',
    [switch]$ResourceProbe,
    [switch]$NativeTable,
    [switch]$HudFont,
    [string]$PythonExe = 'C:\Users\reimu\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe'
)
$ErrorActionPreference = 'Stop'
$projectRoot = $PSScriptRoot
$gameBin = Join-Path $GameDir 'Game\Binaries\Win64'
$gameExe = Join-Path $gameBin 'AceCombat8.exe'
$proxy = Join-Path $gameBin 'dwmapi.dll'
$runtime = Join-Path $gameBin 'ue4ss'
$package = Join-Path $projectRoot 'tools\ue4ss-package'
$marker = Join-Path $runtime 'AC8Chinese-project.txt'
if ($ResourceProbe -and $NativeTable) { throw 'Choose one test mode' }
if ($HudFont -and (-not $NativeTable)) { throw 'HUD font mode requires NativeTable' }
if ($NativeTable -and (-not (Test-Path -LiteralPath $PythonExe))) { throw 'Native table mode requires PythonExe' }
if (-not (Test-Path -LiteralPath $gameExe)) { throw 'Game executable not found' }
if (Get-Process -Name AceCombat8 -ErrorAction SilentlyContinue) { throw 'Close the game first' }
if (Get-Process | Where-Object { $_.ProcessName -match 'EasyAntiCheat|start_protected_game' }) { throw 'Close the protected launcher and anti-cheat game session first' }
if (Test-Path -LiteralPath $proxy) { throw 'Existing dwmapi.dll detected; refusing to overwrite another loader' }
if ((Test-Path -LiteralPath $runtime) -and (-not (Test-Path -LiteralPath $marker))) { throw 'Existing UE4SS detected; refusing to overwrite another runtime' }
if ((Test-Path -LiteralPath $marker) -and ((Get-Content -LiteralPath $marker -Raw).Trim() -ne $projectRoot)) { throw 'Runtime belongs to a different project' }
if (Test-Path -LiteralPath (Join-Path $gameBin 'override.txt')) { throw 'Existing override.txt detected; inspect the loader configuration first' }
if (-not (Test-Path -LiteralPath (Join-Path $package 'ue4ss\UE4SS.dll'))) { throw 'Prepare the official UE4SS package in tools first' }
$resourceLoader = Join-Path $projectRoot 'tools\ac8-override-loader\main.dll'
$resourcePayload = Join-Path $projectRoot 'dist\resource-probe'
$payloadBase = 'AC8ChineseMenuProbe_P'
$payloadSubdir = '0010_AC8ChineseMenuProbe'
$resourceReport = 'reports\resource-probe.json'
if ($HudFont) {
    $resourcePayload = Join-Path $projectRoot 'dist\hud-font'
    $payloadBase = 'AC8ChineseHudFont_P'
    $payloadSubdir = '0020_AC8ChineseHudFont'
    $resourceReport = 'reports\hud-font.json'
}
$loaderDir = Join-Path $runtime 'Mods\AC8OverrideLoader'
$loaderMarker = Join-Path $loaderDir 'AC8Chinese-project.txt'
if ((Test-Path -LiteralPath $loaderDir) -and ((-not (Test-Path -LiteralPath $loaderMarker)) -or ((Get-Content -LiteralPath $loaderMarker -Raw).Trim() -ne $projectRoot))) {
    throw 'Existing resource loader belongs to another installation; refusing to overwrite'
}
if ($ResourceProbe -or $HudFont) {
    if (-not (Test-Path -LiteralPath $resourceLoader)) { throw 'Prepare the fixed AC8OverrideLoader version first' }
    if ((Get-FileHash -LiteralPath $resourceLoader).Hash -ne '225C8D6C3FBF5E8882CB8E334DBD3426CB24A1415B3585073CC4264AE834F851') { throw 'Resource loader hash mismatch' }
    $manifest = Get-Content -LiteralPath (Join-Path $projectRoot $resourceReport) -Raw | ConvertFrom-Json
    if ($HudFont -and (-not $manifest.containerVerified -or -not $manifest.exportPayloadRoundtripExact)) { throw 'HUD font container has not passed readback verification' }
    foreach ($extension in @('utoc', 'ucas', 'pak')) {
        $payloadFile = Join-Path $resourcePayload ($payloadBase + '.' + $extension)
        if ((Get-FileHash -LiteralPath $payloadFile).Hash -ne $manifest.files.$extension.sha256) { throw "Resource payload $extension hash mismatch" }
    }
}
New-Item -ItemType Directory -Force -Path $runtime | Out-Null
Set-Content -LiteralPath $marker -Value $projectRoot -Encoding utf8
Copy-Item -LiteralPath (Join-Path $package 'ue4ss\UE4SS.dll') -Destination (Join-Path $runtime 'UE4SS.dll')
$settings = Get-Content -LiteralPath (Join-Path $package 'ue4ss\UE4SS-settings.ini') -Raw
$settings = $settings -replace '(?m)^MajorVersion =.*$', 'MajorVersion = 5'
$settings = $settings -replace '(?m)^MinorVersion =.*$', 'MinorVersion = 4'
$settings = $settings -replace '(?m)^EnableAutoReloadingLuaMods =.*$', 'EnableAutoReloadingLuaMods = 1'
Set-Content -LiteralPath (Join-Path $runtime 'UE4SS-settings.ini') -Value $settings -Encoding utf8
$mods = Join-Path $runtime 'Mods'
New-Item -ItemType Directory -Force -Path $mods | Out-Null
Copy-Item -LiteralPath (Join-Path $projectRoot 'mod\AC8Chinese') -Destination $mods -Recurse -Force
if ($NativeTable -and (-not $HudFont)) {
    Set-Content -LiteralPath (Join-Path $mods 'mods.txt') -Value "AC8Chinese : 0`r`nAC8OverrideLoader : 0" -Encoding ascii
} elseif ($ResourceProbe -or $HudFont) {
    $dllDir = Join-Path $loaderDir 'dlls'
    $payloadDir = Join-Path $loaderDir ('payloads\' + $payloadSubdir)
    # Retire this project's failed DAT probe before the font test; preserve it for diagnosis.
    $priorProbe = Join-Path $loaderDir 'payloads\0010_AC8ChineseMenuProbe'
    if ($HudFont -and (Test-Path -LiteralPath $priorProbe)) {
        $probeReport = Get-Content -LiteralPath (Join-Path $projectRoot 'reports\resource-probe.json') -Raw | ConvertFrom-Json
        $probeFiles = @(Get-ChildItem -LiteralPath $priorProbe -File)
        if ($probeFiles.Count -ne 3) { throw 'Unexpected files in prior probe; inspect manually' }
        foreach ($extension in @('utoc', 'ucas', 'pak')) {
            if ((Get-FileHash -LiteralPath (Join-Path $priorProbe ('AC8ChineseMenuProbe_P.' + $extension))).Hash -ne $probeReport.files.$extension.sha256) { throw 'Prior probe ownership hash mismatch' }
        }
        $archiveRoot = Join-Path $loaderDir 'disabled-payloads'
        $archivePath = Join-Path $archiveRoot ('menu-probe-' + (Get-Date -Format 'yyyyMMddHHmmss'))
        $ownedRoot = [IO.Path]::GetFullPath($loaderDir).TrimEnd('\') + '\'
        foreach ($checkedPath in @($priorProbe, $archivePath)) {
            if (-not [IO.Path]::GetFullPath($checkedPath).StartsWith($ownedRoot, [StringComparison]::OrdinalIgnoreCase)) { throw 'Payload path escaped owned loader directory' }
        }
        New-Item -ItemType Directory -Path $archiveRoot -Force | Out-Null
        Move-Item -LiteralPath $priorProbe -Destination $archivePath
    }
    New-Item -ItemType Directory -Path $dllDir, $payloadDir -Force | Out-Null
    Set-Content -LiteralPath $loaderMarker -Value $projectRoot -Encoding utf8
    Copy-Item -LiteralPath $resourceLoader -Destination (Join-Path $dllDir 'main.dll') -Force
    foreach ($extension in @('utoc', 'ucas', 'pak')) {
        Copy-Item -LiteralPath (Join-Path $resourcePayload ($payloadBase + '.' + $extension)) -Destination $payloadDir -Force
    }
    Set-Content -LiteralPath (Join-Path $mods 'mods.txt') -Value "AC8Chinese : 0`r`nAC8OverrideLoader : 1" -Encoding ascii
} else {
    Set-Content -LiteralPath (Join-Path $mods 'mods.txt') -Value "AC8Chinese : 1`r`nAC8OverrideLoader : 0" -Encoding ascii
}
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
    if (-not $NativeTable -or $HudFont) { Copy-Item -LiteralPath (Join-Path $package 'dwmapi.dll') -Destination $proxy }
    $env:SteamAppId = '2288340'
    $env:SteamGameId = '2288340'
    $env:EOS_USE_ANTICHEATCLIENTNULL = '1'
    Write-Host "Offline Chinese prototype (ResourceProbe=$ResourceProbe, NativeTable=$NativeTable, HudFont=$HudFont). Keep this launcher open until the game exits."
    $gameProcess = Start-Process -FilePath $gameExe -ArgumentList '-SaveToUserDir' -WorkingDirectory $gameBin -WindowStyle Normal -PassThru
    if ($NativeTable) {
        $patchArguments = @($gameProcess.Id, '--wait', '30', '--apply')
        if ($HudFont) { $patchArguments += '--hud' }
        & $PythonExe (Join-Path $projectRoot 'scripts\patch-loaded-text.py') @patchArguments
        if ($LASTEXITCODE -ne 0) { Write-Warning 'Text table patch failed; consult work logs. The game remains unmodified for unmatched entries.' }
    }
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
    $resourceLog = Join-Path $loaderDir 'AC8OverrideLoader.log'
    if (($ResourceProbe -or $HudFont) -and (Test-Path -LiteralPath $resourceLog)) {
        $logName = if ($HudFont) { 'hud-font-loader.log' } else { 'resource-probe-loader.log' }
        Copy-Item -LiteralPath $resourceLog -Destination (Join-Path $projectRoot ('work\' + $logName)) -Force
    }
}
