$script = Join-Path $PSScriptRoot 'Start-Chinese.ps1'
Start-Process -FilePath (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe') -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -File "' + $script + '"') -WindowStyle Hidden
