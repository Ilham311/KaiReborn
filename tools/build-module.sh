#!/data/data/com.termux/files/usr/bin/bash
# Build KaiReborn module zip.
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/dist"
VERSION="$(grep '^version=' "$ROOT/module/module.prop" | cut -d= -f2)"
NAME="KaiReborn-${VERSION}.zip"

rm -rf "$ROOT/.build/mod" && mkdir -p "$ROOT/.build/mod/META-INF/com/google/android" "$OUT"
cp "$ROOT"/module/. "$ROOT/.build/mod/" -r

cat > "$ROOT/.build/mod/META-INF/com/google/android/update-binary" <<'UP'
#!/sbin/sh
umask 022
OUTFD=$2
ZIPFILE=$3
ui_print() { echo "$1"; }
mount /data 2>/dev/null
if [ -f /data/adb/magisk/util_functions.sh ]; then
  . /data/adb/magisk/util_functions.sh
elif [ -f /data/adb/ksu/bin/util_functions.sh ]; then
  . /data/adb/ksu/bin/util_functions.sh
elif [ -f /data/adb/ksud ]; then
  # KernelSU / KernelSU-Next: ksud installs the module itself.
  exec /data/adb/ksud module install "$ZIPFILE"
else
  ui_print "! No root manager found (no magisk, no ksud)"
  exit 1
fi
install_module
exit 0
UP

echo "#MAGISK" > "$ROOT/.build/mod/META-INF/com/google/android/updater-script"

python3 -I - "$ROOT/.build/mod" "$OUT/$NAME" <<'PY'
import os, sys, zipfile
src, out = sys.argv[1], sys.argv[2]
with zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED) as z:
    for root, dirs, files in os.walk(src):
        dirs.sort()
        for f in sorted(files):
            p = os.path.join(root, f)
            z.write(p, os.path.relpath(p, src))
print("built:", out, os.path.getsize(out), "bytes")
PY

echo "--- contents ---"
python3 -I -c "
import zipfile,sys
z=zipfile.ZipFile('$OUT/$NAME')
for i in z.infolist(): print(f'  {i.filename:50s} {i.file_size:7d}')
"
