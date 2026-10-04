#!/usr/bin/env bash
# pln-cek — uninstaller Linux/macOS (jalankan satu baris, lihat README)
set -e
BIN="$HOME/.local/bin"
DIR="$HOME/pln-re"
RC="$HOME/.bashrc"

hapus=()
for f in "$BIN/pln-cek" "$BIN/pln-login"; do
  [ -e "$f" ] && { rm -f "$f"; hapus+=("$(basename "$f")"); }
done

if [ -d "$DIR" ]; then
  [ -f "$DIR/tok.json" ] && echo "  catatan: tok.json ikut terhapus, login OTP harus diulang kalau dipasang lagi"
  rm -rf "$DIR"
  hapus+=("folder $DIR")
fi

# buang blok yang ditambahkan installer (komentar -> alias / export PATH berurutan)
if [ -f "$RC" ] && grep -q '^# pln-cek' "$RC"; then
  awk '
    /^# pln-cek/ { skip=1; next }
    skip && (/alias pln-(cek|login)=/ || /^export PATH="\$HOME\/\.local\/bin:\$PATH"$/) { next }
    { skip=0; print }
  ' "$RC" > "$RC.tmp" && mv "$RC.tmp" "$RC"
  hapus+=("blok # pln-cek di .bashrc")
fi

echo
if [ ${#hapus[@]} -eq 0 ]; then
  echo "Tidak ada yang terpasang, tidak ada yang dihapus."
else
  echo "Terhapus:"
  for h in "${hapus[@]}"; do echo "  - $h"; done
  echo
  echo "Selesai. Kalau perintah pln-cek masih muncul di sesi yang sedang berjalan, buka terminal baru."
fi
