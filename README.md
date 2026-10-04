# pln-cek

Cek daya PLN (VA) dan koordinat IDPEL dari terminal atau PowerShell. Tidak perlu HP atau
emulator, juga tidak perlu membuka aplikasi PLN Mobile.

Kodenya Python stdlib, jadi tidak ada `pip install` apa pun. Login cukup sekali lewat
WhatsApp, token kemudian dipakai selama ±91 hari. Riwayat enam bulan ada di opsi `--usage`.

Semua nilai yang muncul di repo ini, IDPEL, nomor meter, nama pemilik, nomor telepon, kota,
koordinat, sampai angka tagihan, sudah diganti atau dibulatkan. File token `tok.json` masuk
`.gitignore`.

Yang dibutuhkan: Python 3.10 ke atas (`python3 --version` atau `py -3 --version`), `curl`
atau `wget`, dan nomor HP yang bisa menerima WhatsApp. Git hanya dipakai pada instalasi manual.

---

## 1. Instalasi

Satu baris. Untuk terminal Linux atau macOS:

```bash
curl -fsSL https://raw.githubusercontent.com/qrevebnation/pln-cek/master/install.sh | bash
```

Untuk PowerShell di Windows:

```powershell
iwr https://raw.githubusercontent.com/qrevebnation/pln-cek/master/install.ps1 -UseBasicParsing | iex
```

Installer mengunduh `pln-cek.py` dan `pln-login.py` ke `~/pln-re`, atau ke
`%USERPROFILE%\pln-re` di Windows, lalu mendaftarkan command `pln-cek` dan `pln-login`.
Di Linux command itu berupa file executable di `~/.local/bin`, di Windows berupa
`pln-cek.cmd` yang direktorinya ditambahkan ke PATH user. Menjalankan installer dua kali
tidak membuat salinan ganda.

Selesai, tinggal buka terminal baru atau jalankan `source ~/.bashrc`. PATH user baru dibaca
saat sesi dimulai, jadi terminal lama tidak akan mengenali command barunya.

<details>
<summary>Instalasi manual, butuh git</summary>

```bash
# Linux / macOS
git clone https://github.com/qrevebnation/pln-cek.git
mkdir -p ~/pln-re && cp pln-cek/pln-cek.py pln-cek/pln-login.py ~/pln-re/
```

```powershell
# Windows PowerShell
git clone https://github.com/qrevebnation/pln-cek.git
cd pln-cek
New-Item -ItemType Directory -Force "$env:USERPROFILE\pln-re" | Out-Null
Copy-Item pln-cek.py,pln-login.py "$env:USERPROFILE\pln-re\"
```

Tanpa installer, command `pln-cek` tidak ada. Jalankan file-nya langsung dengan
`python3 ~/pln-re/pln-cek.py <IDPEL>` atau
`py -3 "$env:USERPROFILE\pln-re\pln-cek.py" <IDPEL>`.

</details>

Token disimpan di `~/pln-re/tok.json` (atau `%USERPROFILE%\pln-re\tok.json`) secara otomatis.
Tidak ada konfigurasi tambahan.

---

## 2. Login OTP

Bagian ini tidak bisa dilewati, karena kode OTP masuk ke WhatsApp milikmu sendiri.

```bash
pln-login 81234567890
```

Nomornya ditulis polos: tanpa `0` di depan, tanpa `62`. Kalau ditulis `0812...` atau
`62812...`, server tetap membalas "berhasil terkirim" dan pesan WhatsApp tetap sampai, tapi
kode loginnya tidak pernah dibuat sehingga proses selalu gagal.

Urutan langkahnya:

1. Jalankan perintah di atas, lalu tunggu baris
   `kode terkirim ke WhatsApp 812... (canResendInSec=60)`.
2. Buka WhatsApp, cari pesan dari PLN, salin enam angkanya.
3. Kembali ke terminal. Saat muncul `masukkan kode OTP:`, tempel kode itu lalu tekan Enter.
4. Baris `token tersimpan di .../tok.json` muncul bersama sisa masa berlaku token.
   Dari sini perintah login tidak perlu dijalankan lagi selama ±91 hari.

Kalau gagal, pesannya menjelaskan penyebabnya:

