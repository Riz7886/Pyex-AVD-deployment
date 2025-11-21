# ================================================================
# GENERATE SSL CERTIFICATE FOR APPLICATION GATEWAY
# Run this BEFORE running Terraform
# ================================================================

Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  GENERATING SSL CERTIFICATE" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

$certPassword = "Terraform2024!"
$certPath = "appgw-cert.pfx"

Write-Host "[INFO] Creating self-signed certificate..." -ForegroundColor Yellow
$cert = New-SelfSignedCertificate `
    -DnsName "moveit.local" `
    -CertStoreLocation "Cert:\CurrentUser\My" `
    -NotAfter (Get-Date).AddYears(2)

Write-Host "[INFO] Exporting certificate to PFX..." -ForegroundColor Yellow
$certPasswordSecure = ConvertTo-SecureString -String $certPassword -Force -AsPlainText
Export-PfxCertificate `
    -Cert $cert `
    -FilePath $certPath `
    -Password $certPasswordSecure | Out-Null

if (Test-Path $certPath) {
    Write-Host "[SUCCESS] Certificate created: $certPath" -ForegroundColor Green
    Write-Host "[SUCCESS] Password: $certPassword" -ForegroundColor Green
} else {
    Write-Host "[ERROR] Certificate creation failed!" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "============================================" -ForegroundColor Green
Write-Host "  CERTIFICATE READY!" -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Green
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "  1. Run: terraform init" -ForegroundColor White
Write-Host "  2. Run: terraform plan" -ForegroundColor White
Write-Host "  3. Run: terraform apply" -ForegroundColor White
Write-Host ""
