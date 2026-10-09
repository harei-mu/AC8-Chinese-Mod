param([string]$GameDir)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$package = Join-Path $root 'dist\AC8简体汉化'
$testRoot = Join-Path $root ('work\installer-test-' + (Get-Date -Format 'yyyyMMddHHmmss'))
$game = Join-Path $testRoot 'ACE COMBAT 8'
$bin = Join-Path $game 'Game\Binaries\Win64'
$steam = Join-Path $testRoot 'Steam'
$config = Join-Path $steam 'userdata\123\config\localconfig.vdf'
$ps5 = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
New-Item -ItemType Directory -Path $bin, (Split-Path $config -Parent) -Force | Out-Null
# Use a real supported executable as inert fixture data; never execute the copy.
. (Join-Path $package 'App\Common.ps1')
$originalExe = Join-Path (Resolve-Game $GameDir) 'Game\Binaries\Win64\AceCombat8.exe'
Copy-Item -LiteralPath $originalExe -Destination (Join-Path $bin 'AceCombat8.exe')
[IO.File]::WriteAllText((Join-Path $steam 'steam.exe'), 'inert-test-fixture')
$vdf = '"UserLocalConfigStore" { "Software" { "Valve" { "Steam" { "apps" {' + "`r`n" +
    '"42" { "LaunchOptions" "-other" "Literal" "}" } // untouched game' + "`r`n" +
    '"2288340" { "LaunchOptions" "-windowed" "OtherValue" "unchanged" }' + "`r`n" + ' } } } } }'
