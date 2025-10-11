schtasks /Create /TN "Security-Audit-Reports" /TR "powershell.exe -ExecutionPolicy Bypass -File C:\Scripts\Ultimate-Multi-Subscription-Audit.ps1" /SC WEEKLY /D TUE,FRI /ST 08:00 /RU SYSTEM /F
Write-Host "Security Audit Reports task created - Runs Tuesday and Friday at 8:00 AM" -ForegroundColor Green
