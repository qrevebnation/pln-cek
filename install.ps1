# pln-cek — installer Windows (jalankan satu baris, lihat README)
$ErrorActionPreference = "Stop"
$base = "https://raw.githubusercontent.com/qrevebnation/pln-cek/master"
$dir  = Join-Path $env:USERPROFILE "pln-re"

New-Item -ItemType Directory -Force $dir | Out-Null
foreach ($f in @("pln-cek.py", "pln-login.py")) {
  Write-Host "  mengunduh $f ..."
  Invoke-WebRequest "$base/$f" -UseBasicParsing -OutFile (Join-Path $dir $f)
}

# pasang fungsi pln-cek / pln-login ke profile (sekali saja, tidak dobel)
$profilePath = $PROFILE.CurrentUserCurrentHost
if (!(Test-Path $profilePath)) { New-Item -ItemType File -Force $profilePath | Out-Null }
$content = Get-Content $profilePath -Raw
if ($content -notmatch "function pln-cek") {
  Add-Content $profilePath ""
  Add-Content $profilePath "# pln-cek"
  Add-Content $profilePath 'function pln-cek   { py -3 "$env:USERPROFILE\pln-re\pln-cek.py"   @args }'
  Add-Content $profilePath 'function pln-login { py -3 "$env:USERPROFILE\pln-re\pln-login.py" @args }'
}

Write-Host ""
Write-Host "Terpasang di: $dir"
Write-Host "Langkah berikutnya (buka PowerShell BARU supaya fungsi terbaca):"
Write-Host "  pln-login <nomor HP kamu, polos tanpa 0 tanpa 62>"
Write-Host "  pln-cek <IDPEL 12 digit>"
