param([string]$GameDir, [string]$PackageRoot = (Split-Path $PSScriptRoot -Parent),
    [ValidateSet('UI','HUD','Both')][string]$Mode, [string]$SteamDir, [switch]$NoShortcuts)
. (Join-Path $PSScriptRoot 'Common.ps1')
. (Join-Path $PSScriptRoot 'Steam.ps1')
$manifest = Verify-Package $PackageRoot
$GameDir = Resolve-Game $GameDir
Assert-GameClosed $GameDir
$gameBin = Join-Path $GameDir 'Game\Binaries\Win64'
if ((File-Hash (Join-Path $gameBin 'AceCombat8.exe')) -ne $SupportedExeHash) { throw '当前仅支持游戏 1.1.2.0 / Steam build 25201480。' }
if (-not $Mode) { . (Join-Path $PSScriptRoot 'Select-Mode.ps1'); $Mode = Select-InstallMode }
$appRoot = Scoped-Path $gameBin 'AC8Chinese'
$runtime = Scoped-Path $gameBin 'ue4ss'
$stateFile = Join-Path $appRoot 'install-state.json'
$prior = $null; $owned = @{}
if (Test-Path -LiteralPath $appRoot) {
    if (-not (Test-Path -LiteralPath $stateFile)) { throw 'AC8Chinese 文件夹已存在且归属不明，请勿覆盖。' }
    $prior = Read-JsonFile $stateFile
    if ($prior.owner -ne $ModOwner -or $prior.gameDir -ne $GameDir) { throw '已有安装记录不属于本汉化。' }
    foreach ($file in $prior.files) {
        $target = Owned-Path $gameBin $file.path
        $runtimeLog = $file.path -match '^(?:ue4ss\\UE4SS\.log|ue4ss\\Mods\\AC8OverrideLoader\\AC8OverrideLoader\.log|AC8Chinese\\Logs\\(?:launcher|text-table|UE4SS|AC8OverrideLoader)\.log)$'
        if ((Test-Path -LiteralPath $target) -and (File-Hash $target) -ne $file.sha256 -and -not $runtimeLog) { throw "已安装文件被修改，已保留：$($file.path)" }
        $owned[$file.path] = if ($runtimeLog -and (Test-Path -LiteralPath $target)) { File-Hash $target } else { $file.sha256 }
    }
    # Startup can be interrupted before its final log inventory is written.
    foreach ($name in @('launcher.log','text-table.log','UE4SS.log','AC8OverrideLoader.log')) {
        $relative = 'AC8Chinese\Logs\' + $name
        $target = Owned-Path $gameBin $relative
        if (Test-Path -LiteralPath $target -PathType Leaf) { $owned[$relative] = File-Hash $target }
    }
}
if (Test-Path -LiteralPath $runtime) {
    $marker = Scoped-Path $runtime 'AC8Chinese-project.txt'
    if (-not (Test-Path -LiteralPath $marker)) { throw '发现其他 UE4SS 安装，汉化不会覆盖它。' }
    $owner = (Get-Content -LiteralPath $marker -Raw -Encoding UTF8).Trim()
    if ($owner -ne $ModOwner -and $owner -ne $manifest.legacyOwner) { throw '现有 UE4SS 不属于本汉化项目。' }
    if (-not $prior -and $owner -eq $manifest.legacyOwner) {
        foreach ($file in @(Get-ChildItem -LiteralPath $runtime -File -Recurse -Force)) {
            $relative = $file.FullName.Substring($gameBin.Length + 1)
            $null = Owned-Path $gameBin $relative
            if ($relative -notmatch '^ue4ss\\(?:AC8Chinese-project\.txt|UE4SS(?:\.dll|\.log|-settings\.ini)|Mods\\mods\.txt|Mods\\AC8Chinese\\Scripts\\(?:main|translations|source-text|target-labels)\.lua|Mods\\AC8OverrideLoader\\(?:AC8Chinese-project\.txt|AC8OverrideLoader\.log|dlls\\main\.dll|disabled-payloads\\[^\\]+\\AC8ChineseMenuProbe_P\.(?:pak|ucas|utoc)|payloads\\0020_AC8ChineseHudFont\\AC8ChineseHudFont_P\.(?:pak|ucas|utoc)))$') { throw '旧测试目录中发现其他文件，请先处理 MOD 冲突。' }
            $owned[$relative] = File-Hash $file.FullName
        }
    }
}
foreach ($name in @('dwmapi.dll','override.txt')) {
    $existing = Scoped-Path $gameBin $name
    if (Test-Path -LiteralPath $existing) {
        # Only the exact proxy recorded by this installation may be retired.
        if ($name -eq 'dwmapi.dll' -and $prior -and $prior.owner -eq $ModOwner -and $prior.proxySha256 -and
            (File-Hash $existing) -eq $prior.proxySha256 -and
            (File-Hash $existing) -eq (File-Hash (Join-Path $PackageRoot 'Payload\dwmapi.dll'))) {
            Remove-Item -LiteralPath $existing
        } else { throw "发现已有 $name，请先退出汉化测试或处理 MOD 冲突。" }
    }
}
$plans = @()
foreach ($entry in $manifest.files) {
    $relative = 'AC8Chinese\' + $entry.path.Replace('/', '\')
    $target = Owned-Path $gameBin $relative
    if ((Test-Path -LiteralPath $target) -and -not $owned.ContainsKey($relative)) { throw "目标文件归属不明：$relative" }
    $plans += @{ source=(Scoped-Path $PackageRoot $entry.path); target=$target; relative=$relative; hash=$entry.sha256 }
    if ($entry.path.StartsWith('Payload/runtime/')) {
        $relative = 'ue4ss\' + $entry.path.Substring('Payload/runtime/'.Length).Replace('/', '\')
        $target = Owned-Path $gameBin $relative
        if ((Test-Path -LiteralPath $target) -and -not $owned.ContainsKey($relative)) { throw "运行文件归属不明：$relative" }
        $plans += @{ source=(Scoped-Path $PackageRoot $entry.path); target=$target; relative=$relative; hash=$entry.sha256 }
    }
}
$manifestPath = Join-Path $PackageRoot 'package-manifest.json'
$plans += @{ source=$manifestPath; target=(Owned-Path $gameBin 'AC8Chinese\package-manifest.json'); relative='AC8Chinese\package-manifest.json'; hash=(File-Hash $manifestPath) }
$steamRoot = Get-SteamRoot $SteamDir
$config = Get-SteamConfig $steamRoot
& {
    $currentOptions = Read-SteamOption $steamRoot $config
    $originalOptions = $currentOptions
    if ($prior -and $prior.steam) {
        $oldSteam = $prior.steam
        if ($oldSteam.root -ne $steamRoot -or $oldSteam.config -ne $config) { throw 'Steam 用户或位置发生变化，请先完全卸载旧安装。' }
        if ([string]$currentOptions -cne [string]$oldSteam.installedOptions -and [string]$currentOptions -cne [string]$oldSteam.originalOptions) { throw 'Steam 的启动设置已变更，已保留现有设置。' }
        $originalOptions = $oldSteam.originalOptions
    } elseif ($currentOptions -match '%command%|AC8Chinese') { throw 'Steam 已配置其他自定义启动器，请先处理冲突。' }
    $launchExe = Join-Path $appRoot '汉化安装器.exe'
    $newOptions = '"' + $launchExe + '" --steam-launch %command%'
    if ($originalOptions) { $newOptions += ' ' + $originalOptions }
    $state = @{ owner=$ModOwner; version=$manifest.version; gameDir=$GameDir; mode=$Mode; installedAt=(Get-Date).ToString('s');
        proxySha256=(File-Hash (Join-Path $PackageRoot 'Payload\dwmapi.dll')); originalArguments=[string]$originalOptions;
        appIdCreatedByMod=($prior -and $prior.appIdCreatedByMod);
        steam=@{root=$steamRoot;config=$config;originalOptions=$originalOptions;installedOptions=$newOptions;needsSetup=([string]$currentOptions -cne $newOptions)}; files=@(); shortcuts=@() }
    New-Item -ItemType Directory -Path $appRoot -Force | Out-Null
    $state.files = @($owned.GetEnumerator() | ForEach-Object { @{path=$_.Key;sha256=$_.Value} })
    Write-JsonFile $stateFile $state
    foreach ($plan in $plans) {
        New-Parent $plan.target
        if (-not (Test-Path -LiteralPath $plan.target) -or (File-Hash $plan.target) -ne $plan.hash) {
            Copy-Item -LiteralPath $plan.source -Destination $plan.target -Force
        }
        $owned[$plan.relative] = File-Hash $plan.target
        $state.files = @($owned.GetEnumerator() | ForEach-Object { @{path=$_.Key;sha256=$_.Value} })
        Write-JsonFile $stateFile $state
        if ($owned[$plan.relative] -ne $plan.hash) { throw '安装文件回读校验失败，请运行卸载后重试。' }
    }
    $marker = Scoped-Path $runtime 'AC8Chinese-project.txt'
    [IO.File]::WriteAllText($marker, $ModOwner, [Text.UTF8Encoding]::new($false))
    $owned['ue4ss\AC8Chinese-project.txt'] = File-Hash $marker
    $state.files = @($owned.GetEnumerator() | ForEach-Object { @{path=$_.Key;sha256=$_.Value} })
    Write-JsonFile $stateFile $state
    Write-Host '安装完成。Steam 进程和配置文件未作修改。'
    if ($state.steam.needsSetup) { Write-Host '首次使用请在安装器中复制 Steam 启动选项，并粘贴到游戏属性中。' }
    Write-Host '更换或解除汉化，请打开“汉化安装器.exe”。'
}
