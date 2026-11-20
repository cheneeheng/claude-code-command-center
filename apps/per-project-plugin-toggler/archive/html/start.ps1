$port = 7779
$projectRoot = (Get-Location).Path
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Start-Process python -ArgumentList "server.py $port `"$projectRoot`"" -WorkingDirectory $scriptDir -WindowStyle Hidden
Start-Sleep -Seconds 2
Start-Process "http://localhost:$port/"
