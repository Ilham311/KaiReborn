#!/data/data/com.termux/files/usr/bin/bash
# Build KaiReborn APK without Gradle.
# Toolchain used: javac + d8 + aapt2 + zipalign-free apksigner (all in Termux).
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/app"
OUT="$ROOT/dist"
BUILD="$ROOT/.build"

AJ="${ANDROID_JAR:-/data/data/com.termux/files/home/.gradle/caches/8.13/transforms/9007a5e1e76a60e6cc3cc9fce8b0217d/transformed/android.jar}"
# aapt2 needs the platform *resources*, not just the stubs jar. The device's
# own framework-res.apk is world-readable, so we link against that.
FRAMEWORK_RES="${FRAMEWORK_RES:-/system/framework/framework-res.apk}"

[ -f "$AJ" ] || { echo "android.jar not found; set ANDROID_JAR"; exit 1; }
[ -f "$FRAMEWORK_RES" ] || { echo "framework-res.apk not found; set FRAMEWORK_RES"; exit 1; }
command -v javac >/dev/null || { echo "javac missing"; exit 1; }
command -v d8    >/dev/null || { echo "d8 missing (install android-sdk build-tools pkg)"; exit 1; }
command -v aapt2 >/dev/null || { echo "aapt2 missing"; exit 1; }

rm -rf "$BUILD"; mkdir -p "$BUILD/classes" "$BUILD/dex" "$OUT"

echo "[1/5] javac"
find "$APP/src" -name '*.java' > "$BUILD/sources.txt"
javac --release 17 -nowarn -cp "$AJ" -d "$BUILD/classes" @"$BUILD/sources.txt" 2>&1 | grep -v '^Note:' || true

echo "[2/5] d8"
find "$BUILD/classes" -name '*.class' > "$BUILD/classes.txt"
d8 --min-api 30 --lib "$AJ" --output "$BUILD/dex" @"$BUILD/classes.txt"

echo "[3/5] aapt2 link"
aapt2 link -o "$BUILD/base.apk" \
  -I "$FRAMEWORK_RES" \
  --manifest "$APP/AndroidManifest.xml" \
  --min-sdk-version 30 --target-sdk-version 35 \
  --version-code 1 --version-name 1.0.0

echo "[4/5] add classes.dex"
cp "$BUILD/dex/classes.dex" "$BUILD/classes.dex"
# No `zip` binary in this Termux image; python's zipfile is deterministic and
# stores without compression, which is what apksigner wants anyway.
python3 -I - "$BUILD/base.apk" "$BUILD/classes.dex" <<'PY'
import sys, zipfile
apk, dex = sys.argv[1], sys.argv[2]
with zipfile.ZipFile(apk, 'a', zipfile.ZIP_STORED) as z:
    z.write(dex, 'classes.dex')
print("  classes.dex added:", apk)
PY

echo "[5/5] sign"
if [ ! -f "$ROOT/keys/debug.keystore" ]; then
  mkdir -p "$ROOT/keys"
  keytool -genkeypair -v -keystore "$ROOT/keys/debug.keystore" \
    -alias kaireborn -keyalg RSA -keysize 2048 -validity 10000 \
    -storepass android -keypass android \
    -dname "CN=KaiReborn, OU=Audit, O=KaiReborn, L=-, S=-, C=ID" >/dev/null 2>&1
fi
zipalign -f 4 "$BUILD/base.apk" "$BUILD/aligned.apk" 2>/dev/null || cp "$BUILD/base.apk" "$BUILD/aligned.apk"
apksigner sign --ks "$ROOT/keys/debug.keystore" --ks-pass pass:android \
  --key-pass pass:android --out "$OUT/KaiReborn-1.0.0.apk" "$BUILD/aligned.apk"
apksigner verify --print-certs "$OUT/KaiReborn-1.0.0.apk" | head -4

echo "done: $OUT/KaiReborn-1.0.0.apk"
