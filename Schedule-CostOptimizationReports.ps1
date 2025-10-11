schtasks /Create /TN "Cost-Optimization-Reports" /TR "powershell.exe -ExecutionPolicy Bypass -File C:\Scripts\Cost-Optimization-Idle-Resources.ps1" /SC WEEKLY /D MON,THU /ST 09:00 /RU SYSTEM /F
Write-Host "Cost Optimization Reports task created - Runs Monday and Thursday at 9:00 AM" -ForegroundColor Green
