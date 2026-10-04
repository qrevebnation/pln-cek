#!/usr/bin/env python3
"""Login PLN Mobile sekali pakai OTP WhatsApp -> simpan token.

Pakai:
  python3 pln-login.py 81234567890

Aturan nomor: request OTP harus POLOS tanpa 0 dan tanpa 62 (81234567890).
Simpan: ~/pln-re/tok.json  {"access": "...", "refresh": "..."}
Token access 1 jam; refresh otomatis lewat pln-cek.py (tanpa OTP).
"""
import json
import pathlib
import sys
import urllib.error
import urllib.request

try:  # konsol Windows cp1252: jangan crash saat cetak karakter •
    sys.stdout.reconfigure(errors="replace")
except (AttributeError, ValueError):  # pragma: no cover
    pass

AUTH = "https://connect-gateway.pln.co.id/u/user/v1/user/auth"
TOKEN_FILE = pathlib.Path.home() / "pln-re" / "tok.json"


def post(path: str, payload: dict) -> dict:
    req = urllib.request.Request(
        f"{AUTH}/{path}",
        data=json.dumps(payload).encode(),
        headers={"content-type": "application/json"},
    )
    try:
        with urllib.request.urlopen(req, timeout=20) as res:
            return json.loads(res.read())
    except urllib.error.HTTPError as err:
        raw = err.read().decode(errors="replace")
        try:
            return json.loads(raw)
        except ValueError:
            return {"code": err.code, "message": raw or err.reason, "success": False}


def main() -> int:
    if len(sys.argv) != 2:
        print(__doc__)
        return 1
    phone = sys.argv[1].strip().lstrip("+")
    if phone.startswith("62"):
        pass  # diterima server saat login, tapi request OTP tetap di bawah
    if not phone.isdigit():
        print(f"nomor tidak valid: {phone}")
        return 1

    sent = post("request-otp-wa", {"phoneNumber": phone, "otpType": "LOGIN"})
    if not sent.get("success"):
        print(f"GAGAL kirim kode: {sent.get('message')}")
        return 1
    print(f"kode terkirim ke WhatsApp {phone} (canResendInSec="
          f"{sent.get('data', {}).get('canResendInSec')})")

    code = input("masukkan kode OTP: ").strip()
    if not code.isdigit() or len(code) != 6:
        print("kode harus 6 digit")
        return 1

    login = post("login-otp", {"phoneNumber": phone, "otp": code, "additional": {}})
    data = login.get("data") or {}
    if not data.get("accessToken"):
        print(f"GAGAL login: {login.get('message')}")
        print("petunjuk: 'tidak sesuai' = kode salah; 'tidak ditemukan' = format "
              "request salah / kode kadaluarsa; 'terlalu banyak percobaan' = kena lock.")
        return 1

    TOKEN_FILE.parent.mkdir(parents=True, exist_ok=True)
    TOKEN_FILE.write_text(json.dumps(
        {"access": data["accessToken"], "refresh": data.get("refreshToken", "")}))
    print(f"token tersimpan di {TOKEN_FILE}")
    print(f"access berlaku {data.get('accessTokenExpiresSec')} detik, "
          f"refresh berlaku {data.get('refreshTokenExpiresMins')} menit")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
