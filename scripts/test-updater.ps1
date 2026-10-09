# SPDX-License-Identifier: GPL-3.0-only
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$package = Join-Path $root 'dist\AC8简体汉化'
. (Join-Path $package 'App\Update.ps1')
Add-Type -AssemblyName System.IO.Compression.FileSystem
$testRoot = Join-Path $root ('work\update-test-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testRoot | Out-Null
$passed = [Collections.Generic.List[string]]::new()
function Check([bool]$Condition,[string]$Name) { if (-not $Condition) { throw "FAILED: $Name" }; $passed.Add($Name) }
function Reject([scriptblock]$Action,[string]$Name) { $rejected=$false;try { & $Action | Out-Null } catch { $rejected=$true };Check $rejected $Name }
function Clone($Object) { return ($Object | ConvertTo-Json -Depth 20 | ConvertFrom-Json) }
$release = [pscustomobject]@{tag_name='v0.3.0';draft=$false;prerelease=$false;assets=@([pscustomobject]@{
 name='AC8-Chinese-Mod-v0.3.0.zip';size=100;digest=('sha256:' + ('a'*64));
 browser_download_url='https://github.com/harei-mu/AC8-Chinese-Mod/releases/download/v0.3.0/AC8-Chinese-Mod-v0.3.0.zip'})}
Check ((Select-ReleasePackage $release '0.2.0').version -ceq '0.3.0') 'newer stable release is selected'
Check ($null -eq (Select-ReleasePackage $release '0.3.0')) 'equal version is not reinstalled'
Check ($null -eq (Select-ReleasePackage $release '0.4.0')) 'older version is not installed'
Reject { Release-Version 'v0.3.0/evil' } 'malformed release tag rejected'
$bad=Clone $release;$bad.draft=$true;Reject { Select-ReleasePackage $bad '0.2.0' } 'draft release rejected'
$bad=Clone $release;$bad.prerelease=$true;Reject { Select-ReleasePackage $bad '0.2.0' } 'prerelease rejected'
$bad=Clone $release;$bad.assets[0].browser_download_url='https://example.com/package.zip';Reject { Select-ReleasePackage $bad '0.2.0' } 'foreign download URL rejected'
$bad=Clone $release;$bad.assets[0].digest=$null;Reject { Select-ReleasePackage $bad '0.2.0' } 'missing GitHub digest rejected'
$bad=Clone $release;$bad.assets[0].size=209715201;Reject { Select-ReleasePackage $bad '0.2.0' } 'oversized download rejected'
$bad=Clone $release;$bad.assets=@($bad.assets[0],$bad.assets[0]);Reject { Select-ReleasePackage $bad '0.2.0' } 'duplicate release assets rejected'
$zip=Join-Path $testRoot 'valid.zip'
[IO.Compression.ZipFile]::CreateFromDirectory($package,$zip)
$good=Expand-VerifiedPackage $zip (Join-Path $testRoot 'good') '0.3.0'
Check ((Verify-Package $good).version -ceq '0.3.0') 'complete package extracts and passes file hash and size checks'
Reject { Expand-VerifiedPackage $zip (Join-Path $testRoot 'wrong-version') '0.4.0' } 'mismatched package version rejected'
Reject { Expand-VerifiedPackage $zip $good '0.3.0' } 'existing extraction directory rejected'
$tampered=Join-Path $good 'App\Entry.ps1';[IO.File]::AppendAllText($tampered,'tampered')
Reject { Verify-Package $good } 'changed script rejected before execution'
function CraftedZip([string]$Name,[string[]]$Entries,[int]$Attributes=0) {
 $file=Join-Path $testRoot $Name;$archive=[IO.Compression.ZipFile]::Open($file,[IO.Compression.ZipArchiveMode]::Create)
 try { foreach ($entryName in $Entries) { $entry=$archive.CreateEntry($entryName);$entry.ExternalAttributes=$Attributes;$writer=[IO.StreamWriter]::new($entry.Open());try {$writer.Write('inert')}finally{$writer.Dispose()} } }finally{$archive.Dispose()};return $file
}
$escape=CraftedZip 'traversal.zip' @('../outside.txt');Reject { Expand-VerifiedPackage $escape (Join-Path $testRoot 'escape') '0.3.0' } 'ZIP directory traversal rejected'
Check (-not (Test-Path -LiteralPath (Join-Path $testRoot 'outside.txt'))) 'no file written outside extraction directory'
$absolute=CraftedZip 'absolute.zip' @('C:/outside.txt');Reject { Expand-VerifiedPackage $absolute (Join-Path $testRoot 'absolute') '0.3.0' } 'absolute ZIP path rejected'
$duplicate=CraftedZip 'duplicate.zip' @('App/a.ps1','app/A.ps1');Reject { Expand-VerifiedPackage $duplicate (Join-Path $testRoot 'duplicate') '0.3.0' } 'case-insensitive duplicate ZIP paths rejected'
$link=CraftedZip 'link.zip' @('link') (-1610612736);Reject { Expand-VerifiedPackage $link (Join-Path $testRoot 'link') '0.3.0' } 'symbolic-link ZIP entry rejected'
# Regression: hash verification must work without PowerShell's Get-FileHash cmdlet.
function Get-FileHash { throw 'This command must not be used' }
Check ((File-Hash $zip).Length -eq 64) '.NET SHA-256 works without Get-FileHash'
$report=@{date=(Get-Date).ToString('s');fixtureOnly=$true;passed=@($passed);liveGitHub='pending release publication'}
Write-JsonFile (Join-Path $root 'reports\updater-validation.json') $report
Write-Host ('Passed: ' + $passed.Count)
