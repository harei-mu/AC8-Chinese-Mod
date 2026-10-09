param([string]$GameDir)
. (Join-Path $PSScriptRoot 'Common.ps1')
$appRoot = Split-Path $PSScriptRoot -Parent
$sessionLock = $null
$gameProcess = $null
$createdAppId = $false
$priorApp = $env:SteamAppId; $priorGame = $env:SteamGameId; $priorNull = $env:EOS_USE_ANTICHEATCLIENTNULL
try {
    $stateFile = Join-Path $appRoot 'install-state.json'
    if (-not (Test-Path -LiteralPath $stateFile)) {
        $GameDir = Resolve-Game $GameDir
        $installedScript = Join-Path $GameDir 'Game\Binaries\Win64\AC8Chinese\App\Start-Chinese.ps1'
        if (-not (Test-Path -LiteralPath $installedScript)) { throw '请先双击“汉化安装器.exe”。' }
        Start-Process -FilePath (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe') -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -File "' + $installedScript + '"') -WindowStyle Hidden
        exit 0
    }
    $state = Read-JsonFile $stateFile
    if ($state.owner -ne $ModOwner) { throw '安装记录归属不明。' }
    $GameDir = Resolve-Game $state.gameDir
    $manifest = Verify-Package $appRoot
    Assert-Offline
    if (Get-Process -Name AceCombat8 -ErrorAction SilentlyContinue) { throw '游戏已在运行，请正常退出后再使用汉化入口。' }
    $gameBin = Join-Path $GameDir 'Game\Binaries\Win64'
    $exe = Join-Path $gameBin 'AceCombat8.exe'
    if ((File-Hash $exe) -ne $SupportedExeHash) { throw '游戏版本已变更，请更新汉化包。' }
    foreach ($entry in $manifest.files | Where-Object { $_.path.StartsWith('Payload/runtime/') }) {
        $target = Scoped-Path (Join-Path $gameBin 'ue4ss') $entry.path.Substring('Payload/runtime/'.Length)
        if (-not (Test-Path -LiteralPath $target) -or (File-Hash $target) -ne $entry.sha256) { throw '汉化运行文件已变更，请重新安装。' }
    }
    if (Test-Path -LiteralPath (Join-Path $gameBin 'override.txt')) { throw '发现其他加载器配置，请先处理冲突。' }
    $sessionLock = [IO.File]::Open((Join-Path $appRoot 'session.lock'), [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
    $logs = Join-Path $appRoot 'Logs'
    New-Item -ItemType Directory -Path $logs -Force | Out-Null
    $launchLog = Join-Path $logs 'launcher.log'
    function Write-LaunchEvent([string]$Message) {
        [IO.File]::AppendAllText($launchLog, (Get-Date).ToString('s') + ' ' + $Message + "`r`n", [Text.UTF8Encoding]::new($false))
    }
    Write-LaunchEvent ('Start; mode=' + $state.mode)
    # The helper runs in PowerShell, not inside the game. Compile it when
    # packaging so Steam never launches a compiler during game startup.
    Add-Type -Path (Join-Path $PSScriptRoot 'AC8TextTables.dll')
    Write-LaunchEvent 'Text helper loaded'
    $proxy = Scoped-Path $gameBin 'dwmapi.dll'
    $proxySource = Join-Path $appRoot 'Payload\dwmapi.dll'
    $proxyHash = File-Hash $proxySource
    if ((Test-Path -LiteralPath $proxy) -and (File-Hash $proxy) -ne $proxyHash) { throw '发现其他 MOD 的加载代理，汉化不会覆盖它。' }
    $appIdFile = Scoped-Path $gameBin 'steam_appid.txt'
    if (Test-Path -LiteralPath $appIdFile) {
        if ((Get-Content -LiteralPath $appIdFile -Raw).Trim() -ne '2288340') { throw '现有 Steam appid 与游戏不符。' }
    } else {
        [IO.File]::WriteAllText($appIdFile, '2288340'); $createdAppId = $true
        $state | Add-Member -NotePropertyName appIdCreatedByMod -NotePropertyValue $true -Force
        Write-JsonFile $stateFile $state
    }
    if ($state.mode -ne 'UI') { Copy-Item -LiteralPath $proxySource -Destination $proxy -Force }
    $env:SteamAppId = '2288340'; $env:SteamGameId = '2288340'; $env:EOS_USE_ANTICHEATCLIENTNULL = '1'
    $arguments = '-SaveToUserDir'
    if ($state.originalArguments) { $arguments += ' ' + $state.originalArguments }
    $gameProcess = Start-Process -FilePath $exe -ArgumentList $arguments -WorkingDirectory $gameBin -WindowStyle Normal -PassThru
    Write-LaunchEvent ('Game PID=' + $gameProcess.Id)
    & (Join-Path $PSScriptRoot 'Patch-Text.ps1') -GamePid $gameProcess.Id -Mode $state.mode *> (Join-Path $logs 'text-table.log')
    Write-LaunchEvent 'Text tables patched and read back'
    $gameProcess.WaitForExit()
    Write-LaunchEvent ('Game exit=' + $gameProcess.ExitCode)
} catch {
    $global:LASTEXITCODE = 1
    [Environment]::ExitCode = 1
    if ($launchLog) { [IO.File]::AppendAllText($launchLog, $_.ToString() + "`r`n" + $_.ScriptStackTrace + "`r`n") }
    Add-Type -AssemblyName System.Windows.Forms
    [Windows.Forms.MessageBox]::Show($_.Exception.Message, 'ACE COMBAT 8 单机汉化', 'OK', 'Error') | Out-Null
    if ($gameProcess -and (-not $gameProcess.HasExited)) { $gameProcess.WaitForExit() }
} finally {
    $env:SteamAppId=$priorApp; $env:SteamGameId=$priorGame; $env:EOS_USE_ANTICHEATCLIENTNULL=$priorNull
    if ($proxy -and (Test-Path -LiteralPath $proxy) -and (File-Hash $proxy) -eq $proxyHash) { Remove-Item -LiteralPath $proxy }
    if (($createdAppId -or $state.appIdCreatedByMod) -and $appIdFile -and (Test-Path -LiteralPath $appIdFile) -and (Get-Content -LiteralPath $appIdFile -Raw).Trim() -eq '2288340') { Remove-Item -LiteralPath $appIdFile }
    if ($sessionLock) { $sessionLock.Dispose(); Remove-Item -LiteralPath (Join-Path $appRoot 'session.lock') }
    if ($logs -and (Test-Path -LiteralPath $stateFile)) {
        $state = Read-JsonFile $stateFile
        $newFiles = @{}
        foreach ($file in $state.files) { $newFiles[$file.path] = $file.sha256 }
        foreach ($source in @('ue4ss\UE4SS.log', 'ue4ss\Mods\AC8OverrideLoader\AC8OverrideLoader.log')) {
            $file = Scoped-Path $gameBin $source
            if (Test-Path -LiteralPath $file) {
                Copy-Item -LiteralPath $file -Destination (Join-Path $logs ([IO.Path]::GetFileName($file))) -Force
                $newFiles[$source] = File-Hash $file
            }
        }
        foreach ($file in @(Get-ChildItem -LiteralPath $logs -File)) { $newFiles['AC8Chinese\Logs\' + $file.Name] = File-Hash $file.FullName }
        $state.files = @($newFiles.GetEnumerator() | ForEach-Object { @{path=$_.Key;sha256=$_.Value} })
        Write-JsonFile $stateFile $state
    }
}
