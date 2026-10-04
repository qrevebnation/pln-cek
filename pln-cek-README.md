# pln-cek — Tutor untuk AI Agent

Cek **daya (VA)** + **latitude/longitude** IDPEL PLN lewat API PLN Mobile.
Tanpa HP, tanpa emulator, tanpa APK — murni HTTP.

Baca `PLN-CEK-DAYA-API.md` untuk referensi lengkap (semua endpoint, error, bukti uji).
File ini hanya langkah eksekusi.

**Versi 2.1 (2026-10-03)** — diperbarui mengikuti permintaan terakhir:
`--usage` (riwayat 6 bulan), baris `pemilik:`/alias, endpoint **tagihan (titanium)**,
integrasi bot `/idl` + tab riwayat, baris alamat dari koordinat (OSM).

## Isi paket

| File | Fungsi |
|---|---|
| `pln-cek-README.md` | tutor ini |
| `PLN-CEK-DAYA-API.md` | referensi API lengkap |
| `pln-cek.py` | query IDPEL → daya + lat/long + pemilik (auto-refresh token) |
| `pln-login.py` | login OTP sekali → tulis `~/pln-re/tok.json` |

Kebutuhan: Python 3.10+ (stdlib saja, `pip install` **tidak perlu**), akses internet keluar ke `connect-gateway.pln.co.id`.

## Langkah 1 — cek token

```bash
ls ~/pln-re/tok.json 2>/dev/null && echo ADA || echo KOSONG
```

**ADA** → langsung ke Langkah 3.
**KOSONG** → Langkah 2.

## Langkah 2 — login (sekali, butuh manusia)

Butuh **WhatsApp yang menerima kode OTP**. Agent tidak bisa sendiri — minta manusia.

```bash
python3 pln-login.py 81234567890        # nomor POLOS: tanpa 0, tanpa 62
```

Script minta `masukkan kode OTP`. Minta manusia menyalin kode dari WhatsApp, lalu tempel.

Aturan keras:
- **Nomor request harus polos** (`81234567890`). Format `0812…`/`62812…` → server bilang
  "berhasil terkirim", kode masuk WA, tapi **tidak pernah terbentuk** → login gagal.
- **Satu tembakan per kode.** Sekitar 5 kali salah → lock OTP.
- Simpan `~/pln-re/tok.json` → `{"access": ..., "refresh": ...}`. Ini rahasia; jangan dikirim ke mana pun.

Gagal? Petunjuk ada di pesan error script:
`tidak sesuai` = kode salah · `tidak ditemukan` = format request salah / kode kadaluarsa ·
`terlalu banyak percobaan` = lock, tunggu.

## Langkah 3 — query

```bash
python3 pln-cek.py 990000000001                     # satu IDPEL
python3 pln-cek.py 990000000001 990000000002 990000000003   # banyak, jeda default 2 detik
python3 pln-cek.py --gap=5 990000000001 …            # jeda custom
python3 pln-cek.py --usage 990000000001              # + riwayat 6 bulan (kWh & rupiah)
```

Output:
```
990000000001  daya=7700VA B2  lat=-7.9 lon=112.7
  postpaid •••••••••••  00000 - <NAMA UP>
  pemilik: PT CONTOH JARINGAN NUSANTARA
  JL •••••••••••••••••••••••••••••••••••••••••
  riwayat 6 bulan (blth, kwh, rupiah):            # muncul dengan --usage
    202610  kwh=1750  rp=2800000
    … 5 baris lagi …
```

Field: `energy` = daya (VA) · `energyType` = golongan tarif · `latitude`/`longitude` = koordinat ·
`type` = prepaid/postpaid · `address` sudah di-mask server.

### Identifikasi pemilik: pakai `aliasName`, bukan `name`

| Field | Sifat | Dipakai? |
|---|---|---|
| `name` | **selalu di-mask server** (`PT ••••••`, `PT ••••••`) | ❌ tidak — tidak bisa dibuka |
| `aliasName` | **tanpa samaran** — inilah yang dicetak baris `pemilik:` | ✅ penanda pemilik |
| `address` | **di-mask server** (`JL ••••`) | ❌ tidak bisa dibuka → lihat Langkah 6 |

