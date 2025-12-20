# ===== AMD Driver Signing Script (Complete) =====

$ErrorActionPreference = "Stop"
$DriverFolder = "C:\DRIVERS\Packages\Drivers\Display\WT6A_INF"
$SysFile = "$DriverFolder\B420718\amdkmdag.sys"
$CatFile = "$DriverFolder\u0420842.cat"
$CertName = "AMD Driver Signing Certificate"
$CertPassword = "DriverSign123!"
$CertExportPath = "$env:USERPROFILE\Desktop\DriverCert.pfx"
$SignTool = "C:\Program Files (x86)\Windows Kits\10\bin\10.0.26100.0\x64\signtool.exe"

# === Step 1: 証明書を取得または作成 ===
Write-Host "[Step 1] Getting certificate..." -ForegroundColor Cyan
$Cert = Get-ChildItem Cert:\CurrentUser\My | Where-Object { $_.Subject -like "*$CertName*" } | Select-Object -First 1

if (-not $Cert) {
    $Cert = New-SelfSignedCertificate `
        -Type CodeSigningCert `
        -Subject "CN=$CertName" `
        -KeyUsage DigitalSignature `
        -KeyAlgorithm RSA `
        -KeyLength 2048 `
        -CertStoreLocation "Cert:\CurrentUser\My" `
        -NotAfter (Get-Date).AddYears(5)
    Write-Host "Certificate created" -ForegroundColor Green
} else {
    Write-Host "Using existing certificate" -ForegroundColor Green
}

# === Step 2: 証明書を信頼ストアに追加 ===
Write-Host "[Step 2] Installing certificate to trust stores..." -ForegroundColor Cyan
$SecurePassword = ConvertTo-SecureString -String $CertPassword -Force -AsPlainText
Export-PfxCertificate -Cert $Cert -FilePath $CertExportPath -Password $SecurePassword -Force | Out-Null

$RootStore = New-Object System.Security.Cryptography.X509Certificates.X509Store("Root", "LocalMachine")
$RootStore.Open("ReadWrite")
$RootStore.Add($Cert)
$RootStore.Close()

$PublisherStore = New-Object System.Security.Cryptography.X509Certificates.X509Store("TrustedPublisher", "LocalMachine")
$PublisherStore.Open("ReadWrite")
$PublisherStore.Add($Cert)
$PublisherStore.Close()
Write-Host "Done" -ForegroundColor Green

# === Step 3: 元のカタログファイルをバックアップ＆削除 ===
Write-Host "[Step 3] Removing original catalog file..." -ForegroundColor Cyan
if (Test-Path $CatFile) {
    $CatBackup = "$CatFile.bak"
    if (-not (Test-Path $CatBackup)) {
        Move-Item $CatFile $CatBackup -Force
        Write-Host "Catalog backed up and removed" -ForegroundColor Green
    } else {
        Remove-Item $CatFile -Force -ErrorAction SilentlyContinue
        Write-Host "Catalog removed" -ForegroundColor Green
    }
}

# === Step 4: amdkmdag.sys に署名 ===
Write-Host "[Step 4] Signing amdkmdag.sys..." -ForegroundColor Cyan
& $SignTool sign /fd SHA256 /f $CertExportPath /p $CertPassword /tr http://timestamp.digicert.com /td SHA256 $SysFile

if ($LASTEXITCODE -eq 0) {
    Write-Host "Signed successfully!" -ForegroundColor Green
} else {
    Write-Host "Signing failed!" -ForegroundColor Red
    exit 1
}

# === Step 5: 確認 ===
Write-Host "[Step 5] Verifying signature..." -ForegroundColor Cyan
& $SignTool verify /pa $SysFile

# === Step 6: テスト署名モード確認 ===
Write-Host "[Step 6] Checking test signing mode..." -ForegroundColor Cyan
bcdedit /set testsigning on

Write-Host "`n========================================" -ForegroundColor Green
Write-Host "Complete!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host "`nManual install steps:"
Write-Host "1. Device Manager -> AMD Radeon Graphics"
Write-Host "2. Right-click -> Update driver"
Write-Host "3. Browse my computer -> Let me pick"
Write-Host "4. Have Disk -> Browse to:"
Write-Host "   $DriverFolder\u0420842.inf"
Write-Host "5. Reboot"