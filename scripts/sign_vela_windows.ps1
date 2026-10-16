# Optional Authenticode signing for Vela Windows portable distributions.
# A trusted publisher certificate is required to display a verified publisher.
# Do not substitute a self-signed or ephemeral runner certificate.
param(
  [Parameter(Mandatory=$true)][string]$ReleaseDirectory
)

$ErrorActionPreference = 'Stop'
$hasPfx = -not [string]::IsNullOrWhiteSpace($env:VELA_WINDOWS_CODESIGN_PFX_B64)
$hasPassword = -not [string]::IsNullOrWhiteSpace($env:VELA_WINDOWS_CODESIGN_PASSWORD)
if (-not $hasPfx -and -not $hasPassword) {
  Write-Host 'Windows Authenticode signing not configured: portable executables remain unsigned.'
  exit 0
}
if (-not $hasPfx -or -not $hasPassword) {
  throw 'Incomplete Windows Authenticode configuration (PFX and password required).'
}

$sdkBin = Join-Path ([Environment]::GetFolderPath('ProgramFilesX86')) 'Windows Kits\10\bin'
$signtool = Get-ChildItem $sdkBin -Filter signtool.exe -Recurse -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -match '\\x64\\signtool\.exe$' } |
    Sort-Object FullName -Descending | Select-Object -First 1
if (-not $signtool) { throw 'Windows SDK signtool.exe not found on runner' }

$pfx = Join-Path $env:RUNNER_TEMP 'vela-publisher-signing.pfx'
try {
  [System.IO.File]::WriteAllBytes($pfx,
      [Convert]::FromBase64String($env:VELA_WINDOWS_CODESIGN_PFX_B64))
  foreach ($rel in @('Vela.exe', 'core\FlClashCore.exe', 'core\mihomo.exe')) {
    $exe = Join-Path $ReleaseDirectory $rel
    if (-not (Test-Path $exe)) { throw "Windows executable missing before signing: $rel" }
    & $signtool.FullName sign /fd SHA256 /tr 'http://timestamp.digicert.com' /td SHA256 /f $pfx /p $env:VELA_WINDOWS_CODESIGN_PASSWORD $exe
    if ($LASTEXITCODE -ne 0) { throw "Authenticode signing failed: $rel" }
    & $signtool.FullName verify /pa $exe
    if ($LASTEXITCODE -ne 0) { throw "Authenticode verification failed: $rel" }
    $signature = Get-AuthenticodeSignature -FilePath $exe
    if ($signature.Status -ne 'Valid') {
      throw "Publisher signing chain not trusted for $rel : $($signature.Status)"
    }
    Write-Host "Trusted Windows publisher signature verified for $rel"
  }
} finally {
  Remove-Item -LiteralPath $pfx -Force -ErrorAction SilentlyContinue
}
