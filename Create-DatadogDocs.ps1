# ===============================================
# Datadog Enterprise Documentation Generator
# ===============================================

Add-Type -AssemblyName Microsoft.Office.Interop.Word | Out-Null
$Word = New-Object -ComObject Word.Application
$Word.Visible = $false

$basePath  = (Get-Location).Path
$diagram   = Join-Path $basePath "Datadog-Azure-Alerting-Architecture.png"
$archDoc   = Join-Path $basePath "Datadog-Azure-Architecture.docx"
$bizDoc    = Join-Path $basePath "Datadog-Azure-Business-Case.docx"
$zipOutput = Join-Path $basePath "Datadog-Enterprise-Documentation.zip"

function Add-Heading($doc, $text, $level=1) {
    $p = $doc.Paragraphs.Add()
    $p.Range.Text = $text
    $p.Range.Style = "Heading $level"
    $p.Range.InsertParagraphAfter() | Out-Null
}

# =====================================================
# ARCHITECTURE DOCUMENT
# =====================================================
$doc = $Word.Documents.Add()
$sel = $Word.Selection

$sel.TypeText("PyxHealth Enterprise Cloud Platform - Datadog Enterprise Monitoring (US3)")
$sel.Style = "Title"
$sel.TypeParagraph()
$sel.TypeText("Azure Integration | 14 Subscriptions | Automated Alerting and Cost Optimization")
$sel.Style = "Subtitle"
$sel.TypeParagraph()
$sel.TypeParagraph()

if (Test-Path $diagram) {
    $img = $sel.InlineShapes.AddPicture($diagram)
    $img.Width = 500
    $img.Height = 280
    $sel.TypeParagraph()
}

Add-Heading $doc "Executive Summary"
$sel.TypeText("Datadog delivers unified monitoring and alerting across 14 Azure subscriptions. It ingests metrics, logs, and costs, sending alerts via Email, Slack, and PagerDuty.")
$sel.TypeParagraph()

Add-Heading $doc "System Overview"
$sel.TypeText("• Azure Integration: App Services, VMs, AKS, SQL, Storage, Key Vault, Databricks.`r• Datadog Cloud (US3): Metrics, Logs, APM, Cost Analytics.`r• Alert Routing: Email, Slack, PagerDuty.")
$sel.TypeParagraph()

Add-Heading $doc "Component Breakdown"
$sel.TypeText("Metrics and APM: CPU, memory, disk, network, cost.`rLogs: Error spike detection, JSON parsing, retention.`rMonitors: Automated for live resources only.`rCost Analytics: 30d vs prior reports, HTML/CSV monthly.")
$sel.TypeParagraph()

Add-Heading $doc "Security / Operational / Business Excellence"
$sel.TypeText("Security: Read-only, Entra ID + MFA.`rOperational: Idempotent alert automation.`rBusiness: 30 percent MTTR reduction, 27 percent cost savings vs Azure Monitor.")
$sel.TypeParagraph()

Add-Heading $doc "Connectivity and Ports"
$table = $doc.Tables.Add($doc.Range($doc.Content.End - 1), 5, 5)
$table.Borders.Enable = $true
$table.Cell(1,1).Range.Text = "Direction"
$table.Cell(1,2).Range.Text = "Source"
$table.Cell(1,3).Range.Text = "Destination"
$table.Cell(1,4).Range.Text = "Port"
$table.Cell(1,5).Range.Text = "Purpose"

$data = @(
    "Outbound","Azure Resources","Datadog API (us3.datadoghq.com)","443","Metrics/Logs Intake",
    "Inbound","Admins","Datadog Web Console","443","SSO Access",
    "Outbound","Datadog","Slack/PagerDuty","443","Alert Routing",
    "Outbound","Datadog","SMTP","587","Email Notifications"
)
for ($i=0; $i -lt 4; $i++) {
    $row = $table.Rows.Add()
    for ($j=0; $j -lt 5; $j++) {
        $table.Cell($i+2,$j+1).Range.Text = $data[($i*5)+$j]
    }
}
$doc.SaveAs([ref]$archDoc)
$doc.Close()

# =====================================================
# BUSINESS CASE DOCUMENT
# =====================================================
$doc2 = $Word.Documents.Add()
$sel = $Word.Selection

$sel.TypeText("Business Case - Datadog Enterprise Monitoring for Azure")
$sel.Style = "Title"
$sel.TypeParagraph()
$sel.TypeText("PyxHealth Enterprise Cloud Platform  •  14 Subscriptions  •  US3 Region")
$sel.Style = "Subtitle"
$sel.TypeParagraph()

if (Test-Path $diagram) {
    $img2 = $sel.InlineShapes.AddPicture($diagram)
    $img2.Width = 500
    $img2.Height = 280
    $sel.TypeParagraph()
}

Add-Heading $doc2 "Executive Summary"
$sel.TypeText("Datadog unifies monitoring across all Azure subscriptions, reducing cost and MTTR through automated alerting and reporting.")
$sel.TypeParagraph()

Add-Heading $doc2 "Business Problem and Objectives"
$sel.TypeText("Problem: Fragmented dashboards, duplicate alerts, limited visibility.`rObjective: Unify observability, lower cost, improve incident response.")
$sel.TypeParagraph()

Add-Heading $doc2 "Proposed Solution"
$sel.TypeText("Deploy Datadog US3 integration, automate alerts, route via Email, Slack, and PagerDuty, with monthly cost reports.")
$sel.TypeParagraph()

Add-Heading $doc2 "Cost Comparison"
$t2 = $doc2.Tables.Add($doc2.Range($doc2.Content.End - 1),3,4)
$t2.Borders.Enable = $true
$t2.Cell(1,1).Range.Text="Option"
$t2.Cell(1,2).Range.Text="Monthly"
$t2.Cell(1,3).Range.Text="Notes"
$t2.Cell(1,4).Range.Text="Savings"
$t2.Cell(2,1).Range.Text="Azure Monitor"
$t2.Cell(2,2).Range.Text="$1,750"
$t2.Cell(2,3).Range.Text="Baseline"
$t2.Cell(2,4).Range.Text="—"
$t2.Cell(3,1).Range.Text="Datadog (US3)"
$t2.Cell(3,2).Range.Text="$1,275"
$t2.Cell(3,3).Range.Text="Unified cost analytics"
$t2.Cell(3,4).Range.Text="$475 / mo"

Add-Heading $doc2 "ROI and Implementation Timeline"
$sel.TypeText("3-Year ROI ≈ $17,100 savings.`rWeek 1: Integration.`rWeek 2: Alert setup.`rWeek 3: Cost scheduler.`rWeek 4: Handoff.")
$sel.TypeParagraph()

Add-Heading $doc2 "KPIs and Recommendations"
$sel.TypeText("• MTTR ≤ 4 hrs (30 percent improvement)`r• Cost saving ≥ 25 percent`r• Approve rollout, standardize Slack/PagerDuty routing, enable monthly reports.")
$sel.TypeParagraph()

$doc2.SaveAs([ref]$bizDoc)
$doc2.Close()

# =====================================================
# ZIP OUTPUT
# =====================================================
if (Test-Path $zipOutput) { Remove-Item $zipOutput -Force }
Add-Type -AssemblyName System.IO.Compression.FileSystem
[System.IO.Compression.ZipFile]::CreateFromDirectory($basePath, $zipOutput)

$Word.Quit()
Write-Host ""
Write-Host "✅ Documents created successfully!"
Write-Host " - $archDoc"
Write-Host " - $bizDoc"
Write-Host " - $zipOutput"