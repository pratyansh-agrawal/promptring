<#
.SYNOPSIS
  promptring installer for native Windows.

.DESCRIPTION
  Installs the cross-platform promptring notifier for the Copilot CLI on
  native Windows:
    1. Copies the orchestrator + platform backends into
       ~/.copilot/promptring  (same layout/location as macOS & Linux).
    2. Generates app/icon.ico from icon.png and registers a Windows app
       identity (AUMID com.promptring.notifier) so toasts show the
       "promptring" name + app icon — the same identity as the macOS app.
    3. Merges the Copilot CLI hooks into ~/.copilot/hooks/hooks.json (your
       existing hooks are preserved). On Windows the CLI runs the hook's
       `powershell` command, which invokes `python promptring.py`.

  One Python orchestrator drives delivery; the WinRT toast + taskbar badge
  run via Windows PowerShell 5.1 (python shells out to it). Idempotent:
  re-running refreshes everything in place.

.PARAMETER NoTest
  Skip the test banner at the end.
#>
param([switch]$NoTest)

$ErrorActionPreference = 'Stop'

function Write-Step($m) { Write-Host "`n> $m" -ForegroundColor Cyan }
function Write-Ok($m)   { Write-Host "  OK $m" -ForegroundColor Green }
function Write-Warn2($m){ Write-Host "  !  $m" -ForegroundColor Yellow }
function Write-Info($m) { Write-Host "     $m" -ForegroundColor DarkGray }

Write-Host ""
Write-Host "  +-------------------------------+" -ForegroundColor Cyan
Write-Host "  |  promptring  .  install (win) |" -ForegroundColor Cyan
Write-Host "  +-------------------------------+" -ForegroundColor Cyan

# --- paths ---------------------------------------------------------------
$Repo = $PSScriptRoot
if (-not (Test-Path (Join-Path $Repo 'bin\promptring.py'))) {
  throw "Run install.ps1 from the promptring repo root (bin\promptring.py not found)."
}
$CopilotDir = Join-Path $env:USERPROFILE '.copilot'
$HomeDir    = Join-Path $CopilotDir 'promptring'
$HooksDst   = Join-Path $CopilotDir 'hooks\hooks.json'
$HooksSrc   = Join-Path $Repo 'hooks.json'
$Instructions      = Join-Path $CopilotDir 'copilot-instructions.md'
$InstructionsBlock = Join-Path $Repo 'copilot-instructions.block.md'
$Aumid      = 'com.promptring.notifier'
Write-Info "repo: $Repo"

# --- python is required (single orchestrator) ----------------------------
$py = (Get-Command python -ErrorAction SilentlyContinue).Source
if (-not $py) { $py = (Get-Command python3 -ErrorAction SilentlyContinue).Source }
if (-not $py) {
  Write-Warn2 "python not found — promptring's orchestrator requires it."
  Write-Info  "Install Python 3 (https://www.python.org/downloads/, check 'Add to PATH') and re-run."
  exit 1
}

# --- 1. copy runtime into ~/.copilot/promptring --------------------------
Write-Step "Installing into $HomeDir"
if (Test-Path $HomeDir) { Remove-Item $HomeDir -Recurse -Force }
New-Item -ItemType Directory -Force $HomeDir | Out-Null
foreach ($d in @('bin', 'sounds', 'platform')) {
  Copy-Item (Join-Path $Repo $d) (Join-Path $HomeDir $d) -Recurse -Force
}
New-Item -ItemType Directory -Force (Join-Path $HomeDir 'app') | Out-Null
Copy-Item (Join-Path $Repo 'app\icon.png') (Join-Path $HomeDir 'app') -Force
Copy-Item (Join-Path $Repo 'app\icon.svg') (Join-Path $HomeDir 'app') -Force -ErrorAction SilentlyContinue
Copy-Item (Join-Path $Repo 'categories.conf') $HomeDir -Force
Get-ChildItem $HomeDir -Recurse -Directory -Filter '__pycache__' | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
Write-Ok "copied orchestrator + config + sound + platform backends"

