<#
.SYNOPSIS
    Install and run the bot on Windows, supervised so it comes back after a
    Telegram-triggered self-update or a crash.

.DESCRIPTION
    The Windows counterpart to run_linux.sh, minus the parts Windows does not need:
    there are no dependencies to install (the binary is self-contained) and no tmux
    equivalent - this console window IS the session.

    What it does need is the supervising loop. Settings-change restarts already work
    on Windows without help, because BotRestarter spawns a successor when the in-place
    execvp path is unavailable. A SELF-UPDATE does not: with no supervisor in sight the
    bot prints "please rerun the binary" and exits. Setting INVOCATION_ID tells it a
    supervisor exists, so it exits cleanly for the loop below to restart.

    Closing this window stops the bot. To keep it running unattended, register it as a
    Windows Service (NSSM, sc.exe) or a Scheduled Task set to "Run whether user is
    logged on or not" - a script cannot detach itself the way tmux does.

.PARAMETER BotDir
    Where to install. Defaults to the folder holding this script.

.EXAMPLE
    .\run_windows.ps1
    First run downloads the binary and starts the bot. Later runs just start it.

.EXAMPLE
    .\run_windows.ps1 -BotDir C:\knopka-groshu
    Install into another folder.
#>
[CmdletBinding()]
param(
    [string] $BotDir = $PSScriptRoot
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$releasesRepo = 'envoydev/knopka-groshu-trading-bot'
$exeName = 'knopka-groshu.exe'

New-Item -ItemType Directory -Path $BotDir -Force | Out-Null
Set-Location -Path $BotDir
$exePath = Join-Path $BotDir $exeName

# First run on a fresh machine: fetch the release build for this architecture. Later
# runs skip it - the bot's own self-update owns the binary from then on.
if (-not (Test-Path -Path $exePath)) {
    $arch = switch ([System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture) {
        'X64'   { 'x64' }
        'Arm64' { 'arm64' }
        default {
            throw ("Unsupported architecture " +
                "$([System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture) - " +
                'only x64 and arm64 are published.')
        }
    }

    $asset = "knopka-groshu-win-$arch.exe"
    $url = "https://github.com/$releasesRepo/releases/latest/download/$asset"
    Write-Host "  v Downloading $asset ..."

    # Windows PowerShell renders a progress bar per byte block, which makes a 45 MB
    # download take minutes instead of seconds. Suppressing it is the documented fix.
    $previousProgress = $ProgressPreference
    $ProgressPreference = 'SilentlyContinue'
    try {
        # Land it under a .part name first: an interrupted transfer must not leave a
        # truncated file that the next run mistakes for an installed binary.
        $partPath = "$exePath.part"
        Invoke-WebRequest -Uri $url -OutFile $partPath -UseBasicParsing
        # Clear the mark-of-the-web so the first launch is not blocked as a download.
        Unblock-File -Path $partPath
        Move-Item -Path $partPath -Destination $exePath -Force
    }
    finally {
        $ProgressPreference = $previousProgress
    }

    Write-Host ''
}

# Optional, and only for an operator pinning their own KG_MASTER_KEY - a migrated
# database, or a key from a secret store. Left alone, the bot mints and manages its
# own key in data\master.key.
$envFile = Join-Path $BotDir '.env'
if (Test-Path -Path $envFile) {
    foreach ($line in Get-Content -Path $envFile) {
        $trimmed = $line.Trim()
        if (-not $trimmed -or $trimmed.StartsWith('#')) { continue }

        $split = $trimmed.IndexOf('=')
        if ($split -lt 1) { continue }

        $name = $trimmed.Substring(0, $split).Trim()
        $value = $trimmed.Substring($split + 1).Trim().Trim('"', "'")
        Set-Item -Path "Env:$name" -Value $value
    }
    Write-Host "  * Loaded environment overrides from .env"
}

# Tells SelfUpdateService a supervisor owns the restart, so it exits cleanly for the
# loop below instead of prompting for a manual rerun. Only ever set this together with
# the loop - on its own it leaves the bot down after an update.
$env:INVOCATION_ID = 'windows-supervisor'

while ($true) {
    & $exePath
    $code = $LASTEXITCODE
    Write-Host "  ^ exited ($code) - relaunching in 3s (Ctrl-C to stop)"
    Start-Sleep -Seconds 3
}
