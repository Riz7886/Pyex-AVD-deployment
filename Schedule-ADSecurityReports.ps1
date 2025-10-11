schtasks /Create /TN "AD-Security-Reports" /TR "powershell.exe -ExecutionPolicy Bypass -File C:\Scripts\Ultimate-AD-Security-Hardening.ps1" /SC WEEKLY /D TUE,FRI /ST 09:00 /RU SYSTEM /F
Write-Host "AD Security Reports task created - Runs Tuesday and Friday at 9:00 AM" -ForegroundColor Green
