#requires -RunAsAdministrator
param(
  [Parameter(Mandatory=$true)]
  [string]$ExePath,

  [Parameter(Mandatory=$true)]
  [string]$OutDir,

  # If empty, no rename is performed.
  [string]$FolderName = "",

  # If FolderName already exists, delete it first.
  [switch]$Force
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Find7z {
  $cmd = Get-Command 7z.exe -ErrorAction SilentlyContinue
  if ($cmd) { return $cmd.Source }

  $p1 = Join-Path $env:ProgramFiles "7-Zip\7z.exe"
  if (Test-Path $p1) { return $p1 }

  $p2 = Join-Path ${env:ProgramFiles(x86)} "7-Zip\7z.exe"
  if (Test-Path $p2) { return $p2 }

  return $null
}

function EnsureDir([string]$p) {
  if (-not (Test-Path $p)) { New-Item -ItemType Directory -Path $p | Out-Null }
}

function HasPackagesDrivers([string]$dir) {
  return (Test-Path (Join-Path $dir "Packages\Drivers"))
}

function FindRootChildToRename([string]$outDir, [string[]]$preDirNames) {
  # 1) If OutDir itself has Packages\Drivers, root is OutDir (do not rename OutDir).
  if (HasPackagesDrivers $outDir) { return $outDir }

  # 2) Find a newly-created direct child folder that has Packages\Drivers.
  $postDirs = Get-ChildItem $outDir -Directory -ErrorAction SilentlyContinue
  foreach ($d in $postDirs) {
    if ($preDirNames -notcontains $d.Name) {
      if (HasPackagesDrivers $d.FullName) { return $d.FullName }
    }
  }

  # 3) Minimal fallback: scan only newly-created child folders (depth 2) for Packages\Drivers
  foreach ($d in $postDirs) {
    if ($preDirNames -notcontains $d.Name) {
      $hit = Get-ChildItem $d.FullName -Directory -Recurse -ErrorAction SilentlyContinue |
             Where-Object { Test-Path (Join-Path $_.FullName "Packages\Drivers") } |
             Select-Object -First 1
      if ($hit) { return $hit.FullName }
    }
  }

  return $null
}

# ---- main ----
if (-not (Test-Path $ExePath)) { throw "EXE not found: $ExePath" }

$sevenZip = Find7z
if (-not $sevenZip) { throw "7-Zip not found (7z.exe). Install 7-Zip x64." }

EnsureDir $OutDir

# If the stable target already exists, remove it only when -Force is set
if ($FolderName -and $FolderName.Trim().Length -gt 0) {
  $stablePath = Join-Path $OutDir $FolderName
  if (Test-Path $stablePath) {
    if ($Force) { Remove-Item -Recurse -Force $stablePath }
    else { throw "Target folder already exists. Use -Force." }
  }
}

# Snapshot existing child directories (to detect what got created by extraction)
$preDirNames = @(Get-ChildItem $OutDir -Directory -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name)

# Extract ONCE (no extra copy, no extra harvest)
& $sevenZip x -y ("-o{0}" -f $OutDir) $ExePath | Out-Null

$root = FindRootChildToRename $OutDir $preDirNames
if (-not $root) { throw "Packages\\Drivers not found after extraction." }

# Rename ONLY when root is a direct child of OutDir (no moving/copying)
if ($FolderName -and $FolderName.Trim().Length -gt 0) {
  $parent = Split-Path $root -Parent

  if ($parent -ieq $OutDir) {
    $newPath = Join-Path $OutDir $FolderName
    if ($root -ne $newPath) {
      Rename-Item -LiteralPath $root -NewName $FolderName
      $root = $newPath
    }
  } else {
    # Root is not a direct child (e.g., OutDir itself or nested). Do not move anything.
    # In that case, just output the found root.
  }
}

Write-Host ("EXTRACTED_ROOT={0}" -f $root)
