# AMD Custom Driver Analysis & Patching Guide

## Overview

This document provides a comprehensive guide for analyzing and patching AMD graphics drivers
to work with different devices.

Example: ROG Ally Driver → Steam Deck Custom Driver

---

## 1. Problem Identification

### 1.1 Check Device Manager for Errors

After installing the driver, check GPU status in Device Manager:

```powershell
Get-PnpDevice | Where-Object { $_.FriendlyName -like "*AMD*" -or $_.FriendlyName -like "*Radeon*" } | Select-Object FriendlyName, Status, Problem
```

Common error codes:
- `CM_PROB_FAILED_START` (Code 43) - Device initialization failed
- `CM_PROB_FAILED_POST_START` - Post-start initialization failed
- `CM_PROB_DRIVER_FAILED_LOAD` - Driver load failed

### 1.2 Get Error Details from Event Log

```powershell
# Search for AMD-related events
Get-WinEvent -LogName System | Where-Object { $_.ProviderName -like "*amd*" -or $_.Message -like "*amdkmdag*" } | Select-Object -First 20 TimeCreated, Id, Message
```

### 1.3 Decode Error Messages

If Event ID 3085 shows an empty Message, extract data from Properties:

```powershell
Get-WinEvent -LogName System | Where-Object { $_.Id -eq 3085 } | Select-Object -First 1 | ForEach-Object { $_.Properties | ForEach-Object { $_.Value } }
```

If output is a number sequence, convert from ASCII codes:

```powershell
# Convert number sequence to ASCII
$bytes = @(65,77,68,71,67,70,32,118,101,114,105,102,105,99,97,116,105,111,110)
[System.Text.Encoding]::ASCII.GetString($bytes)
# Result: "AMDGCF verification"
```

---

## 2. Driver Binary Analysis

### 2.1 Search for Error Strings

Search for error messages within the driver file (amdkmdag.sys):

```powershell
$path = "C:\path\to\amdkmdag.sys"
Select-String -Path $path -Pattern "AMDGCF" -Encoding ascii
```

### 2.2 Find File Offset of String

```powershell
$bytes = [System.IO.File]::ReadAllBytes($path)
$pattern = [System.Text.Encoding]::ASCII.GetBytes("AMDGCF verification failed")

for ($i = 0; $i -lt $bytes.Length - $pattern.Length; $i++) {
    $match = $true
    for ($j = 0; $j -lt $pattern.Length; $j++) {
        if ($bytes[$i + $j] -ne $pattern[$j]) { $match = $false; break }
    }
    if ($match) { 
        Write-Host "String found at file offset: 0x$($i.ToString('X'))"
        break 
    }
}
```

### 2.3 Get PE Section Information

Get section info to calculate correct virtual addresses in Ghidra:

```powershell
$bytes = [System.IO.File]::ReadAllBytes($path)
$e_lfanew = [BitConverter]::ToInt32($bytes, 0x3C)
$sizeOfOptionalHeader = [BitConverter]::ToInt16($bytes, $e_lfanew + 4 + 16)
$sectionHeadersStart = $e_lfanew + 4 + 20 + $sizeOfOptionalHeader
$numberOfSections = [BitConverter]::ToInt16($bytes, $e_lfanew + 4 + 2)

Write-Host "Sections:"
for ($i = 0; $i -lt $numberOfSections; $i++) {
    $sectionOffset = $sectionHeadersStart + ($i * 40)
    $name = [System.Text.Encoding]::ASCII.GetString($bytes[$sectionOffset..($sectionOffset+7)]).TrimEnd([char]0)
    $virtualAddress = [BitConverter]::ToInt32($bytes, $sectionOffset + 12)
    $rawAddress = [BitConverter]::ToInt32($bytes, $sectionOffset + 20)
    Write-Host "  $name : VA=0x$($virtualAddress.ToString('X')) Raw=0x$($rawAddress.ToString('X'))"
}
```

---

## 3. Analysis with Ghidra

### 3.1 Installation and Setup

1. Install Java 17 or higher: https://adoptium.net/
2. Download Ghidra: https://ghidra-sre.org/
3. Launch with `ghidraRun.bat`

### 3.2 Import File

1. File → New Project → Non-Shared Project
2. File → Import File → Select amdkmdag.sys
3. Format auto-detected (PE format)
4. Double-click to open CodeBrowser
5. Click "Yes" on "Analyze?" → Analyze (takes several minutes)

### 3.3 Search for Error Strings

