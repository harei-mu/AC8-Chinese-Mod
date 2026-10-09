# SPDX-License-Identifier: GPL-3.0-only
param([string]$Package = (Join-Path (Split-Path $PSScriptRoot -Parent) 'dist\AC8简体汉化'))
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
. (Join-Path $Package 'App\Common.ps1')
$manifest=Verify-Package $Package
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip=Scoped-Path (Join-Path $root 'dist') ('AC8-Chinese-Mod-v'+$manifest.version+'.zip')
if (Test-Path -LiteralPath $zip) { Remove-Item -LiteralPath $zip }
[IO.Compression.ZipFile]::CreateFromDirectory($Package,$zip,[IO.Compression.CompressionLevel]::Optimal,$false)
[IO.File]::WriteAllText($zip+'.sha256',(File-Hash $zip).ToLowerInvariant()+'  '+[IO.Path]::GetFileName($zip)+"`n",[Text.UTF8Encoding]::new($false))
Write-Host $zip
