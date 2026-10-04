#!/usr/bin/env bash
# pln-cek — installer Linux/macOS: bikin command `pln-cek` & `pln-login` sendiri
set -e
BASE="https://raw.githubusercontent.com/qrevebnation/pln-cek/master"
DIR="$HOME/pln-re"
BIN="$HOME/.local/bin"
mkdir -p "$DIR" "$BIN"

for f in pln-cek.py pln-login.py; do
  echo "  mengunduh $f ..."
  if command -v curl >/dev/null 2>&1; then curl -fsSL "$BASE/$f" -o "$DIR/$f"
  else wget -qO "$DIR/$f" "$BASE/$f"; fi
  chmod +x "$DIR/$f"
done

# command sendiri (bukan alias) -> jalan juga di script & shell non-interaktif
for cmd in pln-cek pln-login; do
  printf '#!/bin/sh\nPY=$(command -v python3 || command -v python || echo python3)\nexec "$PY" "%s/%s.py" "$@"\n' "$DIR" "$cmd" > "$BIN/$cmd"
  chmod +x "$BIN/$cmd"
done

# pastikan ~/.local/bin masuk PATH
case ":$PATH:" in
  *":$BIN:"*) ;;
  *)
    if ! grep -q '\.local/bin' "$HOME/.bashrc" 2>/dev/null; then
      printf '\n# pln-cek: pastikan ~/.local/bin di PATH\nexport PATH="$HOME/.local/bin:$PATH"\n' >> "$HOME/.bashrc"
    fi
    ;;
esac

echo
echo "Terpasang:"
echo "  $BIN/pln-cek     -> $DIR/pln-cek.py"
echo "  $BIN/pln-login   -> $DIR/pln-login.py"
echo
echo "Langkah berikutnya (buka terminal BARU, atau: source ~/.bashrc):"
echo "  pln-login <nomor HP kamu, polos tanpa 0 tanpa 62>"
echo "  pln-cek <IDPEL 12 digit>"
