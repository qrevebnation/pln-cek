#!/usr/bin/env bash
# pln-cek — installer Linux/macOS (jalankan satu baris, lihat README)
set -e
BASE="https://raw.githubusercontent.com/qrevebnation/pln-cek/master"
DIR="$HOME/pln-re"
mkdir -p "$DIR"
for f in pln-cek.py pln-login.py; do
  echo "  mengunduh $f ..."
  if command -v curl >/dev/null 2>&1; then curl -fsSL "$BASE/$f" -o "$DIR/$f"
  else wget -qO "$DIR/$f" "$BASE/$f"; fi
  chmod +x "$DIR/$f"
done
# alias sekali saja (tidak dobel)
if ! grep -q "alias pln-cek=" "$HOME/.bashrc" 2>/dev/null; then
  printf '\n# pln-cek\nalias pln-cek='"'"'python3 ~/pln-re/pln-cek.py'"'"'\nalias pln-login='"'"'python3 ~/pln-re/pln-login.py'"'"'\n' >> "$HOME/.bashrc"
fi
echo
echo "Terpasang di: $DIR"
echo "Langkah berikutnya:"
echo "  source ~/.bashrc"
echo "  pln-login <nomor HP kamu, polos tanpa 0 tanpa 62>"
echo "  pln-cek <IDPEL 12 digit>"
