<#
  promptring smoke test - native Windows.

  Fires every notification category through the real orchestrator and
  asserts it exits cleanly and resolves the 'windows' delivery backend.
  Default is DRYRUN (no toasts shown). Pass -Live to pop real toasts.

    powershell -File tests\smoke.ps1          # dry run
    powershell -File tests\smoke.ps1 -Live    # real toasts + sound
#>
param([switch]$Live)

$Repo = Split-Path -Parent $PSScriptRoot
$Pr   = Join-Path $Repo 'bin\promptring.py'
$py   = (Get-Command python -ErrorAction SilentlyContinue).Source
if (-not $py) { $py = (Get-Command python3 -ErrorAction SilentlyContinue).Source }
if (-not $py) { Write-Host "python not found"; exit 1 }

$cats = 'done', 'input', 'ready', 'blocked', 'info'
$fail = $false
Write-Host "platform: expecting backend 'windows'"

foreach ($c in $cats) {
  if ($Live) {
    & $py $Pr $c "smoke: $c"
    if ($LASTEXITCODE -eq 0) { Write-Host "  OK $c  (live, exit 0)" }
    else { Write-Host "  XX $c  exit $LASTEXITCODE"; $fail = $true }
    Start-Sleep -Seconds 1
  } else {
    $env:PROMPTRING_DRYRUN = '1'
    $out = & $py $Pr $c "smoke: $c"
    $rc = $LASTEXITCODE
    Remove-Item Env:PROMPTRING_DRYRUN
    if ($rc -ne 0) { Write-Host "  XX $c  exit $rc"; $fail = $true; continue }
    try { $spec = $out | ConvertFrom-Json } catch { Write-Host "  XX $c  bad json"; $fail = $true; continue }
    if ($spec.platform -eq 'windows' -and $spec.body -eq "smoke: $c") {
      Write-Host "  OK $c  -> $($spec.platform)"
    } else {
      Write-Host "  XX $c  backend='$($spec.platform)' body='$($spec.body)'"; $fail = $true
    }
  }
}

$env:PROMPTRING_DRYRUN = '1'
& $py $Pr 'made-up' 'x' | Out-Null
if ($LASTEXITCODE -eq 0) { Write-Host "  OK unknown-category degrades" } else { Write-Host "  XX unknown-category failed"; $fail = $true }
Remove-Item Env:PROMPTRING_DRYRUN

if ($fail) { Write-Host "smoke: FAIL"; exit 1 } else { Write-Host "smoke: PASS"; exit 0 }
