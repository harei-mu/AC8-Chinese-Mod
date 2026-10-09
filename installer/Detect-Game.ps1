. (Join-Path $PSScriptRoot 'Common.ps1')
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
Find-GameDirectories | Select-Object -First 1