# --- 2. generate icon.ico from icon.png ----------------------------------
Write-Step "Generating app icon"
$iconPng = Join-Path $HomeDir 'app\icon.png'
$iconIco = Join-Path $HomeDir 'app\icon.ico'
function New-IcoFromPng {
  param([string]$PngPath, [string]$IcoPath, [int[]]$Sizes = @(16, 32, 48, 64, 128, 256))
  Add-Type -AssemblyName System.Drawing
  $src = [System.Drawing.Image]::FromFile($PngPath)
  try {
    $side = [Math]::Min($src.Width, $src.Height)
    $sx = [int](($src.Width - $side) / 2)
    $sy = [int](($src.Height - $side) / 2)
    $square = New-Object System.Drawing.Bitmap $side, $side
    $g0 = [System.Drawing.Graphics]::FromImage($square)
    $g0.DrawImage($src, (New-Object System.Drawing.Rectangle 0, 0, $side, $side),
                  (New-Object System.Drawing.Rectangle $sx, $sy, $side, $side),
                  [System.Drawing.GraphicsUnit]::Pixel)
    $g0.Dispose()
    $pngs = @()
    foreach ($sz in $Sizes) {
      $bmp = New-Object System.Drawing.Bitmap $sz, $sz
      $g = [System.Drawing.Graphics]::FromImage($bmp)
      $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
      $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
      $g.DrawImage($square, 0, 0, $sz, $sz)
      $g.Dispose()
      $ms = New-Object System.IO.MemoryStream
      $bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
      $pngs += , @{ Size = $sz; Bytes = $ms.ToArray() }
      $bmp.Dispose(); $ms.Dispose()
    }
    $square.Dispose()
    $fs = [System.IO.File]::Open($IcoPath, 'Create')
    $bw = New-Object System.IO.BinaryWriter $fs
    $bw.Write([uint16]0); $bw.Write([uint16]1); $bw.Write([uint16]$pngs.Count)
    $offset = 6 + 16 * $pngs.Count
    foreach ($p in $pngs) {
      $dim = if ($p.Size -ge 256) { 0 } else { $p.Size }
      $bw.Write([byte]$dim); $bw.Write([byte]$dim)
      $bw.Write([byte]0); $bw.Write([byte]0)
      $bw.Write([uint16]1); $bw.Write([uint16]32)
      $bw.Write([uint32]$p.Bytes.Length)
      $bw.Write([uint32]$offset)
      $offset += $p.Bytes.Length
    }
    foreach ($p in $pngs) { $bw.Write($p.Bytes) }
    $bw.Flush(); $bw.Close(); $fs.Close()
  } finally { $src.Dispose() }
}
try {
  New-IcoFromPng -PngPath $iconPng -IcoPath $iconIco
  Write-Ok "icon.ico generated"
} catch {
  Write-Warn2 "icon.ico generation failed ($($_.Exception.Message)); toast logo still uses icon.png"
}

# --- 3. register the Windows app identity (AUMID) ------------------------
Write-Step "Registering app identity (toast name + icon)"
try {
  $key = "HKCU:\Software\Classes\AppUserModelId\$Aumid"
  if (-not (Test-Path $key)) { New-Item -Path $key -Force | Out-Null }
  New-ItemProperty -Path $key -Name 'DisplayName' -Value 'promptring' -PropertyType String -Force | Out-Null
  $iconForReg = if (Test-Path $iconIco) { $iconIco } else { $iconPng }
  New-ItemProperty -Path $key -Name 'IconUri' -Value $iconForReg -PropertyType String -Force | Out-Null
  New-ItemProperty -Path $key -Name 'IconBackgroundColor' -Value 'FFF24D63' -PropertyType String -Force | Out-Null
  Write-Ok "registered AUMID $Aumid"
} catch {
  Write-Warn2 "AUMID registration failed: $($_.Exception.Message)"
  Write-Info  "Toasts still appear, just without the custom name/icon."
}