| Pesan | Artinya | Yang dilakukan |
|---|---|---|
| `Kode verifikasi tidak sesuai.` | kode salah | ulangi dengan kode yang benar |
| `Kode verifikasi tidak ditemukan.` | format nomor salah atau kode kadaluarsa | cek lagi aturan nomor polos di atas |
| `Terlalu banyak percobaan kode verifikasi.` | akun dikunci sementara | tunggu, jangan diulang |
| `token hilang: jalankan login OTP dulu` | belum pernah login | jalankan langkah ini |

Satu kode berlaku untuk satu kali percobaan. Lima kali berturut-turut salah, akun dikunci.

---

## 3. Cek IDPEL

Perintahnya sama di Linux, macOS, dan Windows.

```bash
pln-cek 123456789012
```

Ganti `123456789012` dengan IDPEL dua belas digit milikmu, angka yang ada di tagihan, STRL,
atau aplikasi PLN.

```bash
# beberapa IDPEL sekaligus, jeda default dua detik antar IDPEL
pln-cek 111111111111 222222222222 333333333333

# perbesar jeda antar IDPEL, dalam detik
pln-cek --gap=5 123456789012

# sekalian riwayat enam bulan, kWh dan rupiah
pln-cek --usage 123456789012
```

Hasilnya kira-kira seperti ini:

```
123456789012  daya=2200VA R1T  lat=-6.2 lon=106.9
  prepaid •••••••••••  00000 - <NAMA UP>
  pemilik: PELANGGI CONTOH A (B)
  JL ••••••••••••••••••••••••••••
```

Dengan `--usage` muncul tambahan riwayat:

```
  riwayat 6 bulan (blth, kwh, rupiah):
    202610  kwh=1250  rp=1800000
    202609  kwh=1350  rp=2000000
    ...
```

`energy` adalah daya dalam VA, `energyType` golongan tarifnya (R1, R2, B2, dan seterusnya),
`latitude` dan `longitude` koordinat meter. `type` membedakan prepaid dan postpaid.
Nilai `address` sudah ditutup oleh server, jadi yang terlihat hanya awalan jalannya.

---

## 4. Aturan main

1. Jeda dua detik antar IDPEL sudah jadi default. Kalau kena `429`, naikkan jadi `--gap=5`.
2. Access token hanya berlaku satu jam, tapi `pln-cek.py` memperbaruinya sendiri sehingga
   OTP tidak diminta lagi. Refresh token bertahan ±91 hari. Endpoint refresh-nya punya rate
   limit sendiri, kena `429` berarti tunggu sekitar 45 detik.
3. Jangan publikasikan isi response mentah. Di dalamnya ada NIK pemilik meter, dan pada meter
   prabayar juga ada nomor token yang belum terpakai, yang nilainya uang.
4. `tok.json` adalah rahasia. Jangan dikirim ke siapa pun dan jangan ikut ter-commit.
5. Endpoint ini tidak resmi dan bisa berubah sewaktu-waktu. Pemakaian dan ToS PLN jadi
   tanggung jawab masing-masing.

---

## 5. Uninstall

Sama seperti instalasi, semuanya satu baris. Untuk Linux atau macOS:

```bash
curl -fsSL https://raw.githubusercontent.com/qrevebnation/pln-cek/master/uninstall.sh | bash
```

Untuk PowerShell:

```powershell
iwr https://raw.githubusercontent.com/qrevebnation/pln-cek/master/uninstall.ps1 -UseBasicParsing | iex
```

Uninstaller menghapus command `pln-cek` dan `pln-login`, folder `pln-re` beserta `tok.json`,
entri PATH yang tadi ditambahkan installer, dan blok `# pln-cek` di `~/.bashrc`. Dijalankan
dua kali juga tidak masalah, dia cuma akan bilang kalau memang sudah tidak ada yang terpasang.

Menghapus file tidak mencabut token yang sudah terlanjur terbit di server PLN. Kalau mau
dicabut, keluar dari aplikasi PLN Mobile di HP kamu. Refresh token ikut mati, dan login
berikutnya meminta OTP baru.

<details>
<summary>Tanpa uninstaller, jalankan manual</summary>

```bash
# Linux / macOS
rm -f ~/.local/bin/pln-cek ~/.local/bin/pln-login
rm -rf ~/pln-re
```