[IO.File]::WriteAllText($config, $vdf)
$results = [Collections.Generic.List[string]]::new()
function Assert-Test([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw "TEST FAILED: $Message" }
    $results.Add($Message)
}
function Run-Installer([string]$Mode) {
    & $ps5 -NoProfile -ExecutionPolicy Bypass -File (Join-Path $package 'App\Install.ps1') -GameDir $game -SteamDir $steam -Mode $Mode -NoShortcuts
    if ($LASTEXITCODE -ne 0) { throw "Installation failed: $Mode" }
}
function Run-Uninstaller([switch]$Full) {
    $flags = @(); if ($Full) { $flags += '-Full' }
    & $ps5 -NoProfile -ExecutionPolicy Bypass -File (Join-Path $package 'App\Uninstall.ps1') -GameDir $game @flags
    if ($LASTEXITCODE -ne 0) { throw 'Uninstallation failed' }
}
. (Join-Path $package 'App\Common.ps1')
. (Join-Path $package 'App\Steam.ps1')
$rows = @(Read-JsonFile (Join-Path $package 'App\translations.json'))
$ui = @(Select-Translations $rows 'UI')
$hud = @(Select-Translations $rows 'HUD')
Assert-Test (@($ui | Where-Object { $_.component -ne 'UI' }).Count -eq 0) 'UI mode excludes HUD strings and shared HUD abbreviations'
Assert-Test (@($hud | Where-Object { $_.component -eq 'UI' }).Count -eq 0) 'HUD mode excludes menu and aircraft detail strings'
Assert-Test (@(Select-Translations $rows 'Both').Count -eq $rows.Count) 'Both mode includes every selected translation'
$exeHash = File-Hash (Join-Path $bin 'AceCombat8.exe')
$steamProcessesBefore = @(Get-Process -Name steam -ErrorAction SilentlyContinue | ForEach-Object { "$($_.Id):$($_.StartTime.Ticks)" }) -join ','
$app = Join-Path $bin 'AC8Chinese'
foreach ($mode in @('UI','HUD','Both')) {
    Run-Installer $mode
    $state = Read-JsonFile (Join-Path $app 'install-state.json')
    Assert-Test ($state.mode -eq $mode) "selected component $mode persists"
    Assert-Test ([IO.File]::ReadAllText($config) -ceq $vdf) "Steam configuration untouched for $mode"
    Assert-Test ($state.steam.needsSetup -and $state.steam.installedOptions.Contains('--steam-launch %command% -windowed')) "first-use copy instructions preserve original arguments for $mode"
    Assert-Test ([IO.File]::ReadAllText($config).Contains('"42" { "LaunchOptions" "-other" "Literal" "}" }')) "other Steam game preserved for $mode"
    foreach ($file in $state.files) {
        if ((File-Hash (Owned-Path $bin $file.path)) -ne $file.sha256) { throw 'Installed file hash mismatch' }
    }
}
$traversalBlocked = $false
try { $null = Owned-Path $bin 'ue4ss\..\AceCombat8.exe' } catch { $traversalBlocked=$true }
Assert-Test $traversalBlocked 'malicious ownership path cannot target original executable'
Write-JsonFile (Join-Path $testRoot 'before-uninstall-state.json') $state
# Simulate the user pasting the one-time launch option in Steam's own UI.
$configuredVdf = [AC8SteamVdf]::Set($vdf, $state.steam.installedOptions)
[IO.File]::WriteAllText($config, $configuredVdf)
Run-Uninstaller
Assert-Test ([IO.File]::ReadAllText($config) -ceq $configuredVdf) 'ordinary uninstall does not edit Steam settings'
$disabled = Read-JsonFile (Join-Path $app 'install-state.json')
Assert-Test ($disabled.mode -eq 'None' -and $disabled.files.Count -eq 1 -and $disabled.files[0].path -eq 'AC8Chinese\汉化安装器.exe') 'ordinary uninstall retains only the native compatibility entry and record'
Assert-Test (-not (Test-Path -LiteralPath (Join-Path $app 'App'))) 'ordinary uninstall removes localization app and payload'
Run-Installer Both
Assert-Test ((Read-JsonFile (Join-Path $app 'install-state.json')).mode -eq 'Both') 'reinstall after ordinary uninstall restores localization'
& $ps5 -NoProfile -ExecutionPolicy Bypass -File (Join-Path $package 'App\Uninstall.ps1') -GameDir $game -Full 2> (Join-Path $testRoot 'expected-active-entry.log')
Assert-Test ($LASTEXITCODE -ne 0 -and (Test-Path -LiteralPath (Join-Path $app 'App\translations.json'))) 'full uninstall refuses to delete an entry still referenced by Steam'
# Simulate the user restoring the launch option in Steam, without restarting it.
[IO.File]::WriteAllText($config, $vdf)
Run-Uninstaller -Full
Assert-Test ([IO.File]::ReadAllText($config) -ceq $vdf) 'full uninstall leaves user-restored Steam settings untouched'
Assert-Test (-not (Test-Path -LiteralPath $app)) 'all unmodified installed app files removed'
Assert-Test (-not (Test-Path -LiteralPath (Join-Path $bin 'ue4ss'))) 'all unmodified runtime files removed'
Assert-Test ((File-Hash (Join-Path $bin 'AceCombat8.exe')) -eq $exeHash) 'original executable unchanged after install/uninstall'
# Foreign proxy must be preserved with no partial installation.
$foreign = Join-Path $bin 'dwmapi.dll'
[IO.File]::WriteAllText($foreign, 'another-mod')
& $ps5 -NoProfile -ExecutionPolicy Bypass -File (Join-Path $package 'App\Install.ps1') -GameDir $game -SteamDir $steam -Mode Both -NoShortcuts 2> (Join-Path $testRoot 'expected-conflict.log')
Assert-Test ($LASTEXITCODE -ne 0 -and [IO.File]::ReadAllText($foreign) -eq 'another-mod' -and -not (Test-Path -LiteralPath $app)) 'foreign MOD conflict refused without overwriting files'
Remove-Item -LiteralPath $foreign
Run-Installer Both
$changed = Join-Path $app '使用说明.txt'
[IO.File]::AppendAllText($changed, 'user-edited')
Run-Uninstaller -Full
Assert-Test ((Test-Path -LiteralPath $changed) -and [IO.File]::ReadAllText($changed).EndsWith('user-edited')) 'user-modified owned file preserved during uninstall'
Assert-Test ([IO.File]::ReadAllText($config) -ceq $vdf) 'Steam untouched even when modified user files preserved'
$steamProcessesAfter = @(Get-Process -Name steam -ErrorAction SilentlyContinue | ForEach-Object { "$($_.Id):$($_.StartTime.Ticks)" }) -join ','
Assert-Test ($steamProcessesBefore -ceq $steamProcessesAfter) 'running Steam processes were neither stopped nor started'
$library = Join-Path $testRoot 'Another drive library'
$discoveredGame = Join-Path $library 'steamapps\common\Renamed install folder'
New-Item -ItemType Directory -Path (Join-Path $discoveredGame 'Game\Binaries\Win64') -Force | Out-Null
[IO.File]::WriteAllText((Join-Path $discoveredGame 'Game\Binaries\Win64\AceCombat8.exe'), 'discovery-fixture')
New-Item -ItemType Directory -Path (Join-Path $steam 'steamapps') -Force | Out-Null
[IO.File]::WriteAllText((Join-Path $steam 'steamapps\libraryfolders.vdf'), ('"libraryfolders" { "1" { "path" "' + $library.Replace('\','\\') + '" } }'))
[IO.File]::WriteAllText((Join-Path $library 'steamapps\appmanifest_2288340.acf'), '"AppState" { "appid" "2288340" "installdir" "Renamed install folder" }')
Assert-Test (@(Find-GameDirectories @($steam)) -contains $discoveredGame) 'automatic search reads all Steam libraries and the actual install folder from appmanifest'
# Compile both native memory code and VDF parser with stock Windows PowerShell 5.1.
$compile = Join-Path $testRoot 'compile-check.ps1'
$script = @'
$ErrorActionPreference = 'Stop'
foreach ($file in Get-ChildItem -LiteralPath $args[0] -Filter '*.ps1') {
    $tokens=$null;$errors=$null
    $null=[Management.Automation.Language.Parser]::ParseFile($file.FullName,[ref]$tokens,[ref]$errors)
    if ($errors.Count) {throw ($errors | Out-String)}
}
. (Join-Path $args[0] 'Steam.ps1')
$source=[IO.File]::ReadAllText((Join-Path $args[0] 'Patch-Text.ps1'))
Add-Type -Path (Join-Path $args[0] 'AC8TextTables.dll')
if (-not ('AC8TextTables' -as [type])) {throw 'Native text helper not loaded'}
'@
[IO.File]::WriteAllText($compile, $script, [Text.UTF8Encoding]::new($true))
& $ps5 -NoProfile -ExecutionPolicy Bypass -File $compile (Join-Path $package 'App')
Assert-Test ($LASTEXITCODE -eq 0) 'all scripts parse and precompiled text helper loads on Windows PowerShell 5.1'
$report = @{date=(Get-Date).ToString('s');gameBuild='25201480';fixtureOnly=$true;passed=@($results);actualSteamLaunch='pending';actualNewPages='pending'}
Write-JsonFile (Join-Path $root 'reports\installer-validation.json') $report
Write-Host ('Passed: ' + $results.Count)
