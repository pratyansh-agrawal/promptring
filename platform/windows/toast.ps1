# ════════════════════════════════════════════════════════════════════
#  toast.ps1 — Windows delivery backend for promptring (render only)
# ════════════════════════════════════════════════════════════════════
#  Receives PRE-COMPOSED banner fields from the orchestrator
#  (bin/promptring.py) and does only the native Windows delivery:
#    * a real WinRT toast under the registered "promptring" app identity
#      (AUMID) — same icon + name as the macOS app,
#    * a Windows Terminal taskbar flash + red pending-count badge,
#    * the per-category sound.
#
#  It performs NO enrichment, NO categories.conf parsing, NO composition —
#  that all lives once, in promptring.py. This keeps a single source of
#  truth and makes the OS layer a thin, dumb renderer.
#
#  Banner layout (identical to macOS promptring):
#      <Title>      e.g. "promptring — my-repo"
#      <Subtitle>   e.g. "✅ Task complete"
#      <Body>       one-line summary
#
#  Silent + never throws.
# ════════════════════════════════════════════════════════════════════
param(
  [string]$Title    = 'promptring',
  [string]$Subtitle = '',
  [string]$Body     = '',
  [string]$Status   = '',
  [string]$Label    = '',
  [string]$Icon     = '',
  [string]$Sound    = '',
  [string]$Aumid    = 'com.promptring.notifier'
)

$ErrorActionPreference = 'SilentlyContinue'

# --- run under Windows PowerShell 5.1 for WinRT toast support -------------
# The WinRT projection (Windows.UI.Notifications) is unavailable in
# PowerShell 7 (Core). If we were launched from Core, re-exec under 5.1.
if ($PSVersionTable.PSEdition -eq 'Core') {
  $winPosh = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
  if (Test-Path $winPosh) {
    $self = $MyInvocation.MyCommand.Path
    & $winPosh -NoProfile -ExecutionPolicy Bypass -File $self `
      -Title $Title -Subtitle $Subtitle -Body $Body -Status $Status `
      -Label $Label -Icon $Icon -Sound $Sound -Aumid $Aumid
    exit $LASTEXITCODE
  }
}

$ScriptDir  = Split-Path -Parent $MyInvocation.MyCommand.Path     # ...\platform\windows
$DllPath    = Join-Path $ScriptDir 'CopilotNotify.dll'
$WatcherPs1 = Join-Path $ScriptDir 'notify-watcher.ps1'
$QueueFile  = Join-Path $env:USERPROFILE '.copilot\notify-queue.json'
$WatcherPid = Join-Path $env:USERPROFILE '.copilot\notify-watcher.pid'

try { [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false) } catch {}

# --- 1. show the toast ---------------------------------------------------
function ConvertTo-XmlText([string]$s) {
  if ($null -eq $s) { return '' }
  return [System.Security.SecurityElement]::Escape($s)
}
try {
  [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] | Out-Null
  [Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime] | Out-Null

  $logoXml = ''
  if ($Icon -and (Test-Path $Icon)) {
    $logoXml = "<image placement=`"appLogoOverride`" src=`"$(ConvertTo-XmlText $Icon)`"/>"
  }
  $subXml  = ''
  if ($Subtitle) { $subXml  = "<text>$(ConvertTo-XmlText $Subtitle)</text>" }
  $bodyXml = ''
  if ($Body)     { $bodyXml = "<text>$(ConvertTo-XmlText $Body)</text>" }

  $xml = @"
<toast>
  <visual>
    <binding template="ToastGeneric">
      $logoXml
      <text>$(ConvertTo-XmlText $Title)</text>
      $subXml
      $bodyXml
    </binding>
  </visual>
  <audio silent="true"/>
</toast>
"@

  $doc = [Windows.Data.Xml.Dom.XmlDocument]::new()
  $doc.LoadXml($xml)
  $notifier = [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($Aumid)
  $notifier.Show([Windows.UI.Notifications.ToastNotification]::new($doc))
} catch { }

# --- 2. taskbar flash + red pending badge --------------------------------
# Track this session in a shared queue so the badge counts pending sessions
# across all tabs; the watcher clears entries as you focus each tab.
try {
  $key = if ($Label) { $Label } elseif ($Title) { $Title } else { "Copilot session $PID" }
  $dir = Split-Path -Parent $QueueFile
  if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force $dir | Out-Null }
  $queue = @()
  if (Test-Path $QueueFile) {
    $raw = Get-Content $QueueFile -Raw
    if ($raw -and $raw.Trim()) {
      $parsed = $raw | ConvertFrom-Json
      $queue = if ($parsed -is [System.Array]) { $parsed } else { @($parsed) }
    }
  }
  $queue = @($queue | Where-Object { $_.title -ne $key })
  $queue += [pscustomobject]@{ title = $key; status = $Status; addedAt = (Get-Date).ToString('o') }
  ($queue | ConvertTo-Json -Depth 5 -Compress) | Set-Content -Path $QueueFile -Encoding utf8
  $count = $queue.Count

  if (Test-Path $DllPath) {
    Add-Type -Path $DllPath -ErrorAction SilentlyContinue
    $wt = Get-Process WindowsTerminal -ErrorAction SilentlyContinue |
          Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
    if ($wt) {
      try { [Copilot.Notify.Badger]::Flash($wt.MainWindowHandle) } catch { }
      try { [Copilot.Notify.Badger]::Set($wt.MainWindowHandle, $count, "$count pending Copilot session(s)") | Out-Null } catch { }
    }
  }

  $running = $false
  if (Test-Path $WatcherPid) {
    $wpid = (Get-Content $WatcherPid -Raw).Trim()
    if ($wpid -match '^\d+$' -and (Get-Process -Id ([int]$wpid) -ErrorAction SilentlyContinue)) { $running = $true }
  }
  if (-not $running -and (Test-Path $WatcherPs1)) {
    Start-Process -FilePath 'powershell.exe' `
      -ArgumentList @('-NoProfile', '-WindowStyle', 'Hidden', '-File', $WatcherPs1) `
      -WindowStyle Hidden | Out-Null
  }
} catch { }

# --- 3. sound (a resolved file path passed by the orchestrator) ----------
try {
  if ($Sound -and (Test-Path $Sound)) {
    $cmd = "Add-Type -AssemblyName PresentationCore; " +
           "`$p = New-Object System.Windows.Media.MediaPlayer; " +
           "`$p.Open([Uri]::new('$Sound')); `$p.Volume = 1.0; `$p.Play(); " +
           "Start-Sleep -Milliseconds 200; `$w = 0; " +
           "while (-not `$p.NaturalDuration.HasTimeSpan -and `$w -lt 1500) { Start-Sleep -Milliseconds 50; `$w += 50 }; " +
           "if (`$p.NaturalDuration.HasTimeSpan) { Start-Sleep -Milliseconds ([int]`$p.NaturalDuration.TimeSpan.TotalMilliseconds + 100) }; " +
           "`$p.Close()"
    Start-Process -FilePath 'powershell.exe' `
      -ArgumentList @('-NoProfile', '-WindowStyle', 'Hidden', '-Command', $cmd) `
      -WindowStyle Hidden | Out-Null
  }
} catch { }

exit 0
