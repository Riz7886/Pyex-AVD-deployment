schtasks /Create /TN "Azure-Monitor-Reports" /TR "powershell.exe -ExecutionPolicy Bypass -File C:\Scripts\Deploy-Azure-Monitor-Alerts.ps1" /SC WEEKLY /D MON,THU /ST 08:00 /RU SYSTEM /F
Write-Host "Azure Monitor Reports task created - Runs Monday and Thursday at 8:00 AM" -ForegroundColor Green