Bukti (5 IDPEL lintas pelanggan): `name` selalu berupa titik-titik, `aliasName` selalu utuh —
contoh dua meter milik akun yang sama keduanya `PT CONTOH JARINGAN NUSANTARA`.
`nikName` sering `None`; `nik` terbuka (data pribadi) — jangan cetak/log.

## Langkah 4 — aturan main

1. **Jeda ≥2 detik** antar IDPEL. Kena `429` → naikkan 5 detik.
2. **Token 1 jam.** `pln-cek.py` refresh sendiri — tidak perlu OTP lagi. `refreshToken` berlaku ±91 hari.
3. **Endpoint refresh punya rate limit sendiri.** Kena `429` → tunggu ±45 detik.
4. **Hanya IDPEL publik-data.** Endpoint membuka `nik` di response — jangan publikasikan response mentah.
   Untuk prabayar, response riwayat juga memuat **`tokenNumber` utuh untuk token yang belum
   terpakai** (nilai uang) — jangan log/cetak; `--usage` sudah sengaja tidak mencetaknya.
5. **Endpoint tidak membatasi ke akun sendiri** (teruji 12/12 IDPEL orang lain). Tapi IDPEL
   **prepaid milik orang lain belum dites** — uji satu dulu.
6. Koordinat bisa **per gardu, bukan per pelanggan** (dua IDPEL berbeda bisa koordinat identik).
   Jangan pakai untuk membedakan pelanggan yang berdekatan.
7. Jangan menebak endpoint. Kalau butuh data lain, cari dulu di dump string (§9 referensi)
   atau baca `PLN-CEK-DAYA-API.md` §6 katalog.

## Langkah 5 — riwayat kWh vs riwayat tagihan (endpoint terpisah)

| Kebutuhan | Endpoint | Catatan |
|---|---|---|
| Riwayat kWh 6 bulan | `platinum/v2/meter/usage/<data.id>` | **id internal** hasil `v1/meter/check`, bukan IDPEL |
| Riwayat tagihan | `titanium/v2/meter/postbilling?meterID=<idpel>` | prefix **titanium** (platinum → 404); hanya tagihan **belum dibayar** + `average_billing`, `bill_count`, `bill_four_month` |

Catatan implementasi:
- `get()` di `pln-cek.py` sudah mengembalikan isi `data` — **jangan** `.get("data")` lagi.
- Meter lunas → `message: "Belum ada tagihan yang perlu dibayar"`, field lain `0`/`""`.
- Riwayat penuh (termasuk yang sudah dibayar) tetap lewat `v2/meter/usage`.
- Contoh nilai teruji: `990000000013` → `bill_total 1800000`, `990000000001` → `average 2800000`.

## Langkah 6 — alamat jalan (karena `address` di-mask)

`address` dari PLN tidak mungkin dibuka; yang tidak di-mask adalah **koordinat**.
Balik koordinat jadi alamat lewat **OpenStreetMap Nominatim** (gratis, tanpa API key):

```bash
curl -A 'your-agent/1.0' \
  'https://nominatim.openstreetmap.org/reverse?lat=-7.9&lon=112.7&format=jsonv2&zoom=18'
# → <nama jalan>, <kelurahan>, <kecamatan>, <kab/kota>, <provinsi> <kodepos>   # hasil contoh
```
Awalan nama jalan dari OSM biasanya cocok dengan prefiks alamat yang masih terlihat
dari data PLN (yang sudah di-mask `•••`).

Aturan Nominatim (wajib):
- **Maks 1 request/detik**, selalu kirim header `User-Agent` identifikasi sendiri.
- **Cache hasil per koordinat** — 500+ meter cukup di-geocode sekali.
- Atribusi: data © OpenStreetMap contributors.
- Gagal/timeout → kembalikan alamat PLN apa adanya (masked), jangan mengulang agresif.

## Langkah 7 — dipakai bot Telegram (<bot-telegram-anda>)