```powershell
# Windows PowerShell
Remove-Item "$env:USERPROFILE\pln-re" -Recurse -Force
$p = [Environment]::GetEnvironmentVariable("Path","User")
[Environment]::SetEnvironmentVariable("Path",
  (($p -split ';' | Where-Object { $_ -and $_ -ne "$env:USERPROFILE\pln-re" }) -join ';'),
  "User")
```

Kalau kamu memasang fungsi sendiri lewat `notepad $PROFILE`, hapus baris `function pln-cek`
dan `function pln-login`. Blok di `~/.bashrc` dihapus dengan `nano ~/.bashrc`, simpan, lalu
`source ~/.bashrc`.

</details>

---

## 6. Troubleshooting

| Gejala | Penyebab | Solusi |
|---|---|---|
| `'pln-cek' tidak dikenal` / `not recognized` | PATH belum terbaca | Linux: `source ~/.bashrc`. Windows: buka PowerShell baru |
| `token hilang: jalankan login OTP dulu` | belum pernah login | jalankan langkah 2 |
| `401 permintaan tidak diotorisasi` | access token kadaluarsa atau korup | biarkan script refresh; kalau tetap gagal, hapus `tok.json` lalu login ulang |
| `429 Too Many Requests` | rate limit | tunggu, lalu query lagi dengan `--gap=5` |
| `IDPel/Nomor Meter yang Anda masukan salah` | IDPEL salah ketik | periksa lagi dua belas digitnya |
| `500 V000` di riwayat | path diisi IDPEL | pakai `--usage`, script otomatis memakai id internal |
| `Kode verifikasi tidak ditemukan` | format nomor OTP salah | pakai nomor polos tanpa `0` dan tanpa `62` |
| `python: command not found` / `py : term ...` | Python belum terpasang | unduh dari python.org dan centang Add to PATH |
| Karakter `•` jadi `?` atau berantakan di Windows | konsol bukan UTF-8 | jalankan `chcp 65001` lalu `$env:PYTHONUTF8="1"` |
| respons berbeda dari dokumentasi | PLN mengganti API | cek header `x-plnmobile-version: 8.1.1` |

---

## 7. File lain di repo ini

| File | Isi |
|---|---|
| `install.sh` / `install.ps1` | installer satu baris yang mendaftarkan command `pln-cek` dan `pln-login` |
| `uninstall.sh` / `uninstall.ps1` | uninstaller satu baris yang menghapus command, folder `pln-re`, dan entri PATH |
| `pln-cek.py` | query IDPEL, mengembalikan daya, lat/long, dan pemilik, dengan refresh token otomatis |
| `pln-login.py` | login OTP sekali jalan, menulis `tok.json` |
| `PLN-CEK-DAYA-API.md` | referensi lengkap: seluruh endpoint, header, katalog status 200/404/500, bukti uji, risiko PII |

### Alamat jalan dari koordinat

Nilai `address` dari PLN tidak bisa dibuka, tapi koordinatnya utuh. Balik ke alamat lewat
Nominatim milik OpenStreetMap:

```bash
curl -A 'pln-cek/1.0' \
  'https://nominatim.openstreetmap.org/reverse?lat=-7.9&lon=112.7&format=jsonv2&zoom=18'
# → <nama jalan>, <kelurahan>, <kecamatan>, <kab/kota>, <provinsi> <kodepos>
```

Nominatim membatasi satu request per detik dan mewajibkan header `User-Agent`. Simpan hasil
per koordinat supaya 500 meter tidak dihitung ulang berkali-kali, dan cantumkan atribusi
© OpenStreetMap contributors. Kalau gagal atau timeout, biarkan, jangan diulang terus.

---

## Riwayat perubahan

| Versi | Perubahan |
|---|---|
| v1 | tutor awal: `check` (daya + lat/long) dan login OTP |
| v2 | `--usage` untuk riwayat enam bulan, `get()` generik, baris `pemilik:` |
| v2.1 | tagihan lewat titanium, alamat via OSM, tabel perbandingan `name` dan `aliasName` |
| v3 | tutorial untuk manusia di terminal dan PowerShell, seluruh contoh disanitasi |
| v3.1 | installer satu baris, `chcp` dipindah ke troubleshooting |
| v3.2 | command sendiri `pln-cek` dan `pln-login` di PATH, tanpa `python3` |
| v3.3 | penyuntingan gaya bahasa dan bagian uninstall |
| v3.4 | uninstall jadi satu baris lewat `uninstall.sh` / `uninstall.ps1` |
