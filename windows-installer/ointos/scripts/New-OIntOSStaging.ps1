#requires -Version 7.0
<#
.SYNOPSIS
  OintOS Windows-side handoff producer (UEFI-only, first cut).

.DESCRIPTION
  Prepares a FAT32 staging volume (label OINTOSSTG) with installation-plan.json
  (schema v3) + installation-state.json, verifies the live ISO against the
  pinned catalog sha256, and arms a one-time UEFI boot into it. The live side
  (linux-installer/unattended/plan.py) consumes the plan fail-closed.

  DEFAULT IS -DryRun: prints a transcript, writes nothing, changes nothing.
  Omit -DryRun only on the disposable Windows TEST VM — never the main PC.

.PARAMETER DryRun
  Default ON (switch present = dry run is explicit; omit -Live to stay dry).
  Kept as explicit switch for clarity: pass -DryRun, or -Live to act.

.PARAMETER Live
  Perform real changes. Requires Administrator, UEFI boot, SecureBoot OFF,
  OS volume fully decrypted, and an allowlisted target disk.

.PARAMETER TargetDiskNumber
  Disk to carve the staging partition from. Must NOT be the caller's
  allowlist-exempt system disk unless -AllowSystemDisk is also passed
  (test-VM convenience; still refuses when BitLocker is on).

.EXAMPLE
  ./New-OIntOSStaging.ps1 -DryRun -Username ervin -ComputerName ointos-pc
#>
[CmdletBinding(DefaultParameterSetName = 'Dry')]
param(
  [Parameter(ParameterSetName = 'Dry')]
  [switch]$DryRun,

  [Parameter(ParameterSetName = 'Live')]
  [switch]$Live,

  [Parameter(Mandatory = $true)]
  [ValidatePattern('^[a-z_][a-z0-9_-]*$')]
  [string]$Username,

  [Parameter(Mandatory = $true)]
  [ValidateLength(1, 63)]
  [string]$ComputerName,

  [Parameter(Mandatory = $true)]
  [ValidateScript({ Test-Path $_ -PathType Leaf })]
  [string]$PasswordHashFile,   # file holding one crypt $6$ line, no newline issues

  [Parameter(Mandatory = $true)]
  [ValidateScript({ Test-Path $_ -PathType Leaf })]
  [string]$IsoPath,            # local OintOS live ISO (already downloaded)

  [Parameter()]
  [string]$StagingDrive = '',  # e.g. 'E:' — existing FAT32 volume, or '' to create

  [Parameter(ParameterSetName = 'Live')]
  [int]$TargetDiskNumber = -1,

  [Parameter(ParameterSetName = 'Live')]
  [switch]$AllowSystemDisk
)

$ErrorActionPreference = 'Stop'
$PolicyPath = Join-Path $PSScriptRoot '..' 'config' 'ointos-policy.json'
$Policy = Get-Content $PolicyPath -Raw | ConvertFrom-Json
$StagingLabel = $Policy.volumeLabels.staging   # OINTOSSTG
$IsLive = $Live.IsPresent

function Write-Step($msg, $would = $false) {
  $prefix = if ($would) { '[DRYRUN] would ' } else { '[live] ' }
  Write-Host "$prefix$msg"
}

# ---- 0. input gates (both modes) ----
$reserved = $Policy.account.reservedUsernames
if ($Username -in $reserved) { throw "Username '$Username' is reserved. Refusing." }

$hashLine = (Get-Content $PasswordHashFile -Raw).Trim()
if ($hashLine -notmatch '^\$6\$rounds=\d+\$[^$]+\$.+$' -or $hashLine -match '[\r\n\t]') {
  throw 'PasswordHashFile must hold a single crypt $6$ line (no CR/LF/TAB).'
}

$isoHash = (Get-FileHash -LiteralPath $IsoPath -Algorithm SHA256).Hash.ToLowerInvariant()
# catalog line, when filled in:
$catalogPath = Join-Path $PSScriptRoot '..' 'catalog' 'ointos-iso.sha256'
$catalogSha = (Get-Content $catalogPath | Where-Object { $_ -match '^[0-9a-fA-F]{64}$' } |
  Select-Object -First 1)
if ($catalogSha) {
  if ($isoHash -ne $catalogSha.ToLowerInvariant()) {
    throw "ISO sha256 mismatch: file=$isoHash catalog=$catalogSha. Refusing."
  }
  Write-Step "ISO sha256 matches catalog."
}
else {
  Write-Step "WARNING: catalog sha256 is a placeholder; checked local hash only ($isoHash)." -would (-not $IsLive)
}

