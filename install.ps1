# Bucks Browser — Soul Engine
# One-command installer (Windows PowerShell)
# Usage: irm https://bucks.global/install.ps1 | iex

$ErrorActionPreference = "Stop"

$BucksCid = "bafybeifdjsptd56c5gt4pcsx5w7soo2opoylcdcpoyipdk2ynaybdtklgy"
$InstallDir = Join-Path $HOME ".bucks"
$RepoDir = Join-Path $InstallDir "bucks-browser"

# If this script was downloaded as part of the pinned IPFS folder (alongside
# bucks-browser-dist.tar.gz, rather than piped in via irm|iex), prefer that
# local copy — no network fetch needed at all.
$ScriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { "" }
$LocalTarball = if ($ScriptDir) { Join-Path $ScriptDir "bucks-browser-dist.tar.gz" } else { "" }

# A 200 response only means we got bytes back — not that they're the actual
# tarball. A blocked/misconfigured gateway can serve an HTML error page
# instead, which Invoke-WebRequest happily saves. Check the gzip magic bytes
# before ever trusting a download.
function Test-ValidGzip($path) {
    if (-not (Test-Path $path)) { return $false }
    if ((Get-Item $path).Length -lt 2) { return $false }
    $bytes = [System.IO.File]::ReadAllBytes($path)[0..1]
    return ($bytes[0] -eq 0x1f -and $bytes[1] -eq 0x8b)
}

Write-Host ""
Write-Host "+========================================+"
Write-Host "|        Bucks -- Soul Engine            |"
Write-Host "|     Web3 Browser + AI Runtime          |"
Write-Host "+========================================+"
Write-Host ""

New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
Set-Location $InstallDir

Write-Host "Platform: windows"
Write-Host ""

# -- Check Node.js --------------------------------------------------------
$node = Get-Command node -ErrorAction SilentlyContinue
if (-not $node) {
    Write-Host "Node.js not found. Installing via winget..."
    $winget = Get-Command winget -ErrorAction SilentlyContinue
    if (-not $winget) {
        Write-Host "winget not found either. Install Node.js manually from https://nodejs.org and re-run this script."
        exit 1
    }
    winget install --id OpenJS.NodeJS.LTS -e --accept-source-agreements --accept-package-agreements
    Write-Host "Node.js installed — you may need to open a new terminal for PATH changes to take effect."
    $node = Get-Command node -ErrorAction SilentlyContinue
    if (-not $node) {
        Write-Host "Node.js still not on PATH in this session. Open a new PowerShell window and re-run this script."
        exit 1
    }
}
$nodeVer = node --version
Write-Host "Node.js $nodeVer"

# -- Download Bucks --------------------------------------------------------
if (Test-Path $RepoDir) {
    Write-Host "Bucks already installed at $RepoDir"
} else {
    $downloaded = $false
    $tarballPath = Join-Path $InstallDir "bucks.tar.gz"

    if ($LocalTarball -and (Test-Path $LocalTarball)) {
        Write-Host "Found bucks-browser-dist.tar.gz next to this script -- using it (no download needed)."
        Copy-Item $LocalTarball $tarballPath -Force
        $downloaded = $true
    }

    if (-not $downloaded -and $BucksCid) {
        Write-Host "Downloading Bucks..."
        # cloudflare-ipfs.com deliberately not in this list -- that hostname
        # no longer resolves at all.
        $gateways = @(
            "https://ipfs.io/ipfs",
            "https://dweb.link/ipfs",
            "https://w3s.link/ipfs",
            "https://nftstorage.link/ipfs"
        )
        foreach ($gw in $gateways) {
            try {
                $url = "$gw/$BucksCid/bucks-browser-dist.tar.gz"
                Invoke-WebRequest -Uri $url -OutFile $tarballPath -TimeoutSec 120 -UseBasicParsing
                if (Test-ValidGzip $tarballPath) {
                    Write-Host "Downloaded from IPFS ($gw)"
                    $downloaded = $true
                    break
                }
                Write-Host "  ($gw returned something unusable, trying next...)"
            } catch {
                Write-Host "  ($gw didn't work, trying next...)"
            }
        }
    }

    if (-not $downloaded) {
        Write-Host "Could not download Bucks automatically (every IPFS gateway failed or returned an unusable file)."
        Write-Host ""
        Write-Host "Manual steps:"
        Write-Host "  1. Fetch it yourself once a gateway is reachable, e.g.:"
        Write-Host "     Invoke-WebRequest -Uri https://ipfs.io/ipfs/$BucksCid/bucks-browser-dist.tar.gz -OutFile bucks-browser-dist.tar.gz"
        Write-Host "  2. Run: tar -xzf bucks-browser-dist.tar.gz -C `"$InstallDir`""
        Write-Host "  3. Re-run this script"
        exit 1
    }

    Write-Host "Extracting..."
    New-Item -ItemType Directory -Force -Path $RepoDir | Out-Null
    # Windows 10 1803+ ships bsdtar as `tar` — same as install.sh's approach.
    tar -xzf $tarballPath -C $RepoDir --strip-components=1
    Remove-Item $tarballPath -Force
}

# -- Install dependencies ---------------------------------------------------
Write-Host ""
Write-Host "Installing dependencies..."
Set-Location $RepoDir
npm install --loglevel=error
if (Test-Path (Join-Path $RepoDir "electron")) {
    npm --prefix electron install --loglevel=error
}

# -- Create launcher ---------------------------------------------------------
$LauncherPath = Join-Path $InstallDir "launch-bucks.ps1"
@"
Set-Location "$RepoDir"
npm start
"@ | Out-File -FilePath $LauncherPath -Encoding utf8

# Start Menu shortcut
try {
    $StartMenuDir = Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs"
    $ShortcutPath = Join-Path $StartMenuDir "Bucks.lnk"
    $WshShell = New-Object -ComObject WScript.Shell
    $Shortcut = $WshShell.CreateShortcut($ShortcutPath)
    $Shortcut.TargetPath = "powershell.exe"
    $Shortcut.Arguments = "-NoExit -ExecutionPolicy Bypass -File `"$LauncherPath`""
    $Shortcut.WorkingDirectory = $RepoDir
    $Shortcut.Description = "Bucks — Soul Engine"
    $Shortcut.Save()
    Write-Host "Start Menu shortcut created (Bucks)."
} catch {
    Write-Host "Could not create Start Menu shortcut (non-fatal): $($_.Exception.Message)"
}

# -- Done ---------------------------------------------------------------------
Write-Host ""
Write-Host "+========================================+"
Write-Host "|         Bucks Installed!               |"
Write-Host "+========================================+"
Write-Host ""
Write-Host "To launch:"
Write-Host "  Search 'Bucks' in the Start Menu"
Write-Host "  -- or --"
Write-Host "  powershell -File `"$LauncherPath`""
Write-Host ""
Write-Host "First launch:"
Write-Host "  - App core: ~28 MB"
Write-Host "  - Download AI models from the Component Store"
Write-Host "  - Models load based on your device specs"
Write-Host ""

# -- Auto-launch ---------------------------------------------------------------
$reply = Read-Host "Launch Bucks now? [Y/n]"
if ($reply -eq "" -or $reply -match "^[Yy]") {
    Write-Host "Launching Bucks..."
    Set-Location $RepoDir
    npm start
}