Paket ini terpasang di `~/pln-re/` (token: `~/pln-re/tok.json`) dan dipanggil modul
`<modul-bot>/pln_idp.py`:

| Perintah | Isi |
|---|---|
| `/idl <12 digit>` | kartu info: daya · golongan · **Alias tanpa samaran** · meter/UP · **Alamat (OSM)** · koordinat · link Maps |
| tombol `📊 Riwayat kWh` | 6 bulan kWh + total (endpoint `v2/meter/usage`) |
| tombol `🧾 Riwayat tagihan` | tagihan belum dibayar + rata-rata (endpoint `titanium/…/postbilling`) |
| `/idl <12 digit> riwayat` | keduanya langsung dalam satu pesan |

Aturan implementasi bot:
- Callback `idp#<info|kwh|tag>#<idpel>` (handler `cb_idl`) — pesan diedit (tab), tidak menumpuk.
- Jeda ≥1 dtk antar panggilan API per klik; batas 5 IDPEL (3 bila pakai `riwayat`).
- `tokenNumber`, `nik`, `npwp` **tidak pernah dicetak** — cukup `aliasName` untuk identifikasi.
- Geocoding di-cache `~/.hermes/cache/geo_cache.json` (atomic write, fallback alamat PLN).
- Perintah `/idt` (cek tagihan lama, backend `~/pln-cek.js` + cookies) **dihapus** —
  tagihan cukup lewat tab 🧾.

## Troubleshooting

| Gejala | Penyebab | Solusi |
|---|---|---|
| `token hilang` | belum login | Langkah 2, minta manusia |
| `401 permintaan tidak diotorisasi` | access kadaluarsa / korup | biarkan script refresh; kalau tetap, cek `refreshToken` |
| `429 Too Many Requests` | rate limit | tunggu; refresh ±45 detik, query +5 detik |
| `IDPel/Nomor Meter yang Anda masukan salah` | IDPEL salah/ketik ulang | cek 12 digit |
| `500 V000` di `v2/meter/usage/<…>` | path memakai IDPEL | pakai **id internal** hasil `check` |
| `404` di riwayat tagihan | prefix salah | pakai **titanium**, bukan platinum |
| alamat `-` / kosong | OSM tidak mengenali koordinat | biarkan — fallback ke alamat PLN (masked) |
| `Kode verifikasi tidak ditemukan` | format request OTP salah | pakai nomor polos |
| `Terlalu banyak percobaan kode verifikasi` | lock OTP | tunggu, lalu satu tembakan |
| `Device UUID wajib diisi` | pakai endpoint `login-pin` | jangan — pakai OTP (§3.3 referensi) |
| respons beda dari dokumentasi | PLN ganti API | cek `x-plnmobile-version: 8.1.1`, update doc |

## Menambah kapasitas

Butuh endpoint lain (riwayat token, dsb)? Jangan disundul — lihat referensi §6
(katalog status 200/404/500) dan §9 (cara ekstrak endpoint baru dari `libapp.so`).
Semua langkah bisa dijalankan di server, tanpa emulator.

## Riwayat perubahan

| Versi | Perubahan |
|---|---|
| v1 | tutor awal: `check` (daya + lat/long) + login OTP |
| v2 | `--usage` (riwayat 6 bulan), `get()` generik, baris `pemilik:`, catatan `tokenNumber` |
| **v2.1** | Langkah 5 (tagihan titanium), Langkah 6 (alamat via OSM), Langkah 7 (integrasi bot `/idl` + tab riwayat), tabel identifikasi `name` vs `aliasName`, nama file isi paket diperbaiki, troubleshooting ditambah (500 V000, 404 titanium, alamat kosong) |


> **Contoh = data contoh.** IDPEL, nomor meter, nama pemilik, nomor telepon, kode gardu, nama kota/UP, angka kWh & tagihan, serta lat/long site
> (dibulatkan 1 desimal) pada semua contoh sudah disanitasi (bukan nilai asli). `tok.json` masuk `.gitignore`.
