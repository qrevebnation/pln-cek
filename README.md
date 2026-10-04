# pln-cek

Cek **daya (VA)** + **koordinat lat/long** IDPEL PLN langsung dari **terminal (Linux/macOS)**
atau **PowerShell (Windows)** — tanpa HP, tanpa emulator, tanpa aplikasi PLN Mobile.

- Python **murni stdlib** → `pip install` **tidak perlu**
- Login OTP sekali lewat WhatsApp → token awet ±91 hari
- Ada riwayat kWh 6 bulan (`--usage`)

> **Contoh = data contoh.** IDPEL, nomor meter, nama pemilik, nomor telepon, kode gardu,
> nama kota/UP, angka kWh & tagihan, serta lat/long site (dibulatkan 1 desimal) pada semua
> contoh dan dokumen di repo ini sudah **disanitasi** — bukan nilai asli. `tok.json` masuk `.gitignore`.

---

## Persyaratan

| Kebutuhan | Cek |
|---|---|
| Python 3.10+ | `python3 --version` (Linux/macOS) · `py -3 --version` (Windows) |
| Git | `git --version` |
| Internet ke `connect-gateway.pln.co.id` | — |
| Nomor HP yang bisa menerima **WhatsApp** | untuk OTP, sekali saja |

---

## 1. Instalasi

### Linux / macOS (terminal)

```bash
git clone https://github.com/qrevebnation/pln-cek.git
mkdir -p ~/pln-re
cp pln-cek/pln-cek.py pln-cek/pln-login.py ~/pln-re/
cd ~/pln-re
python3 --version
```

Token disimpan otomatis di `~/pln-re/tok.json`.

### Windows (PowerShell)

```powershell
# 1. Python dari python.org, lalu buka PowerShell
py -3 --version

# 2. Ambil repo
git clone https://github.com/qrevebnation/pln-cek.git
cd pln-cek

# 3. Simpan script (folder dibuat otomatis)
New-Item -ItemType Directory -Force "$env:USERPROFILE\pln-re" | Out-Null
Copy-Item pln-cek.py,pln-login.py "$env:USERPROFILE\pln-re\"
cd "$env:USERPROFILE\pln-re"

# 4. Konsol UTF-8 supaya karakter • tampil benar
chcp 65001
$env:PYTHONUTF8 = "1"
```

Token disimpan otomatis di `$env:USERPROFILE\pln-re\tok.json`.

---

## 2. Login OTP — sekali saja, butuh manusia

Agent/kode tidak bisa menerima WhatsApp, jadi langkah ini dikerjakan sendiri.

**Linux / macOS**

```bash
cd ~/pln-re
python3 pln-login.py 81234567890
```

**PowerShell**

```powershell
cd "$env:USERPROFILE\pln-re"
py -3 pln-login.py 81234567890
```

> Ganti `81234567890` dengan **nomor WhatsApp kamu**, format **POLOS**:
> tanpa `0` di depan, tanpa `62`. Format `0812…` / `62812…` → server tetap bilang
> "berhasil terkirim", kode masuk WhatsApp, tapi **kode tidak pernah terbentuk** → login gagal.

**Step by step:**

1. Jalankan perintah di atas → tunggu muncul:
   `kode terkirim ke WhatsApp 812... (canResendInSec=60)`
2. Buka WhatsApp → cari pesan dari PLN → **salin kode 6 digit**.
3. Kembali ke terminal, diminta:
   ```
   masukkan kode OTP:
   ```
   tempel kode itu, tekan **Enter**.
4. Muncul `token tersimpan di .../tok.json` + lama berlakunya token → **selesai**.
   Perintah di atas **tidak perlu dijalankan lagi** (±91 hari).

**Kode salah / gagal:**

| Pesan | Artinya | Action |
|---|---|---|
| `Kode verifikasi tidak sesuai.` | kode salah | coba lagi dengan kode yang benar |
| `Kode verifikasi tidak ditemukan.` | format nomor salah / kode kadaluarsa | cek aturan nomor polos di atas |
| `Terlalu banyak percobaan kode verifikasi.` | kena **lock** | tunggu, jangan diulang |
| `tidak ditemukan` saat request | format request salah | pakai nomor polos |

**Aturan keras:** satu kode = satu percobaan. Sekitar 5 kali salah → terkunci.

---

## 3. Cek IDPEL — langkah utama

**Linux / macOS**

```bash
cd ~/pln-re
python3 pln-cek.py 123456789012
```

**PowerShell**

```powershell
cd "$env:USERPROFILE\pln-re"
py -3 pln-cek.py 123456789012
```

> Ganti `123456789012` dengan **IDPEL kamu (12 digit)** — angka di tagihan/STRL/pln-mobile.

**Variasi perintah:**

```bash
# beberapa IDPEL sekaligus (jeda default 2 detik antar IDPEL)
python3 pln-cek.py 111111111111 222222222222 333333333333

# jeda antar IDPEL diperbesar (detik)
python3 pln-cek.py --gap=5 123456789012

# sekalian riwayat 6 bulan (kWh + rupiah)
python3 pln-cek.py --usage 123456789012
```

