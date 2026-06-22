<#
.SYNOPSIS
  promptring one-line installer (Windows).

.DESCRIPTION
  Usage:
    irm https://pratyansh-agrawal.github.io/promptring/install.ps1 | iex

  Downloads the latest promptring source into a temp directory and runs the
  real installer (install.ps1) - no manual clone required. The temp checkout is
  removed afterward; the install itself lives in ~/.copilot/promptring.

  Pin a branch/tag with $env:PROMPTRING_REF, or point at a custom archive with
  $env:PROMPTRING_TARBALL.
#>
$ErrorActionPreference = 'Stop'
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}

$slug = 'pratyansh-agrawal/promptring'
$ref  = if ($env:PROMPTRING_REF) { $env:PROMPTRING_REF } else { 'main' }
$url  = if ($env:PROMPTRING_TARBALL) { $env:PROMPTRING_TARBALL } else { "https://github.com/$slug/archive/refs/heads/$ref.zip" }

$tmp = Join-Path ([IO.Path]::GetTempPath()) ('promptring-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmp -Force | Out-Null
try {
  Write-Host "> Downloading promptring ($ref)..." -ForegroundColor Cyan
  $zip = Join-Path $tmp 'src.zip'
  Invoke-WebRequest -Uri $url -OutFile $zip -UseBasicParsing
  Expand-Archive -Path $zip -DestinationPath $tmp -Force
  $src = Get-ChildItem -Path $tmp -Directory |
         Where-Object { $_.Name -like 'promptring-*' } | Select-Object -First 1
  if (-not $src -or -not (Test-Path (Join-Path $src.FullName 'install.ps1'))) {
    throw "downloaded archive is missing install.ps1 (check PROMPTRING_REF / network)."
  }
  Write-Host "> Running installer..." -ForegroundColor Cyan
  & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $src.FullName 'install.ps1')
  if ($LASTEXITCODE -ne 0) { throw "promptring installer exited with code $LASTEXITCODE." }
}
finally {
  Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
}
