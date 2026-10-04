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