1. Search → For Strings...
2. Minimum Length: 10
3. Click Search
4. Type "AMDGCF" in Filter
5. Double-click the matching string

### 3.4 Find Referencing Code

At the string location, check for:

```
DAT_14079cdf0    XREF[1]:  FUN_140052c50:140052e74(*)
```

This means "function FUN_140052c50 at address 140052e74 references this string."

Jump to the reference:
1. Navigation → Go To... (or press G)
2. Enter reference address (e.g., 140052e74)

### 3.5 Review Decompiled Code

In the Decompile window on the right, review C-like code:

```c
iVar14 = FUN_140056b50(param_1, ...);  // Verification function
if (iVar14 < 0) {
    // Verification failed → Error message
    FUN_14004e010(param_1, "AMDGCF verification failed...");
}
```

### 3.6 Analyze Verification Function

Jump to verification function (e.g., FUN_140056b50) and examine:

```c
// Load amdgcf.dat
iVar2 = FUN_1400e5b10(&local_48, L"amdgcf.dat", 0, 0);

// Device ID / Revision check
if (uVar6 == param_2) {           // Device ID check
    if (*(byte *)(...) == param_3) // Revision check
        break;
}
```

---

## 4. Calculate Patch Offset

### 4.1 Virtual Address → File Offset Conversion

Ghidra addresses are Virtual Addresses (VA). Convert to file offset:

```
File Offset = VA - Section VA + Section Raw Address
```

Example (for .text section):
- Function VA: 0x140056b50
- ImageBase: 0x140000000
- RVA: 0x56b50 (= VA - ImageBase)
- .text VA: 0x1000
- .text Raw: 0xA00

```
File Offset = 0x56b50 - 0x1000 + 0xA00 = 0x56550
```

### 4.2 Automatic Calculation with PowerShell

```powershell
$bytes = [System.IO.File]::ReadAllBytes($path)
$rva = 0x56b50  # Ghidra address - ImageBase

$e_lfanew = [BitConverter]::ToInt32($bytes, 0x3C)
$numberOfSections = [BitConverter]::ToInt16($bytes, $e_lfanew + 4 + 2)
$sizeOfOptionalHeader = [BitConverter]::ToInt16($bytes, $e_lfanew + 4 + 16)
$sectionHeadersStart = $e_lfanew + 4 + 20 + $sizeOfOptionalHeader

for ($i = 0; $i -lt $numberOfSections; $i++) {
    $sectionOffset = $sectionHeadersStart + ($i * 40)
    $virtualAddress = [BitConverter]::ToInt32($bytes, $sectionOffset + 12)
    $virtualSize = [BitConverter]::ToInt32($bytes, $sectionOffset + 8)
    $rawAddress = [BitConverter]::ToInt32($bytes, $sectionOffset + 20)
    
    if ($rva -ge $virtualAddress -and $rva -lt ($virtualAddress + $virtualSize)) {
        $fileOffset = $rva - $virtualAddress + $rawAddress
        Write-Host "File offset: 0x$($fileOffset.ToString('X'))"
        Write-Host "Current bytes:"
        Write-Host ($bytes[$fileOffset..($fileOffset+4)] | ForEach-Object { $_.ToString('X2') }) -Separator ' '
        break
    }
}
```

---

## 5. Apply Patch

### 5.1 Types of Bypass Patches

**Method A: Immediate Return (Recommended)**

Overwrite the beginning of verification function:

```asm
xor eax, eax    ; 31 C0  (return value = 0 = success)
ret             ; C3     (return immediately)
nop             ; 90     (padding)
nop             ; 90
```

Byte sequence: `31 C0 C3 90 90`

**Method B: Modify Conditional Jump**

```asm
jnz FAIL  →  jmp FAIL  (always jump)
jnz FAIL  →  nop nop   (never jump)
```

### 5.2 Apply Patch with PowerShell

```powershell
$path = "C:\path\to\amdkmdag.sys"
$backupPath = $path + ".bak"
$offset = 0x56550  # Calculated offset

# Backup
Copy-Item $path $backupPath -Force

# Read
$bytes = [System.IO.File]::ReadAllBytes($path)

# Verify before patch
Write-Host "Before:" ($bytes[$offset..($offset+4)] | ForEach-Object { $_.ToString('X2') }) -Separator ' '

# Apply patch
$patch = [byte[]]@(0x31, 0xC0, 0xC3, 0x90, 0x90)
for ($i = 0; $i -lt $patch.Length; $i++) {
    $bytes[$offset + $i] = $patch[$i]
}

# Write
[System.IO.File]::WriteAllBytes($path, $bytes)

# Verify after patch
Write-Host "After: " ($bytes[$offset..($offset+4)] | ForEach-Object { $_.ToString('X2') }) -Separator ' '
```

