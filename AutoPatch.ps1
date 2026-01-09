# =================================================================================================
#  Steam Deck: ROG XBOX ALLY Graphics Driver Patcher
# =================================================================================================


# =================================================================================================
# 1.ENVIRONMENT SETUP
# =================================================================================================

# Auto‑elevate to Administrator
$IsAdmin = ([Security.Principal.WindowsPrincipal] `
    [Security.Principal.WindowsIdentity]::GetCurrent()
).IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)

if (-not $IsAdmin) {
    Write-Host "Restarting script with administrative privileges..." -ForegroundColor Yellow

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "powershell.exe"
    $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    $psi.Verb = "runas"

    try { [System.Diagnostics.Process]::Start($psi) | Out-Null }
    catch { Write-Host "User declined elevation. Exiting." -ForegroundColor Red }

    exit
}

# Force black background
$Host.UI.RawUI.BackgroundColor = 'Black'
$Host.UI.RawUI.ForegroundColor = 'Gray'
Clear-Host

# Determine script directory
$ScriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path $MyInvocation.MyCommand.Definition -Parent }
Set-Location $ScriptDir



# =================================================================================================
# 2. INTRO MESSAGE
# =================================================================================================

$SteamDeckASCII = @"
                                           
                :@@%*=-.                   
                :@@@@@@@@#-.               
                :@@@@@@@@@@@#.             
                :%@@@@@@@@@@@@#.           
                    .-#@@@@@@@@@=.         
            .:-====:.  .-%@@@@@@@*.        
         .-+++++++++++=.  =@@@@@@@+        
        :+++++++++++++++-. -@@@@@@@-       
       :+++++++++++++++++-. =@@@@@@*       
       =++++++++++++++++++. .%@@@@@%       
       +++++++++++++++++++: .%@@@@@%       
       =++++++++++++++++++. .%@@@@@%       
       :+++++++++++++++++=. =@@@@@@*       
        :+++++++++++++++-. -@@@@@@@-       
         .-+++++++++++=.  =@@@@@@@+        
            .:=====-.  .:%@@@@@@@*.        
                    .-*@@@@@@@@@+.         
                :%@@@@@@@@@@@@#.           
                :@@@@@@@@@@@%.             
                :@@@@@@@@#=.               
                :@@%#+-.                   
                                           
"@

Clear-Host
Write-Host $SteamDeckASCII -ForegroundColor Cyan
Write-Host ""
Write-Host "Steam Deck: ROG XBOX ALLY Graphics Driver Patcher" -ForegroundColor Cyan
Write-Host "This script will automatically patch and sign the AMD Graphics Driver from the ROG XBOX ALLY to work on the Steam Deck." -ForegroundColor Cyan
Write-Host "All tools will be downloaded automatically, except the driver, you must manually download it from the ASUS website." -ForegroundColor Cyan
Write-Host "This script was made for personal use, with the help of Copilot." -ForegroundColor Cyan
Write-Host "I am not responsible for any issues caused by using this script, such as:" -ForegroundColor Cyan
Write-Host "- You caught a virus." -ForegroundColor Cyan
Write-Host "- Your Steam Deck stopped working." -ForegroundColor Cyan
Write-Host "- Your house burned down." -ForegroundColor Cyan
Write-Host "If you are aware of the risks, press any key to continue." -ForegroundColor Cyan

try {
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
} catch {
    Read-Host -Prompt "Press Enter to continue"
}

Write-Host "Script directory: $ScriptDir" -ForegroundColor Cyan



# =================================================================================================
# 3. UTILITY FUNCTIONS
# =================================================================================================

function Fail {
    param([string]$Message)
    Write-Host ""
    Write-Host "ERROR: $Message" -ForegroundColor Red
    Write-Host ""
    Write-Host "Press any key to exit..." -ForegroundColor Yellow

    try {
        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    } catch {
        Read-Host -Prompt "Press Enter to exit"
    }

    Exit 1
}

function Test-7Zip {
    try {
        if (Get-Command 7z -ErrorAction SilentlyContinue) { return $true }
        $paths = @(
            "$env:ProgramFiles\7-Zip\7z.exe",
            "$env:ProgramFiles(x86)\7-Zip\7z.exe"
        )
        foreach ($p in $paths) { if (Test-Path $p) { return $true } }
        return $false
    } catch { return $false }
}



# =================================================================================================
# 4. PATH SETUP & PRE‑CLEANUP
# =================================================================================================

$OutDir      = Join-Path $ScriptDir "DRIVERS"
$CertPfx     = Join-Path $ScriptDir "SteamDeckTestDriverCert.pfx"
$CertCer     = Join-Path $ScriptDir "SteamDeckTestDriverCert.cer"
$PasswordTxt = Join-Path $ScriptDir "password.txt"

# Remove old DRIVERS folder
if (Test-Path $OutDir) {
    Write-Host "Removing existing DRIVERS folder..." -ForegroundColor Yellow
    try { Remove-Item $OutDir -Recurse -Force -ErrorAction Stop }
    catch { Fail "Failed to remove existing DRIVERS folder: $($_.Exception.Message)" }
}

# Remove old cert artifacts
foreach ($f in @($CertPfx, $CertCer, $PasswordTxt)) {
    if (Test-Path $f) {
        Write-Host "Removing existing file: $f" -ForegroundColor Yellow
        try { Remove-Item $f -Force -ErrorAction Stop }
        catch { Fail "Failed to remove file '$f': $($_.Exception.Message)" }
    }
}



# =================================================================================================
# 5. DEPENDENCY CHECKS (7-Zip, signtool, SDK)
# =================================================================================================

# 7-Zip
if (-not (Test-7Zip)) {
    Write-Host "7-Zip not found. Installing via winget..." -ForegroundColor Cyan
    try {
        Start-Process "winget" -ArgumentList "install","-e","--id","7zip.7zip" -Wait -NoNewWindow -ErrorAction Stop
    } catch { Fail "Failed to install 7-Zip: $($_.Exception.Message)" }

    if (-not (Test-7Zip)) { Fail "7-Zip installation failed." }
    Write-Host "7-Zip installed." -ForegroundColor Green
} else {
    Write-Host "7-Zip detected." -ForegroundColor Green
}

# signtool path
$SignToolPath = "C:\Program Files (x86)\Windows Kits\10\bin\10.0.26100.0\x64\signtool.exe"

# SDK installer info
$SdkFwlink      = "https://go.microsoft.com/fwlink/?linkid=2346012"
$InstallerName  = "winsdksetup.exe"
$InstallerTemp  = Join-Path $env:TEMP $InstallerName
$InstallerLocal = Join-Path $ScriptDir $InstallerName

# Install SDK Signing Tools if missing
if (-not (Test-Path $SignToolPath)) {
    Write-Host "signtool not found. Installing Windows SDK Signing Tools..." -ForegroundColor Yellow

    $downloadOk = $false
    for ($i=1; $i -le 3; $i++) {
        Write-Host "Download attempt $i of 3..." -ForegroundColor Cyan
        try {
            Invoke-WebRequest $SdkFwlink -OutFile $InstallerTemp -UseBasicParsing -ErrorAction Stop
            if ((Get-Item $InstallerTemp).Length -gt 10240) {
                $downloadOk = $true
                break
            }
        } catch { Start-Sleep 2 }
    }

    if (-not $downloadOk) { Fail "Failed to download SDK installer after 3 attempts." }

    Move-Item $InstallerTemp $InstallerLocal -Force -ErrorAction SilentlyContinue

    Write-Host "Installing SDK Signing Tools..." -ForegroundColor Cyan
    try {
        Start-Process $InstallerLocal -ArgumentList "/quiet","/norestart","/features","OptionId.SigningTools" -Verb RunAs -Wait -ErrorAction Stop
    } catch { Fail "SDK installer failed: $($_.Exception.Message)" }

    if (-not (Test-Path $SignToolPath)) { Fail "Signing Tools still missing after install." }
    Write-Host "signtool installed." -ForegroundColor Green
} else {
    Write-Host "Using existing signtool." -ForegroundColor Green
}

# Warn if running 32-bit PowerShell
if (-not [Environment]::Is64BitProcess) {
    Write-Host "WARNING: Running 32-bit PowerShell. Use 64-bit for best compatibility." -ForegroundColor Yellow
}



# =================================================================================================
# 6. DRIVER EXE HANDLING
# =================================================================================================

Write-Host "Locating AMDDriver.exe..." -ForegroundColor Cyan
$DriverExe = Join-Path $ScriptDir "AMDDriver.exe"

if (-not (Test-Path -LiteralPath $DriverExe)) {
    Fail "No driver EXE named 'AMDDriver.exe' found in script folder. Download the AMD Graphics Driver from https://rog.asus.com/gaming-handhelds/rog-ally/rog-xbox-ally-2025/helpdesk_download/ and place it in the same folder as this script, rename it to AMDDriver.exe."
}

Write-Host "Driver EXE: $DriverExe" -ForegroundColor Green


# Create DRIVERS folder
if (-not (Test-Path $OutDir)) {
    try { New-Item -ItemType Directory -Path $OutDir -ErrorAction Stop | Out-Null }
    catch { Fail "Failed to create DRIVERS folder: $($_.Exception.Message)" }
}

$ExtractRoot = $OutDir



# =================================================================================================
# 7. DOWNLOAD & PATCH HELPER SCRIPTS
# =================================================================================================

$extractScript = Join-Path $ScriptDir "01_extract_driver.ps1"
$patchScript   = Join-Path $ScriptDir "02_driver_patch.ps1"
$baseUrl       = "https://raw.githubusercontent.com/otti83/apu_driver_test/main"

Write-Host "Downloading helper scripts..." -ForegroundColor Cyan
try {
    Invoke-WebRequest "$baseUrl/01_extract_driver.ps1" -OutFile $extractScript -UseBasicParsing -ErrorAction Stop
    Invoke-WebRequest "$baseUrl/02_driver_patch.ps1" -OutFile $patchScript   -UseBasicParsing -ErrorAction Stop
} catch { Fail "Failed to download helper scripts: $($_.Exception.Message)" }

Write-Host "Helper scripts downloaded." -ForegroundColor Green

# Patch helper scripts to use our DRIVERS folder
foreach ($helper in @($extractScript, $patchScript)) {
    try {
        $content = Get-Content $helper -Raw
        $content = $content -replace 'C:\\DRIVERS', [Regex]::Escape($ExtractRoot)
        $content = $content -replace 'C:/DRIVERS', [Regex]::Escape($ExtractRoot)
        Set-Content $helper $content -Encoding UTF8
        Write-Host "Patched paths in: $helper" -ForegroundColor Yellow
    } catch {
        Fail "Failed to patch helper script '$helper': $($_.Exception.Message)"
    }
}



# =================================================================================================
# 8. EXTRACTION, PATCHING & INF TWEAK
# =================================================================================================

# Run extraction
Write-Host "Running extraction script..." -ForegroundColor Cyan
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
& $extractScript -ExePath $DriverExe -OutDir $OutDir -FolderName "" -Force
if ($LASTEXITCODE -ne 0) { Fail "Extraction script failed." }
Write-Host "Extraction completed." -ForegroundColor Green

# Run patch
Write-Host "Running patch script..." -ForegroundColor Cyan
& $patchScript
if ($LASTEXITCODE -ne 0) { Fail "Patch script failed." }
Write-Host "Upstream patch applied." -ForegroundColor Green

# INF tweak
$InfPath = Join-Path $ExtractRoot "Packages\Drivers\Display\WT6A_INF\u0420842.inf"
$BaseLine = '"%AMD163F.2%" = ati2mtag_VanGogh, PCI\VEN_1002&DEV_163F&REV_AF'
$SteamDeckLine = '"%AMD163F.2%" = ati2mtag_VanGogh, PCI\VEN_1002&DEV_163F&SUBSYS_01231002&REV_AE'

if (-not (Test-Path $InfPath)) { Fail "INF not found: $InfPath" }

$infLines = Get-Content $InfPath

if ($infLines -contains $SteamDeckLine) {
    Write-Host "Steam Deck ID already present in INF." -ForegroundColor Yellow
} else {
    $baseIndex = $infLines.IndexOf($BaseLine)
    if ($baseIndex -lt 0) { Fail "Base 163F line not found in INF." }

    $before = $infLines[0..$baseIndex]
    $after  = if ($baseIndex -lt $infLines.Count - 1) { $infLines[($baseIndex + 1)..($infLines.Count - 1)] } else { @() }

    $newLines = $before + $SteamDeckLine + $after
    Set-Content $InfPath $newLines -Encoding ASCII

    Write-Host "Inserted Steam Deck ID into INF." -ForegroundColor Green
}



# =================================================================================================
# 9. CERTIFICATE CREATION & SIGNING
# =================================================================================================

Write-Host "Creating test certificate..." -ForegroundColor Cyan

$CertName     = "SteamDeckTestDriverCert"
$CertPassword = "P@ssw0rd123!"

# Create or reuse certificate
$existing = Get-ChildItem Cert:\LocalMachine\My | Where-Object { $_.Subject -eq "CN=$CertName" } | Select-Object -First 1

if (-not $existing) {
    try {
        $existing = New-SelfSignedCertificate -Type CodeSigningCert -Subject "CN=$CertName" -CertStoreLocation "Cert:\LocalMachine\My"
    } catch { Fail "Failed to create certificate: $($_.Exception.Message)" }
} else {
    Write-Host "Reusing existing certificate." -ForegroundColor Yellow
}

# Export PFX
try {
    $secPwd = ConvertTo-SecureString $CertPassword -AsPlainText -Force
    Export-PfxCertificate -Cert $existing -FilePath $CertPfx -Password $secPwd -Force | Out-Null
} catch { Fail "Failed to export PFX: $($_.Exception.Message)" }

Write-Host "Exported PFX: $CertPfx" -ForegroundColor Green

# Export CER
try {
    Export-Certificate -Cert $existing -FilePath $CertCer -Force | Out-Null
} catch { Fail "Failed to export CER: $($_.Exception.Message)" }

Write-Host "Exported CER: $CertCer" -ForegroundColor Green

# Write password.txt
try {
    $CertPassword | Out-File $PasswordTxt -Encoding ASCII -Force
} catch { Fail "Failed to write password.txt: $($_.Exception.Message)" }

Write-Host "Wrote certificate password to: $PasswordTxt" -ForegroundColor Green

# Sign .sys and .cat files
$filesToSign = Get-ChildItem $ExtractRoot -Recurse -Include *.cat, *.sys -ErrorAction SilentlyContinue

if (-not $filesToSign) {
    Write-Host "No .cat or .sys files found to sign." -ForegroundColor Yellow
} else {
    foreach ($file in $filesToSign) {
        Write-Host "Signing: $($file.FullName)" -ForegroundColor DarkCyan

        $args = @(
            "sign","/fd","SHA256",
            "/f",$CertPfx,
            "/p",$CertPassword,
            "/tr","http://timestamp.digicert.com",
            "/td","SHA256",
            $file.FullName
        )

        try {
            & $SignToolPath @args
            if ($LASTEXITCODE -ne 0) {
                Write-Host "ERROR: signtool returned $LASTEXITCODE for $($file.FullName)" -ForegroundColor Red
            } else {
                Write-Host "Signed OK: $($file.Name)" -ForegroundColor Green
            }
        } catch {
            Write-Host "ERROR: signtool failed for $($file.FullName): $($_.Exception.Message)" -ForegroundColor Red
        }
    }
}



# =================================================================================================
# 10. FINAL OUTPUT
# =================================================================================================

Write-Host ""
Write-Host "DONE. PFX, CER, and password.txt are in the script folder." -ForegroundColor Green
Write-Host "Next steps: disable driver signature enforcement for next boot, then install the INF via Device Manager." -ForegroundColor Green
