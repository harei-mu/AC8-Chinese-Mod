param([string]$GameDir, [switch]$Full)
. (Join-Path $PSScriptRoot 'Common.ps1')
. (Join-Path $PSScriptRoot 'Steam.ps1')
$localState = Join-Path (Split-Path $PSScriptRoot -Parent) 'install-state.json'
if (-not $GameDir -and (Test-Path -LiteralPath $localState)) { $GameDir = (Read-JsonFile $localState).gameDir }
$GameDir = Resolve-Game $GameDir
Assert-GameClosed $GameDir
$gameBin = Join-Path $GameDir 'Game\Binaries\Win64'
$appRoot = Scoped-Path $gameBin 'AC8Chinese'
$stateFile = Join-Path $appRoot 'install-state.json'
if (-not (Test-Path -LiteralPath $stateFile)) { Write-Host '没有检测到本汉化的安装，无需卸载。'; return }
$state = Read-JsonFile $stateFile
if ($state.owner -ne $ModOwner -or $state.gameDir -ne $GameDir) { throw '安装记录归属不明，已停止卸载。' }
# Validate all removal paths before changing Steam or deleting any file.
foreach ($file in $state.files) { $null = Owned-Path $gameBin $file.path }
$keepEntry = -not $Full
    if ($state.steam) {
        $steamRoot = Get-SteamRoot $state.steam.root
        $current = Read-SteamOption $steamRoot $state.steam.config
        if ($Full -and $current -match 'AC8Chinese|--steam-launch') {
            throw '完全卸载前，请在 Steam 游戏属性中清除汉化启动选项，再点“完全卸载”。无需退出或重新启动 Steam。'
        }
    }
$preserved = @()
$retained = @()
foreach ($file in $state.files) {
    $target = Owned-Path $gameBin $file.path
    if (Test-Path -LiteralPath $target -PathType Leaf) {
        if ($keepEntry -and $file.path -eq 'AC8Chinese\汉化安装器.exe') { $retained += $file }
        elseif ((File-Hash $target) -eq $file.sha256) { Remove-Item -LiteralPath $target }
        else { $preserved += $file.path }
    }
}
foreach ($shortcut in $state.shortcuts) {
    $desktop = [Environment]::GetFolderPath('Desktop').TrimEnd('\') + '\'
    $resolved = [IO.Path]::GetFullPath($shortcut.path)
    if (-not $resolved.StartsWith($desktop, [StringComparison]::OrdinalIgnoreCase)) { throw '快捷方式位置不属于桌面。' }
    if (Test-Path -LiteralPath $resolved) {
        if ((File-Hash $resolved) -eq $shortcut.sha256) { Remove-Item -LiteralPath $resolved }
        else { $preserved += $resolved }
    }
}
$proxy = Scoped-Path $gameBin 'dwmapi.dll'
$proxyHash = $state.proxySha256
if (-not $proxyHash) { $proxyHash = 'E0-NONE' }
if ((Test-Path -LiteralPath $proxy) -and (File-Hash $proxy) -eq $proxyHash) { Remove-Item -LiteralPath $proxy }
$appId = Scoped-Path $gameBin 'steam_appid.txt'
if ($state.appIdCreatedByMod -and (Test-Path -LiteralPath $appId) -and [IO.File]::ReadAllText($appId) -eq '2288340') { Remove-Item -LiteralPath $appId }
if ($preserved.Count -eq 0 -and -not $keepEntry) {
    Remove-Item -LiteralPath $stateFile
} else {
    $state.mode = 'None'
    $state.files = @($retained) + @($state.files | Where-Object { $preserved -contains $_.path })
    $state.shortcuts = @($state.shortcuts | Where-Object { $preserved -contains $_.path })
    Write-JsonFile $stateFile $state
}
foreach ($directory in @($appRoot, (Scoped-Path $gameBin 'ue4ss'))) {
    Remove-EmptyDirectories $directory
    if ((Test-Path -LiteralPath $directory) -and @(Get-ChildItem -LiteralPath $directory -Force).Count -eq 0) { Remove-Item -LiteralPath $directory }
}
Write-Host '汉化已解除，游戏恢复原文。Steam 进程和配置文件未作修改。'
if ($keepEntry) { Write-Host '仅保留 Steam 兼容入口和安装记录；可清除启动选项后选择完全卸载。' }
if ($preserved.Count) { Write-Host ('已保留安装后被修改的文件：' + ($preserved -join '、')) }
