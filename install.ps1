# Bucks Browser — Soul Engine
# One-command installer (Windows PowerShell)
# Usage: irm https://bucks.global/install.ps1 | iex

$ErrorActionPreference = "Stop"

$BucksCid = "bafybeifdjsptd56c5gt4pcsx5w7soo2opoylcdcpoyipdk2ynaybdtklgy"
# sha256 of the exact tarball this CID points at. Updated together with
# $BucksCid on every release — see scripts/build-and-pin-release.js, which
# already computes this hash for every artifact it pins.
$BucksSha256 = "5922b76129929cfe963a89259917d21206d7c3c5a33a574deb98fa4be106ceae"
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

# The gzip-magic-byte check catches a gateway serving an error page, but not
# a connection that just dropped mid-transfer — that also leaves a file that
# starts with valid gzip bytes, it's just truncated. Verifying the full
# contents against the known-good hash for this release catches that case
# too, for any source (gateway, mirror, or the local sibling-file copy).
function Test-ValidDownload($path) {
    if (-not (Test-ValidGzip $path)) { return $false }
    if (-not $BucksSha256) { return $true }
    $actual = (Get-FileHash -Path $path -Algorithm SHA256).Hash
    return ($actual -eq $BucksSha256)
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

    if ($LocalTarball -and (Test-Path $LocalTarball) -and (Test-ValidDownload $LocalTarball)) {
        Write-Host "Found bucks-browser-dist.tar.gz next to this script -- using it (no download needed)."
        Copy-Item $LocalTarball $tarballPath -Force
        $downloaded = $true
    }

    if (-not $downloaded -and $BucksCid) {
        Write-Host "Downloading Bucks..."
        # cloudflare-ipfs.com deliberately not in this list -- that hostname
        # no longer resolves at all. w3s.link and nftstorage.link currently
        # redirect to dweb.link's own backend, so in practice this is closer
        # to 2-way redundancy -- ipfs.io vs. everything else -- not 4-way.
        # Kept as 4 entries anyway since that redirect target is Protocol
        # Labs' own choice to change at any time, and a redirecting-but-
        # reachable gateway is still strictly better than one fewer attempt.
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
                if (Test-ValidDownload $tarballPath) {
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

    # Last resort: a same-origin HTTPS mirror. Every gateway above depends on
    # this release's CID being reachable over IPFS at all -- a separate
    # failure mode from bucks.global itself being up. This mirror needs
    # nothing IPFS-specific to work, so it's the most independent fallback
    # available.
    if (-not $downloaded) {
        Write-Host "All IPFS gateways failed -- trying the direct mirror..."
        try {
            Invoke-WebRequest -Uri "https://bucks.global/dl/bucks-browser-dist.tar.gz" -OutFile $tarballPath -TimeoutSec 120 -UseBasicParsing
            if (Test-ValidDownload $tarballPath) {
                Write-Host "Downloaded from bucks.global mirror"
                $downloaded = $true
            }
        } catch {
            # falls through to the manual-steps message below
        }
    }

    if (-not $downloaded) {
        Write-Host "Could not download Bucks automatically (every IPFS gateway and the direct mirror failed or returned an unusable file)."
        Write-Host ""
        Write-Host "This is usually temporary -- gateway/network issues, not a broken release. What to do:"
        Write-Host "  1. Wait a few minutes and re-run:"
        Write-Host "     irm https://bucks.global/install.ps1 | iex"
        Write-Host "  2. Still failing? Fetch the file yourself from any one of these, then continue below:"
        Write-Host "     Invoke-WebRequest -Uri https://dweb.link/ipfs/$BucksCid/bucks-browser-dist.tar.gz -OutFile bucks-browser-dist.tar.gz"
        Write-Host "     Invoke-WebRequest -Uri https://bucks.global/dl/bucks-browser-dist.tar.gz -OutFile bucks-browser-dist.tar.gz"
        Write-Host "     Invoke-WebRequest -Uri https://ipfs.io/ipfs/$BucksCid/bucks-browser-dist.tar.gz -OutFile bucks-browser-dist.tar.gz"
        Write-Host "  3. Run: New-Item -ItemType Directory -Force -Path `"$RepoDir`"; tar -xzf bucks-browser-dist.tar.gz -C `"$RepoDir`" --strip-components=1"
        Write-Host "  4. Re-run this script -- it'll detect the install and skip straight to dependencies"
        Write-Host ""
        Write-Host "  Still stuck? https://github.com/shafeeqduddiyanda/bucks.global/issues"
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