# --- 4. unblock files ----------------------------------------------------
Write-Step "Unblocking files"
Get-ChildItem $HomeDir -Recurse -File | Unblock-File -ErrorAction SilentlyContinue
Write-Ok "files unblocked"

# --- 5. merge the Copilot CLI notification hooks -------------------------
Write-Step "Installing Copilot CLI notification hooks"
New-Item -ItemType Directory -Force (Split-Path -Parent $HooksDst) | Out-Null
& $py (Join-Path $HomeDir 'bin\merge-hooks.py') add $HooksDst $HooksSrc
if ($LASTEXITCODE -eq 0) {
  Write-Ok "merged hooks -> $HooksDst (existing hooks preserved)"
} else {
  Write-Warn2 "$HooksDst could not be merged; merge $HooksSrc manually."
}

# --- 6. clean up legacy install ------------------------------------------
$legacyWin = Join-Path $CopilotDir 'promptring-win'
if (Test-Path $legacyWin) { Remove-Item $legacyWin -Recurse -Force -ErrorAction SilentlyContinue; Write-Info "removed legacy ~/.copilot/promptring-win" }

# --- 7. install the promptring instruction block -------------------------
#  The hooks cover permission_prompt, elicitation_dialog and agentStop, but
#  the Copilot CLI fires NO hookable event when the agent pauses mid-turn on
#  the built-in `ask_user` tool — so under --yolo a decision prompt shows no
#  banner. We close that gap by instructing the agent to fire the notifier
#  itself before calling ask_user. The block is fenced by markers so it can
#  be refreshed/removed cleanly; its text is the single shared source in
#  copilot-instructions.block.md.
Write-Step "Installing promptring instruction block"
New-Item -ItemType Directory -Force (Split-Path -Parent $Instructions) | Out-Null
$existing = if (Test-Path $Instructions) { Get-Content -LiteralPath $Instructions } else { @() }
# strip any previous promptring block, preserving your other content
$kept = New-Object System.Collections.Generic.List[string]
$skip = $false
foreach ($line in $existing) {
  if ($line -match 'promptring:start') { $skip = $true; continue }
  if ($skip) { if ($line -match 'promptring:end') { $skip = $false }; continue }
  $kept.Add($line)
}
# drop trailing blank lines so the appended block sits cleanly
while ($kept.Count -gt 0 -and [string]::IsNullOrWhiteSpace($kept[$kept.Count - 1])) {
  $kept.RemoveAt($kept.Count - 1)
}
$block = Get-Content -LiteralPath $InstructionsBlock
$out = New-Object System.Collections.Generic.List[string]
$out.AddRange($kept)
if ($kept.Count -gt 0) { $out.Add('') }
$out.AddRange([string[]]$block)
Set-Content -LiteralPath $Instructions -Value $out -Encoding UTF8
Write-Ok "instruction block written -> $Instructions"

# --- done ----------------------------------------------------------------
if ($NoTest) {
  Write-Warn2 "Skipping test banner (-NoTest)"
} else {
  Write-Step "Firing a test banner"
  try {
    & $py (Join-Path $HomeDir 'bin\promptring.py') done 'promptring works'
    Write-Ok "test fired - expect a toast (promptring icon) + the tring chime"
  } catch {
    Write-Warn2 "test banner failed: $($_.Exception.Message)"
  }
}

Write-Host ""
Write-Host "promptring installed." -ForegroundColor Green
Write-Host "Next steps" -ForegroundColor White
Write-Info "1. Fire a test banner:"
Write-Info "     python `"$HomeDir\bin\promptring.py`" done `"hello`""
Write-Info "2. Restart your Copilot CLI session so the hook loads."
Write-Info "Everything lives under ~/.copilot/promptring now - you can delete this clone."
Write-Host ""