**Output contoh:**

```
123456789012  daya=2200VA R1T  lat=-6.2 lon=106.9
  prepaid •••••••••••  00000 - <NAMA UP>
  pemilik: PELANGGI CONTOH A (B)
  JL ••••••••••••••••••••••••••••
```

Dengan `--usage`:

```
  riwayat 6 bulan (blth, kwh, rupiah):
    202610  kwh=1250  rp=1800000
    202609  kwh=1350  rp=2000000
    ...
```

**Arti field:** `energy` = daya (VA) · `energyType` = golongan tarif (R1, R2, B2, …) ·
`latitude`/`longitude` = koordinat (di-contoh sudah dibulatkan) · `type` = prepaid/postpaid ·
`address` di-mask oleh server.

---

## 4. Perintah singkat (opsional)

Supaya tidak perlu mengetik `python3 …` tiap kali.

**Linux/macOS** — tambahkan ke `~/.bashrc`:

```bash
alias pln-cek='python3 ~/pln-re/pln-cek.py'
alias pln-login='python3 ~/pln-re/pln-login.py'
```

lalu `source ~/.bashrc`. Pemakaian: `pln-cek 123456789012`.

**PowerShell** — tambahkan ke profile (`notepad $PROFILE`):

```powershell
function pln-cek   { py -3 "$env:USERPROFILE\pln-re\pln-cek.py"   @args }
function pln-login { py -3 "$env:USERPROFILE\pln-re\pln-login.py" @args }
```

lalu reload: `. $PROFILE`. Pemakaian: `pln-cek 123456789012`.

---

## 5. Aturan main

1. **Jeda ≥2 detik** antar IDPEL (sudah default). Kena `429` → naikkan jadi `--gap=5`.
2. **Token 1 jam** → `pln-cek.py` refresh sendiri, tidak perlu OTP lagi.
   Refresh token berlaku ±91 hari; kena `429` di endpoint refresh → tunggu ±45 detik.
3. **Jangan publikasikan response mentah.** Response memuat `nik` pemilik meter, dan untuk
   prabayar juga `tokenNumber` token yang belum terpakai (nilai uang).
4. `tok.json` = rahasia. Jangan dikirim ke siapa pun, jangan ikut di-commit (sudah masuk `.gitignore`).
5. Endpoint ini **tidak resmi** dan bisa berubah sewaktu-waktu; ToS PLN jadi tanggung jawab pemakai.

---

## 6. Troubleshooting

| Gejala | Penyebab | Solusi |
|---|---|---|
| `token hilang: jalankan login OTP dulu` | belum pernah login | Langkah 2 |
| `401 permintaan tidak diotorisasi` | access kadaluarsa/korup | biarkan script refresh; kalau tetap, cek `tok.json` |
| `429 Too Many Requests` | rate limit | tunggu; query lagi dengan `--gap=5` |
| `IDPel/Nomor Meter yang Anda masukan salah` | IDPEL salah | cek lagi 12 digit |
| `500 V000` di riwayat | path pakai IDPEL | pakai `--usage` (otomatis pakai id internal) |
| `Kode verifikasi tidak ditemukan` | format nomor OTP salah | pakai nomor polos tanpa `0`/`62` |
| Karakter `•` jadi `?`/kacau (Windows) | konsol non-UTF-8 | `chcp 65001` + `$env:PYTHONUTF8="1"` |
| respons beda dari dokumentasi | PLN ganti API | cek `x-plnmobile-version: 8.1.1` |

---

## 7. Dokumen lain

| File | Isi |
|---|---|
| `PLN-CEK-DAYA-API.md` | referensi lengkap: semua endpoint, header, katalog 200/404/500, bukti uji, risiko PII |
| `pln-cek.py` | query IDPEL → daya + lat/long + pemilik (auto-refresh token) |
| `pln-login.py` | login OTP sekali → tulis `tok.json` |

### Bonus: alamat jalan dari koordinat (karena `address` di-mask)

```bash
curl -A 'pln-cek/1.0' \
  'https://nominatim.openstreetmap.org/reverse?lat=-7.9&lon=112.7&format=jsonv2&zoom=18'
# → <nama jalan>, <kelurahan>, <kecamatan>, <kab/kota>, <provinsi> <kodepos>
```

Aturan Nominatim: maks **1 request/detik**, wajib header `User-Agent`, cache hasil per
koordinat, atribusi © OpenStreetMap contributors. Gagal → biarkan, jangan diulang agresif.

---

## Riwayat perubahan

| Versi | Perubahan |
|---|---|
| v1 | tutor awal: `check` (daya + lat/long) + login OTP |
| v2 | `--usage` (riwayat 6 bulan), `get()` generik, baris `pemilik:` |
| v2.1 | tagihan (titanium), alamat via OSM, tabel identifikasi `name` vs `aliasName` |
| v3 | tutorial untuk **manusia** di terminal & PowerShell (install → OTP → IDPEL), semua contoh disanitasi |
