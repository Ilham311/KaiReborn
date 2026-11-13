#!/usr/bin/env bash
# Build KaiReborn APK without Gradle.
#
# Portable across two environments:
#   * GitHub Actions (ubuntu-latest): SDK at $ANDROID_HOME, build-tools on PATH,
#     platform android.jar plus its framework-res.apk.
#   * Termux on device: android.jar from a Gradle cache, aapt2/d8/apksigner from
#     the termux package, framework resources borrowed from
#     /system/framework/framework-res.apk.
#
# Override with ANDROID_JAR / FRAMEWORK_RES if your layout differs.
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/app"
OUT="$ROOT/dist"
BUILD="$ROOT/.build"

VER_CODE="${VERSION_CODE:-1}"
VER_NAME="${VERSION_NAME:-1.0.0}"

# ---- locate toolchain ------------------------------------------------------
find_sdk_jar() {
  local sdk="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}"
  [ -n "$sdk" ] || return 1
  local p
  p="$(ls -d "$sdk"/platforms/android-* 2>/dev/null | sort -V | tail -1)"
  [ -n "$p" ] && [ -f "$p/android.jar" ] && { echo "$p/android.jar"; return 0; }
  return 1
}

find_framework_res() {
  local sdk="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}"
  # 1. explicit
  [ -n "${FRAMEWORK_RES:-}" ] && [ -f "$FRAMEWORK_RES" ] && { echo "$FRAMEWORK_RES"; return 0; }
  # 2. SDK platform resource apk (present on the GH runner image)
  if [ -n "$sdk" ]; then
    local p
    p="$(ls -d "$sdk"/platforms/android-* 2>/dev/null | sort -V | tail -1)"
    for c in "$p/framework-res.apk" "$p/android.jar"; do
      [ -f "$c" ] && { echo "$c"; return 0; }
    done
  fi
  # 3. device
  [ -f /system/framework/framework-res.apk ] && { echo /system/framework/framework-res.apk; return 0; }
  return 1
}

AJ="${ANDROID_JAR:-$(find_sdk_jar || true)}"
[ -n "$AJ" ] || AJ="$(ls /data/data/com.termux/files/home/.gradle/caches/*/transforms/*/transformed/android.jar 2>/dev/null | head -1)"
FR="$(find_framework_res || true)"

[ -n "$AJ" ] && [ -f "$AJ" ] || { echo "! android.jar not found; set ANDROID_JAR"; exit 1; }
[ -n "$FR" ] && [ -f "$FR" ] || { echo "! framework resources not found; set FRAMEWORK_RES"; exit 1; }

command -v javac    >/dev/null || { echo "! javac missing"; exit 1; }
command -v d8       >/dev/null || { echo "! d8 missing"; exit 1; }
command -v aapt2    >/dev/null || { echo "! aapt2 missing"; exit 1; }
command -v apksigner >/dev/null || { echo "! apksigner missing"; exit 1; }

echo "android.jar    : $AJ"
echo "framework res  : $FR"
echo "aapt2          : $(command -v aapt2)"
echo "d8             : $(command -v d8)"

rm -rf "$BUILD"; mkdir -p "$BUILD/classes" "$BUILD/dex" "$OUT"

# ---- 1. compile ------------------------------------------------------------
echo "[1/6] javac"
find "$APP/src" -name '*.java' > "$BUILD/sources.txt"
javac --release 17 -nowarn -cp "$AJ" -d "$BUILD/classes" @"$BUILD/sources.txt"

# ---- 2. dex -----------------------------------------------------------------
echo "[2/6] d8"
find "$BUILD/classes" -name '*.class' > "$BUILD/classes.txt"
d8 --min-api 30 --lib "$AJ" --output "$BUILD/dex" @"$BUILD/classes.txt"

# ---- 3. resources -----------------------------------------------------------
echo "[3/6] aapt2 link"
aapt2 link -o "$BUILD/base.apk" \
  -I "$FR" \
  --manifest "$APP/AndroidManifest.xml" \
  --min-sdk-version 30 --target-sdk-version 35 \
  --version-code "$VER_CODE" --version-name "$VER_NAME"

# ---- 4. package -------------------------------------------------------------
echo "[4/6] add classes.dex"
cp "$BUILD/dex/classes.dex" "$BUILD/classes.dex"
python3 -I - "$BUILD/base.apk" "$BUILD/classes.dex" <<'PY'
import sys, zipfile
apk, dex = sys.argv[1], sys.argv[2]
with zipfile.ZipFile(apk, 'a', zipfile.ZIP_STORED) as z:
    z.write(dex, 'classes.dex')
print("  classes.dex ->", apk)
PY

# ---- 5. align ---------------------------------------------------------------
echo "[5/6] align"
if command -v zipalign >/dev/null; then
  zipalign -f 4 "$BUILD/base.apk" "$BUILD/aligned.apk"
else
  echo "  zipalign not present, skipping (apksigner v2+ tolerates it)"
  cp "$BUILD/base.apk" "$BUILD/aligned.apk"
fi

# ---- 6. sign ----------------------------------------------------------------
echo "[6/6] sign"
KS="$ROOT/keys/debug.keystore"
if [ ! -f "$KS" ]; then
  mkdir -p "$ROOT/keys"
  keytool -genkeypair -keystore "$KS" -alias kaireborn \
    -keyalg RSA -keysize 2048 -validity 10000 \
    -storepass android -keypass android \
    -dname "CN=KaiReborn, OU=Audit, O=KaiReborn, C=ID" >/dev/null 2>&1
  echo "  generated $KS (debug only — never distribute this key)"
fi

APK="$OUT/KaiReborn-${VER_NAME}.apk"
apksigner sign --ks "$KS" --ks-pass pass:android --key-pass pass:android \
  --out "$APK" "$BUILD/aligned.apk"
apksigner verify --print-certs "$APK" | sed -n '1,3p'

echo "done: $APK ($(wc -c < "$APK") bytes)"
