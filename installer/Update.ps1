# SPDX-License-Identifier: GPL-3.0-only
# This module has no side effects when dot-sourced; the GUI calls Invoke-ModUpdate.
. (Join-Path $PSScriptRoot 'Common.ps1')
$UpdateRepo = 'harei-mu/AC8-Chinese-Mod'
function Release-Version([string]$Tag) {
    if ($Tag -notmatch '^v?(\d+)\.(\d+)\.(\d+)$') { throw '发布版本号格式不支持。' }
    return [Version]($Matches[1] + '.' + $Matches[2] + '.' + $Matches[3])
}
function Select-ReleasePackage($Release, [string]$CurrentVersion) {
    if ($Release.draft -or $Release.prerelease) { throw '更新只接受正式发布版本。' }
    $version = Release-Version $Release.tag_name
    if ($version -le (Release-Version $CurrentVersion)) { return $null }
    $name = 'AC8-Chinese-Mod-v' + $version.ToString(3) + '.zip'
    $assets = @($Release.assets | Where-Object { $_.name -ceq $name })
    if ($assets.Count -ne 1) { throw '新版本缺少唯一的安装包，请到项目发布页查看。' }
    $asset = $assets[0]
    $expectedUrl = 'https://github.com/' + $UpdateRepo + '/releases/download/' + $Release.tag_name + '/' + $name
    if ($asset.browser_download_url -cne $expectedUrl -or $asset.size -le 0 -or $asset.size -gt 209715200) { throw '更新下载地址或安装包大小异常。' }
    if ($asset.digest -notmatch '^sha256:([0-9a-fA-F]{64})$') { throw 'GitHub 尚未提供安装包校验值，请稍后再试。' }
    return @{version=$version.ToString(3);url=$expectedUrl;name=$name;size=[long]$asset.size;sha256=$Matches[1].ToUpperInvariant()}
}
function Expand-VerifiedPackage([string]$Zip, [string]$Destination, [string]$Version) {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    if (Test-Path -LiteralPath $Destination) { throw '更新解压目录必须是新目录。' }
    $archive = [IO.Compression.ZipFile]::OpenRead($Zip)
    try {
        if ($archive.Entries.Count -gt 1000) { throw '更新包包含过多文件。' }
        $plans = @(); $total = [long]0; $seen = @{}
        foreach ($entry in $archive.Entries) {
            $name = $entry.FullName.Replace('\','/')
            if (-not $name -or $name.StartsWith('/') -or $name.Contains(':') -or @($name.Split('/') | Where-Object { $_ -in @('.','..') }).Count) { throw '更新包包含非法路径。' }
            if (($entry.ExternalAttributes -shr 16 -band 61440) -eq 40960) { throw '更新包不允许包含符号链接。' }
            if ($name.EndsWith('/')) { continue }
            if ($seen.ContainsKey($name)) { throw '更新包包含重复路径。' }
            $seen[$name]=$true
            $total += $entry.Length
            if ($entry.Length -gt 209715200 -or $total -gt 536870912) { throw '更新包解压大小异常。' }
            $plans += @{entry=$entry;path=(Scoped-Path $Destination $name)}
        }
        New-Item -ItemType Directory -Path $Destination -Force | Out-Null
        foreach ($plan in $plans) {
            New-Parent $plan.path
            [IO.Compression.ZipFileExtensions]::ExtractToFile($plan.entry,$plan.path,$false)
        }
    } finally { $archive.Dispose() }
    $manifest = Verify-Package $Destination
    if ($manifest.version -cne $Version -or -not (Test-Path -LiteralPath (Join-Path $Destination '汉化安装器.exe'))) { throw '安装包版本与发布版本不一致。' }
    return $Destination
}
function Invoke-ModUpdate([string]$GameDir, [string]$Mode, [int]$InstallerPid, [switch]$CheckOnly) {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $ProgressPreference = 'SilentlyContinue'
    $current = (Read-JsonFile (Join-Path (Split-Path $PSScriptRoot -Parent) 'package-manifest.json')).version
    $statePath = Join-Path $GameDir 'Game\Binaries\Win64\AC8Chinese\install-state.json'
    if (Test-Path -LiteralPath $statePath) {
        $state = Read-JsonFile $statePath
        if ($state.owner -ne $ModOwner -or $state.gameDir -ne $GameDir) { throw '现有安装记录归属不明。' }
        $current = $state.version
        if ($state.mode -in @('UI','HUD','Both')) { $Mode = $state.mode }
    }
    try {
        $release = Invoke-RestMethod ('https://api.github.com/repos/' + $UpdateRepo + '/releases/latest') -Headers @{'User-Agent'='AC8-Chinese-Mod-Updater';Accept='application/vnd.github+json';'X-GitHub-Api-Version'='2026-03-10'} -TimeoutSec 30
    } catch { throw '无法检查 GitHub 更新。请检查网络；也可从项目 Releases 页面手动下载，现有安装不会改变。' }
    $package = Select-ReleasePackage $release $current
    if ($CheckOnly) { return $package }
    Add-Type -AssemblyName System.Windows.Forms
    if (-not $package) {
        [Windows.Forms.MessageBox]::Show('已经是最新正式版本：v' + $current, '检查更新', 'OK', 'Information') | Out-Null
        return 0
    }
    $question = '发现新版本 v' + $package.version + '。下载并安装吗？将保留当前汉化内容，Steam 无需重启。请先退出游戏。'
    if ([Windows.Forms.MessageBox]::Show($question, '检查更新', 'YesNo', 'Question') -ne 'Yes') { return 0 }
    Assert-GameClosed $GameDir
    $temp = Join-Path ([IO.Path]::GetTempPath()) ('AC8ChineseUpdate-' + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $temp -Force | Out-Null
    $zip = Scoped-Path $temp $package.name
    Invoke-WebRequest $package.url -OutFile $zip -UseBasicParsing -TimeoutSec 120
    if ((Get-Item -LiteralPath $zip).Length -ne $package.size -or (File-Hash $zip) -cne $package.sha256) { throw '更新安装包 SHA-256 校验失败，已停止安装。' }
    $newRoot = Expand-VerifiedPackage $zip (Scoped-Path $temp 'package') $package.version
    $exe = Join-Path $newRoot '汉化安装器.exe'
    # The new EXE waits for the old GUI to close before replacing installed files.
    $arguments = '--apply-update ' + $Mode + ' "' + $GameDir + '" ' + $InstallerPid
    Start-Process -FilePath $exe -ArgumentList $arguments -WorkingDirectory $newRoot | Out-Null
    return 10
}
