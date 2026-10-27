# Offline Tailscale installer for Windows. Works from a clone of this repo
# with no access to pkgs.tailscale.com: it uses the MSIs mirror.sh stored
# under releases\ instead.
#
# Usage: powershell -ExecutionPolicy Bypass -File .\install.ps1 [stable|unstable|VERSION]
#
# Uses only cmdlets and native commands (no .NET calls), so it also runs in
# Constrained Language Mode. If PowerShell scripts are blocked outright, use
# install.cmd instead. Needs local admin: Windows asks for it when the MSI runs.

param(
    [Parameter(Position=0)]
    [ValidatePattern('^(stable|unstable|\d+\.\d+\.\d+)$')]
    [string]$Target = "stable"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# PROCESSOR_ARCHITEW6432 is set when 32-bit PowerShell runs on 64-bit Windows.
$arch = $env:PROCESSOR_ARCHITECTURE
if ($env:PROCESSOR_ARCHITEW6432) { $arch = $env:PROCESSOR_ARCHITEW6432 }
switch ($arch) {
    "ARM64" { $arch = "arm64" }
    "AMD64" { $arch = "amd64" }
    "x86"   { $arch = "x86" }
    default {
        Write-Error "Unsupported architecture: $arch"
        exit 1
    }
}

$ReleasesDir = Join-Path $PSScriptRoot "releases"

if ($Target -eq "stable" -or $Target -eq "unstable") {
    $pointer = Join-Path $ReleasesDir $Target
    if (-not (Test-Path $pointer)) {
        Write-Error "No $Target version mirrored. Run mirror.sh first."
        exit 1
    }
    $version = (Get-Content -Raw $pointer).Trim()
} else {
    $version = $Target
}

$archDir = Join-Path (Join-Path $ReleasesDir $version) $arch
$msiPath = Join-Path $archDir "tailscale-setup-$version-$arch.msi"
$checksumFile = Join-Path $archDir "checksum"
if (-not (Test-Path $msiPath) -or -not (Test-Path $checksumFile)) {
    Write-Error "Tailscale $version for $arch is not in this mirror."
    exit 1
}

Write-Output "Installing Tailscale $version ($arch)..."

$checksum = (Get-Content -Raw $checksumFile).Trim()
$actual = (Get-FileHash -Path $msiPath -Algorithm SHA256).Hash.ToLower()
if ($actual -ne $checksum) {
    Write-Error "Checksum verification failed (is the clone complete?)"
    exit 1
}

# Same check Tailscale's own updater does before running an MSI.
$sig = Get-AuthenticodeSignature -FilePath $msiPath
if ($sig.Status -ne "Valid" -or $sig.SignerCertificate.Subject -notmatch 'O="?Tailscale Inc') {
    Write-Error "The MSI is not validly signed by Tailscale Inc. (status: $($sig.Status))"
    exit 1
}

# No route to pkgs.tailscale.com, so turn off update checks and auto-updates.
# Windows shows an admin prompt here if this terminal isn't elevated.
$msiArgs = "/i `"$msiPath`" /passive /norestart TS_CHECKUPDATES=never TS_INSTALLUPDATES=never"
$proc = Start-Process -FilePath "msiexec.exe" -ArgumentList $msiArgs -Wait -PassThru
switch ($proc.ExitCode) {
    0    { }
    3010 { Write-Output "Installed. Restart Windows to finish." }
    1602 { Write-Error "Installation cancelled."; exit 1 }
    default { Write-Error "msiexec failed with exit code $($proc.ExitCode)"; exit 1 }
}

$tsExe = Join-Path $env:ProgramFiles "Tailscale\tailscale.exe"
if (Test-Path $tsExe) { & $tsExe version }

Write-Output ""
Write-Output "$([char]0x2705) Installation complete!"
Write-Output "Sign in from the Tailscale tray icon, or run: tailscale up"
Write-Output ""