---

## 6. Edit INF File

### 6.1 Add Device HWID

Check target device HWID:

```powershell
Get-PnpDevice | Where-Object { $_.Class -eq "Display" } | Get-PnpDeviceProperty -KeyName DEVPKEY_Device_HardwareIds | Select-Object -ExpandProperty Data
```

Add entry to appropriate section of INF file:

```ini
"%AMD163F.2%" = ati2mtag_VanGogh, PCI\VEN_1002&DEV_163F&SUBSYS_01231002&REV_AE
```

---

## 7. Driver Signing

### 7.1 Create Self-Signed Certificate

```powershell
$CertName = "AMD Driver Signing Certificate"
$Cert = New-SelfSignedCertificate `
    -Type CodeSigningCert `
    -Subject "CN=$CertName" `
    -KeyUsage DigitalSignature `
    -KeyAlgorithm RSA `
    -KeyLength 2048 `
    -CertStoreLocation "Cert:\CurrentUser\My" `
    -NotAfter (Get-Date).AddYears(5)
```

### 7.2 Add Certificate to Trust Stores

```powershell
$RootStore = New-Object System.Security.Cryptography.X509Certificates.X509Store("Root", "LocalMachine")
$RootStore.Open("ReadWrite")
$RootStore.Add($Cert)
$RootStore.Close()

$PublisherStore = New-Object System.Security.Cryptography.X509Certificates.X509Store("TrustedPublisher", "LocalMachine")
$PublisherStore.Open("ReadWrite")
$PublisherStore.Add($Cert)
$PublisherStore.Close()
```

### 7.3 Sign the Driver

```powershell
$SignTool = "C:\Program Files (x86)\Windows Kits\10\bin\10.0.XXXXX.0\x64\signtool.exe"
$CertExportPath = "C:\DriverCert.pfx"
$CertPassword = "YourPassword"

# Export certificate
$SecurePassword = ConvertTo-SecureString -String $CertPassword -Force -AsPlainText
Export-PfxCertificate -Cert $Cert -FilePath $CertExportPath -Password $SecurePassword

# Remove catalog file (avoid hash mismatch)
Remove-Item "u0420842.cat" -Force

# Sign
& $SignTool sign /fd SHA256 /f $CertExportPath /p $CertPassword /tr http://timestamp.digicert.com /td SHA256 "amdkmdag.sys"
```

---

## 8. Installation and Boot

### 8.1 Enable Test Signing Mode

```cmd
bcdedit /set testsigning on
bcdedit /set nointegritychecks on
```

### 8.2 Temporarily Disable Signature Enforcement (For Initial Testing)

```cmd
shutdown /r /o /t 0
```

After reboot:
1. Troubleshoot
2. Advanced options
3. Startup Settings
4. Restart
5. Press F7 - Disable driver signature enforcement

### 8.3 Manual Driver Installation

1. Open Device Manager
2. Right-click AMD Radeon Graphics
3. Update driver
4. Browse my computer for drivers
5. Let me pick from a list → Have Disk
6. Browse to INF file

---

## 9. Troubleshooting

### 9.1 Code 43 Not Resolved

- Verify patch offset is correct
- Investigate for other verification logic

### 9.2 Code 52 (Signature Error)

- Check test signing is enabled: `bcdedit | findstr testsigning`
- Disable Memory Integrity: Settings → Windows Security → Device Security → Core Isolation

### 9.3 Code 39 (Driver Load Failed)

- Check application control policy
- Run `bcdedit /set nointegritychecks on`

---

## 10. Reference: This Patch Details

### Steam Deck + ROG Ally Driver Case

| Item | Value |
|------|-------|
| Driver | amdkmdag.sys (32.0.21025.27003) |
| Problem | AMDGCF verification failed |
| Verification Function VA | 0x140056b50 |
| File Offset | 0x56550 (353616) |
| Original Bytes | 48 89 5C 24 18 |
| Patch Bytes | 31 C0 C3 90 90 |
| INF Entry | "%AMD163F.2%" = ati2mtag_VanGogh, PCI\VEN_1002&DEV_163F&SUBSYS_01231002&REV_AE |

---

## Disclaimer

This guide is provided for technical research purposes only.
Driver modification is done at your own risk.
