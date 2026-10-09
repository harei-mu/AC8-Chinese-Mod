param([Parameter(Mandatory)][ValidateSet('Install','Uninstall','FullUninstall','SteamOptions','Update')][string]$Operation,
    [ValidateSet('UI','HUD','Both')][string]$Mode='Both', [string]$GameDir, [int]$InstallerPid)
Add-Type -AssemblyName System.Windows.Forms
. (Join-Path $PSScriptRoot 'Common.ps1')
try {
    $GameDir = Resolve-Game $GameDir
    if ($Operation -eq 'Update') {
        . (Join-Path $PSScriptRoot 'Update.ps1')
        $code = Invoke-ModUpdate -GameDir $GameDir -Mode $Mode -InstallerPid $InstallerPid
        exit $code
    }
    if ($Operation -eq 'SteamOptions') {
        $statePath = Join-Path $GameDir 'Game\Binaries\Win64\AC8Chinese\install-state.json'
        if (-not (Test-Path -LiteralPath $statePath)) { throw '请先安装汉化。' }
        $state = Read-JsonFile $statePath
        if ($state.owner -ne $ModOwner -or $state.gameDir -ne $GameDir) { throw '安装记录归属不明。' }
        [Windows.Forms.Clipboard]::SetText([string]$state.steam.installedOptions)
        [Windows.Forms.MessageBox]::Show('启动选项已复制。打开 Steam → 此游戏的属性 → 通用 → 启动选项，粘贴后直接启动游戏。只需设置一次。', 'ACE COMBAT 8 简体汉化', 'OK', 'Information') | Out-Null
        exit 0
    }
    if ($Operation -eq 'Install') {
        & (Join-Path $PSScriptRoot 'Install.ps1') -Mode $Mode -GameDir $GameDir
        $state = Read-JsonFile (Join-Path $GameDir 'Game\Binaries\Win64\AC8Chinese\install-state.json')
        $message = if ($state.steam.needsSetup) { '安装完成。首次使用请点击“复制 Steam 启动选项”，粘贴到 Steam 的游戏属性中。以后更换或更新汉化只需重启游戏。' } else { '安装完成。重新启动游戏即可生效，Steam 无需重启。' }
    } else {
        if ($Operation -eq 'FullUninstall' -and $InstallerPid) {
            $parent = Get-Process -Id $InstallerPid -ErrorAction SilentlyContinue
            if ($parent -and -not $parent.WaitForExit(15000)) { throw '安装器仍在运行，请关闭后从完整汉化包中重试完全卸载。' }
        }
        & (Join-Path $PSScriptRoot 'Uninstall.ps1') -GameDir $GameDir -Full:($Operation -eq 'FullUninstall')
        $message = if ($Operation -eq 'FullUninstall') { '完全卸载操作完成。校验一致的汉化文件和入口已删除，自行修改过的文件会保留。Steam 无需重启。' } else { '汉化已卸载，游戏恢复原文。仅保留 Steam 兼容入口；无需改动或重启 Steam。需要删除入口时，请清除 Steam 汉化启动选项后选择“完全卸载”。' }
    }
    [Windows.Forms.MessageBox]::Show($message, 'ACE COMBAT 8 简体汉化', 'OK', 'Information') | Out-Null
} catch {
    [Windows.Forms.MessageBox]::Show($_.Exception.Message, 'ACE COMBAT 8 简体汉化', 'OK', 'Error') | Out-Null
    exit 1
}
