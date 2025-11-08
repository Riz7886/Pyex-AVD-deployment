Datadog Alerting & Reporting  v2.3
=================================

Included:
- Deploy-Datadog-Services-Auto-ASCII.ps1      -> Creates monitors only for live services (all subscriptions). PagerDuty + Slack routing baked in.
- Run-Datadog-Services-Auto.cmd                -> Double-click runner.
- Generate-Datadog-CostReports-ASCII.ps1      -> Creates per-subscription HTML pages + index + CSV with savings vs prior 30 days.
- Send-Monthly-CostReport.ps1                  -> Generates and emails the report to CloudOps recipients.
- Register-Monthly-ReportTask.ps1              -> Schedules Send-Monthly-CostReport.ps1 monthly (1st @ 08:00).
- Datadog-Enterprise-Alerting-Architecture-SR.docx
- Datadog-Azure-Alerting-Architecture.png

SMTP Setup (Office 365 example)
-------------------------------
1) Create/get a mailbox like cloudops@pyxhealth.com and app password or delegated creds.
2) Update `Send-Monthly-CostReport.ps1` parameters if needed:
   -From 'cloudops@pyxhealth.com' -SmtpServer 'smtp.office365.com' -SmtpPort 587 -UseSsl
3) Run:
   $cred = Get-Credential  # enter cloudops mailbox creds (or use secure secret retrieval)
   powershell -NoProfile -ExecutionPolicy Bypass -File .\Send-Monthly-CostReport.ps1 -Credential $cred

Schedule Monthly Email
----------------------
.\Register-Monthly-ReportTask.ps1 -User "DOMAIN\\YourServiceAccount" -Password "ServiceAccountPassword"

Manual One-Off Run
------------------
powershell -NoProfile -ExecutionPolicy Bypass -File .\Generate-Datadog-CostReports-ASCII.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\Send-Monthly-CostReport.ps1 -Credential (Get-Credential)
