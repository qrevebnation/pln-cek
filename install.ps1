# pln-cek — installer Windows: bikin command `pln-cek` & `pln-login` sendiri
$ErrorActionPreference = "Stop"
$base = "https://raw.githubusercontent.com/qrevebnation/pln-cek/master"
$dir  = Join-Path $env:USERPROFILE "pln-re"

New-Item -ItemType Directory -Force $dir | Out-Null
foreach ($f in @("pln-cek.py", "pln-login.py")) {
  Write-Host "  mengunduh $f ..."
  Invoke-WebRequest "$base/$f" -UseBasicParsing -OutFile (Join-Path $dir $f)
}

# command sendiri (.cmd) -> cukup ketik pln-cek, tanpa py -3
foreach ($c in @("pln-cek", "pln-login")) {
  $cmd = "@echo off`r`n" +
         "where py >nul 2>nul && (py -3 `"%USERPROFILE%\pln-re\$c.py`" %*) || (python `"%USERPROFILE%\pln-re\$c.py`" %*)"
  [System.IO.File]::WriteAllText((Join-Path $dir "$c.cmd"), $cmd)
}

# masukkan folder script ke PATH user (sekali saja)
$userPath = [Environment]::GetEnvironmentVariable("Path", "User")
if (-not $userPath) { $userPath = "" }
if ($userPath -notlike "*$dir*") {
  [Environment]::SetEnvironmentVariable("Path", ($userPath.TrimEnd(";") + ";" + $dir), "User")
}

Write-Host ""
Write-Host "Terpasang:"
Write-Host "  $dir\pln-cek.cmd    -> pln-cek"
Write-Host "  $dir\pln-login.cmd  -> pln-login"
Write-Host ""
Write-Host "Langkah berikutnya (buka PowerShell BARU supaya PATH terbaca):"
Write-Host "  pln-login <nomor HP kamu, polos tanpa 0 tanpa 62>"
Write-Host "  pln-cek <IDPEL 12 digit>"