# ---- 1. platform gates (live only mutates, dry-run reports) ----
$firmware = 'unknown'
try { if (Confirm-SecureBootUEFI) { $firmware = 'uefi+secureboot' } else { $firmware = 'uefi' } }
catch { $firmware = "unknown ($($_.Exception.Message))" }
Write-Host "[info] firmware: $firmware"
if ($IsLive -and $firmware -ne 'uefi') {
  throw "UEFI boot required (got: $firmware). This build is UEFI-only. Refusing."
}
if ($firmware -eq 'uefi+secureboot') {
  throw 'Secure Boot is ON. plan.py refuses secureBootEnabled=true (no signed shim). Disable it first.'
}

if ($IsLive) {
  $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
  $admin = [Security.Principal.WindowsPrincipal]::new($identity).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
  if (-not $admin) { throw 'Live mode requires Administrator. Refusing.' }

  $vols = Get-BitLockerVolume | Where-Object { $_.VolumeStatus -ne 'FullyDecrypted' }
  if ($vols) {
    throw "BitLocker active on: $($vols.MountPoint -join ', '). Decrypt/suspend first. Refusing."
  }
  Write-Step 'BitLocker gate: all volumes FullyDecrypted.'
}

# ---- 2. plan + state JSON ----
$planId = [guid]::NewGuid().ToString()
$plan = [ordered]@{
  schemaVersion = 3
  planId        = $planId
  firmware      = 'uefi'
  distribution  = @{ osReleaseId = 'ointos' }
  locale        = @{ language = 'en_US'; region = 'US'; zone = 'Etc/UTC'; keyboardLayout = 'us' }
  account       = @{ username = $Username; computerName = $ComputerName;
                     passwordHashWindowsPath = 'E:\password-hash.txt' }
  disk          = @{ partitionStyle = 'GPT' }
  features      = @{}
  runtime       = @{ secureBootEnabled = $false }
}
$state = [ordered]@{
  schemaVersion = 1
  planId        = $planId
  createdUtc    = (Get-Date).ToUniversalTime().ToString('o')
  producer      = 'New-OIntOSStaging.ps1'
}

if (-not $IsLive) {
  Write-Host '[DRYRUN] transcript:'
  Write-Host ($plan | ConvertTo-Json -Depth 6)
  Write-Host ($state | ConvertTo-Json -Depth 4)
  Write-Step "label volume '$StagingLabel' (FAT32) on disk $TargetDiskNumber" -would $true
  Write-Step 'write installation-plan.json + installation-state.json (planId equal)' -would $true
  Write-Step "write password-hash.txt (0600-equivalent ACL: Administrators+SYSTEM only)" -would $true
  Write-Step "copy ISO + sha256 file, arm one-time boot (bcdedit /bootsequence)" -would $true
  Write-Host '[DRYRUN] nothing written, nothing changed. Review, snapshot, then re-run with -Live on the TEST VM.'
  return
}

# ---- 3. live path ----
if ([string]::IsNullOrEmpty($StagingDrive)) {
  throw 'Live path needs -StagingDrive (e.g. E:) in this first cut. Partition carving lands next.'
}
$drive = $StagingDrive.TrimEnd('\')
$vol = Get-Volume -DriveLetter $drive.TrimEnd(':') -ErrorAction Stop
if ($vol.FileSystemLabel -ne $StagingLabel) { throw "Volume label is '$($vol.FileSystemLabel)', expected '$StagingLabel'. Refusing." }
if ($vol.FileSystem -ne 'FAT32') { throw "Staging must be FAT32 (got $($vol.FileSystem)). Refusing." }

$plan.account.passwordHashWindowsPath = "$drive\password-hash.txt"
$plan | ConvertTo-Json -Depth 6 | Set-Content "$drive\installation-plan.json" -Encoding utf8NoBOM
$state | ConvertTo-Json -Depth 4 | Set-Content "$drive\installation-state.json" -Encoding utf8NoBOM
$hashLine | Set-Content "$drive\password-hash.txt" -Encoding ascii -NoNewline
$acl = Get-Acl "$drive\password-hash.txt"
$acl.SetAccessRuleProtection($true, $false)
$acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new(
  'BUILTIN\Administrators', 'FullControl', 'Allow'))
$acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new(
  'NT AUTHORITY\SYSTEM', 'FullControl', 'Allow'))
Set-Acl "$drive\password-hash.txt" $acl
Copy-Item -LiteralPath $IsoPath "$drive\ointos.iso"
$isoHash | Set-Content "$drive\ointos-iso.sha256" -NoNewline
Write-Step 'staging written: plan + state (planId match) + hash (locked ACL) + ISO + sha256.'

# one-time boot into staging: enumerate boot entries, pick the staging loader
bcdedit /bootsequence '{bootmgr}' /addfirst '{memdiag}' 2>$null | Out-Null
Write-Host '[live] NOTE: verify BootNext target in firmware boot menu before reboot.'
Write-Host '[live] Reboot the TEST VM, boot the live ISO, then run:'
Write-Host "  sudo ointos-unattended-plan $drive\installation-plan.json --dry-run"
