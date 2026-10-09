param([Parameter(Mandatory)][int]$GamePid, [ValidateSet('UI','HUD','Both')][string]$Mode='Both', [switch]$ReadOnly)
. (Join-Path $PSScriptRoot 'Common.ps1')
$packageRoot = Split-Path $PSScriptRoot -Parent
$manifest = Verify-Package $packageRoot
Assert-Offline
if (-not [Environment]::Is64BitProcess) { throw '汉化需要 64 位 Windows PowerShell。' }
$deadline = (Get-Date).AddSeconds(30)
do {
    $process = Get-Process -Id $GamePid
    try { $module = $process.MainModule } catch { $module = $null }
    if ($module -and $module.BaseAddress -ne [IntPtr]::Zero) { break }
    if ((Get-Date) -ge $deadline) { throw '游戏主模块初始化超时。' }
    Start-Sleep -Milliseconds 100
} while ($true)
if ($process.ProcessName -ne 'AceCombat8' -or (File-Hash $process.MainModule.FileName) -ne $SupportedExeHash) { throw '游戏进程或版本校验失败。' }
$rows = @(Read-JsonFile (Join-Path $PSScriptRoot 'translations.json'))
$rows = @(Select-Translations $rows $Mode)
if (-not ('AC8TextTables' -as [type])) { Add-Type -Path (Join-Path $PSScriptRoot 'AC8TextTables.dll') }
$result = [AC8TextTables]::Patch($GamePid, $process.MainModule.BaseAddress.ToInt64(), [int[]]$rows.index, [string[]]$rows.before, [string[]]$rows.after, [string[]]$rows.key, (-not $ReadOnly))
$result | ConvertTo-Json -Depth 5
if ($result.Skipped.Count) { throw '有词条未通过原文或内存容量校验，请查看启动日志。' }
