$ErrorActionPreference = 'Stop'
$ModOwner = 'AC8ChineseMod:offline-v1'
$SupportedExeHash = '51510E2A520565DBE81FB0D569E95CD4393077ACAAA859371489B80B8128829F'

function Read-JsonFile([string]$Path) {
    return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
}
function Write-JsonFile([string]$Path, $Value) {
    [IO.File]::WriteAllText($Path, ($Value | ConvertTo-Json -Depth 30) + "`r`n", [Text.UTF8Encoding]::new($false))
}
function Select-Translations($Rows, [string]$Mode) {
    return @($Rows | Where-Object { $Mode -eq 'Both' -or $_.component -eq $Mode -or ($Mode -eq 'HUD' -and $_.component -eq 'Shared') })
}
function Scoped-Path([string]$Root, [string]$Relative) {
    $prefix = [IO.Path]::GetFullPath($Root).TrimEnd('\') + '\'
    $result = [IO.Path]::GetFullPath((Join-Path $Root $Relative))
    if (-not $result.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) { throw '文件路径超出汉化目录。' }
    # Do not follow a directory junction into somebody else's files.
    $current = $result
    while ($current -and $current.Length -ge $prefix.TrimEnd('\').Length) {
        if ((Test-Path -LiteralPath $current) -and ((Get-Item -LiteralPath $current -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            throw "目录包含链接，无法确认文件归属：$current"
        }
        $current = Split-Path $current -Parent
    }
    return $result
}
function File-Hash([string]$Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
}
function Owned-Path([string]$GameBin, [string]$Relative) {
    if ($Relative.StartsWith('AC8Chinese\', [StringComparison]::OrdinalIgnoreCase)) {
        return Scoped-Path (Join-Path $GameBin 'AC8Chinese') $Relative.Substring(11)
    }
    if ($Relative.StartsWith('ue4ss\', [StringComparison]::OrdinalIgnoreCase)) {
        return Scoped-Path (Join-Path $GameBin 'ue4ss') $Relative.Substring(6)
    }
    throw '安装记录包含未授权的目标文件。'
}
function Verify-Package([string]$Root) {
    $manifest = Read-JsonFile (Join-Path $Root 'package-manifest.json')
    if ($manifest.owner -ne $ModOwner -or $manifest.exeSha256 -ne $SupportedExeHash) { throw '汉化包标识或游戏版本不匹配。' }
    foreach ($entry in $manifest.files) {
        $file = Scoped-Path $Root $entry.path
        if (-not (Test-Path -LiteralPath $file -PathType Leaf) -or (File-Hash $file) -ne $entry.sha256) { throw "汉化包文件损坏：$($entry.path)" }
    }
    return $manifest
}
function Find-GameDirectories([string[]]$SteamRoots) {
    if (-not $SteamRoots) {
        $SteamRoots = @((Get-ItemProperty 'HKCU:\Software\Valve\Steam' -ErrorAction SilentlyContinue).SteamPath,
            (Get-ItemProperty 'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam' -ErrorAction SilentlyContinue).InstallPath,
            (Get-ItemProperty 'HKLM:\SOFTWARE\Valve\Steam' -ErrorAction SilentlyContinue).InstallPath) | Where-Object { $_ }
    }
    $libraries = @($SteamRoots)
    foreach ($steam in $SteamRoots) {
        $vdf = Join-Path $steam 'steamapps\libraryfolders.vdf'
        if (Test-Path -LiteralPath $vdf) {
            foreach ($match in [regex]::Matches([IO.File]::ReadAllText($vdf), '"path"\s+"((?:\\.|[^"\\])*)"')) {
                $libraries += $match.Groups[1].Value.Replace('\\', '\').Replace('\"', '"')
            }
        }
    }
    foreach ($library in @($libraries | Select-Object -Unique)) {
        $installName = 'ACE COMBAT 8'
        $acf = Join-Path $library 'steamapps\appmanifest_2288340.acf'
        if (Test-Path -LiteralPath $acf) {
            $match = [regex]::Match([IO.File]::ReadAllText($acf), '"installdir"\s+"([^"\\]+)"')
            if ($match.Success -and $match.Groups[1].Value -notin @('.', '..')) { $installName = $match.Groups[1].Value }
        }
        $candidate = Join-Path $library ('steamapps\common\' + $installName)
        if (Test-Path -LiteralPath (Join-Path $candidate 'Game\Binaries\Win64\AceCombat8.exe') -PathType Leaf) {
            [IO.Path]::GetFullPath($candidate).TrimEnd('\')
        }
    }
}
function Resolve-Game([string]$GameDir) {
    if (-not $GameDir) {
        $GameDir = Find-GameDirectories | Select-Object -First 1
        if (-not $GameDir) {
            Add-Type -AssemblyName System.Windows.Forms
            $picker = New-Object Windows.Forms.FolderBrowserDialog
            $picker.Description = '请选择 ACE COMBAT 8 游戏文件夹'
            if ($picker.ShowDialog() -ne [Windows.Forms.DialogResult]::OK) { throw '未选择游戏目录。' }
            $GameDir = $picker.SelectedPath
        }
    }
    $GameDir = [IO.Path]::GetFullPath($GameDir).TrimEnd('\')
    $exe = Scoped-Path $GameDir 'Game\Binaries\Win64\AceCombat8.exe'
    if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) { throw '所选文件夹没有找到游戏程序。' }
    return $GameDir
}
function Assert-GameClosed([string]$GameDir) {
    $exe = Join-Path $GameDir 'Game\Binaries\Win64\AceCombat8.exe'
    foreach ($process in @(Get-Process -Name AceCombat8 -ErrorAction SilentlyContinue)) {
        try { $path = $process.MainModule.FileName } catch { throw '无法确认游戏状态，请正常退出游戏后重试。' }
        if ($path -eq $exe) { throw '请先正常退出游戏，再运行安装或卸载。' }
    }
}
function Assert-Offline {
    if (Get-Process | Where-Object { $_.ProcessName -match 'EasyAntiCheat|start_protected_game' }) { throw '请先退出受保护的游戏启动器，再使用单机汉化入口。' }
}
function New-Parent([string]$Path) {
    New-Item -ItemType Directory -Path (Split-Path $Path -Parent) -Force | Out-Null
}
function Remove-EmptyDirectories([string]$Root) {
    if (-not (Test-Path -LiteralPath $Root)) { return }
    # Verify every resolved target, then remove only empty directories, deepest first.
    $directories = @(Get-ChildItem -LiteralPath $Root -Directory -Recurse -Force | Sort-Object { $_.FullName.Length } -Descending)
    foreach ($dir in $directories) {
        $relative = $dir.FullName.Substring($Root.TrimEnd('\').Length + 1)
        $checked = Scoped-Path $Root $relative
        if (@(Get-ChildItem -LiteralPath $checked -Force).Count -eq 0) { Remove-Item -LiteralPath $checked }
    }
}
