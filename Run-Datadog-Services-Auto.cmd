@echo off
REM Double-click to run Datadog monitor creation (v2.2 with PagerDuty + Slack per env).
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Deploy-Datadog-Services-Auto-ASCII.ps1" -PagerDutyService "@pagerduty-pyxhealth-oncall"
echo.
echo Done. PagerDuty and Slack routing enforced for all subscriptions and environments.
pause
