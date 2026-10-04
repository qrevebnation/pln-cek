# pln-cek — uninstaller Windows (jalankan satu baris, lihat README)
$ErrorActionPreference = "Continue"
$dir = Join-Path $env:USERPROFILE "pln-re"
$done = @()

# buang folder script + tok.json
if (Test-Path $dir) {
  Remove-Item $dir -Recurse -Force
  $done += "folder $dir (termasuk tok.json)"
}

# buang folder itu dari PATH user
$userPath = [Environment]::GetEnvironmentVariable("Path", "User")
if ($userPath -and $userPath -like "*$dir*") {
  $newPath = (($userPath -split ';' | Where-Object { $_ -and $_.TrimEnd('\') -ne $dir }) -join ';')
  [Environment]::SetEnvironmentVariable("Path", $newPath, "User")
  $done += "entri PATH user"
}

# buang fungsi manual dari profile kalau pernah ditambahkan sendiri
$profilePath = $PROFILE.CurrentUserCurrentHost
if ((Test-Path $profilePath) -and ((Get-Content $profilePath -Raw) -match "function pln-cek")) {
  (Get-Content $profilePath) |
    Where-Object { $_ -notmatch "function pln-(cek|login)" } |
    Set-Content $profilePath
  $done += "fungsi di `$PROFILE"
}

Write-Host ""
if ($done.Count -eq 0) {
  Write-Host "Tidak ada yang terpasang, tidak ada yang dihapus."
} else {
  Write-Host "Terhapus:"
  $done | ForEach-Object { Write-Host "  - $_" }
  Write-Host ""
  Write-Host "Selesai. Buka lagi PowerShell supaya PATH baru terbaca."
}
