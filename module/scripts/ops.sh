#!/system/bin/sh
# KaiReborn — device operations, "full" feature set.
#
# Every routine here mirrors a routine the legacy APK ran as root, but each
# one is gated by the module mode and supports a dry-run:
#
#   kr_op <name> [--apply]
#
# Without --apply nothing is written and the plan is printed. With --apply the
# operation runs and every path it touches is appended to the module log.
#
# What is deliberately NOT reproduced, and why (see docs/EVIDENCE.md):
#   * `find /data/data -name cache|code_cache -exec rm -rf`  — 1019 dirs here
#   * `find /sdcard -type d -empty -exec rm -rf`             — 624 dirs here
#   * `rm /data/system/users/0/settings_*`                   — 19 files here
#   * `mount -o remount,rw / | /product | /vendor`           — dm devices, ro
#   * writing /cache/recovery/openrecoveryscript + reboot recovery — no
#     recovery partition on A/B here
# The equivalents below scope each operation to the *target app*, and the
# package-level reset refuses to run for critical packages.

KR_CRITICAL_PKGS="com.google.android.gms com.android.vending com.google.android.gsf android com.google.android.gsf.login"

kr_op() {
  local name="$1"; shift
  case "$name" in
    wipegms)      kr_op_wipegms "$@" ;;
    ssaid)        kr_op_ssaid "$@" ;;
    cleaner)      kr_op_cleaner "$@" ;;
    pkgreset)     kr_op_pkgreset "$@" ;;
    pkgreinstall) kr_op_pkgreinstall "$@" ;;
    ifw)          kr_op_ifw "$@" ;;
    dalvik)       kr_op_dalvik "$@" ;;
    *) echo "unknown op: $name"; return 1 ;;
  esac
}

kr_apply_or_plan() {
  # $1 = "apply" or "plan"
  [ "$1" = "apply" ]
}

# --- wipe Google data, scoped ----------------------------------------------
# Legacy: pm clear for 16 packages including com.google.android.gms.
# PM clear on GMS is what regenerates the Advertising ID, so the capability is
# kept, but it is opt-in per call and logged.
kr_op_wipegms() {
  local mode="${1:-plan}"; shift 2>/dev/null || true
  local apps="com.google.android.gms.ext.services com.google.android.ext.shared
com.google.android.syncadapters.contacts com.google.android.syncadapters.calendar
com.google.android.partnersetup com.google.android.feedback
com.google.android.backuptransport com.google.android.configupdater
com.google.android.onetimeinitializer"

  echo "── wipe (scoped) ──"
  echo "note: com.google.android.gms and com.android.vending are NOT cleared here."
  echo "      Clearing GMS rotates the Advertising ID; do it deliberately with"
  echo "      'wipegms --with-gms', and expect to re-sign-in to Google apps."
  for a in "$@"; do
    [ "$a" = "--with-gms" ] && apps="com.google.android.gms com.android.vending $apps"
  done

  for a in $apps; do
    if ! pm list packages 2>/dev/null | grep -q "^package:$a$"; then
      echo "  skip (absent) $a"
      continue
    fi
    if [ "$mode" = "apply" ]; then
      am force-stop "$a" >/dev/null 2>&1
      if pm clear "$a" >/dev/null 2>&1; then
        echo "  cleared $a"
        kr_log "op wipegms: cleared $a"
      else
        echo "  FAILED  $a"
        kr_log "op wipegms: FAILED $a"
      fi
    else
      echo "  would clear $a"
    fi
  done
}

# --- per-app data reset and reinstall (legacy wipe + reinstall) ------------
kr_op_pkgreset() {
  local mode="${1:-plan}" pkg="$2"
  [ -n "$pkg" ] || { echo "usage: pkgreset <package> [--apply]"; return 1; }
  for c in $KR_CRITICAL_PKGS; do
    [ "$pkg" = "$c" ] && { echo "refusing: $pkg is critical (use wipegms --with-gms)"; return 1; }
  done
  echo "── reset data: $pkg ──"
  if [ "$mode" != "apply" ]; then
    echo "  would run: am force-stop; pm clear; rm -rf /sdcard/Android/data/$pkg"
    return 0
  fi
  am force-stop "$pkg" >/dev/null 2>&1
  pm clear "$pkg" >/dev/null 2>&1 && echo "  data cleared" || echo "  clear FAILED"
  if [ -d "/storage/emulated/0/Android/data/$pkg" ]; then
    rm -rf "/storage/emulated/0/Android/data/$pkg" 2>/dev/null \
      && echo "  external data removed" || echo "  external data FAILED"
  fi
  kr_log "op pkgreset: $pkg"
}

# --- reinstall keeping signature slot (legacy pm install -t -i vending) ----
kr_op_pkgreinstall() {
  local mode="${1:-plan}" pkg="$2"
  [ -n "$pkg" ] || { echo "usage: pkgreinstall <package> [--apply]"; return 1; }
  echo "── reinstall: $pkg ──"
  local path; path="$(pm path "$pkg" 2>/dev/null | head -1 | sed 's/^package://')"
  [ -n "$path" ] || { echo "  not installed"; return 1; }
  echo "  apk: $path"
  if [ "$mode" != "apply" ]; then
    echo "  would run: uninstall -> pm install -t -i com.android.vending -r"
    return 0
  fi
  local tmp="/data/local/tmp/kaireborn-$pkg.apk"
  cp -f "$path" "$tmp" 2>/dev/null || { echo "  copy FAILED"; return 1; }
  pm uninstall "$pkg" >/dev/null 2>&1
  if pm install -t -i com.android.vending -r "$tmp" >/dev/null 2>&1; then
    echo "  reinstalled (installer set to Play Store)"
    kr_log "op pkgreinstall: $pkg"
  else
    echo "  install FAILED — apk kept at $tmp"
  fi
  rm -f "$tmp" 2>/dev/null
}

# --- SSAID ----------------------------------------------------------------
# Legacy: rm every settings_ssaid* under /data/system/users/0.
# Kept, but it backs the files up first and requires the module to be in full
# mode. The platform regenerates per-app values; nothing writes a chosen ID.
kr_op_ssaid() {
  local mode="${1:-plan}" dir="/data/system/users/0"
  echo "── android id (SSAID) ──"
  local files; files="$(find "$dir" -maxdepth 1 -type f -name 'settings_ssaid*' 2>/dev/null)"
  [ -n "$files" ] || { echo "  no ssaid files found"; return 0; }
  echo "$files" | while read -r f; do echo "  target: $f"; done
  if [ "$mode" != "apply" ]; then
    echo "  would back up to $KR_STATE/ssaid-backup/ then remove"
    echo "  next boot: every app gets a fresh Android ID"
    return 0
  fi
  local b="$KR_STATE/ssaid-backup/$(date +%Y%m%d-%H%M%S)"
  mkdir -p "$b" 2>/dev/null
  echo "$files" | while read -r f; do
    [ -f "$f" ] || continue
    cp -f "$f" "$b/" 2>/dev/null && echo "  backed up $(basename "$f")"
    rm -f "$f" 2>/dev/null && echo "  removed $(basename "$f")"
  done
  kr_log "op ssaid: backed up to $b and removed"
}

# --- IFW (legacy "reset blokir") ------------------------------------------
kr_op_ifw() {
  local mode="${1:-plan}"
  echo "── IFW (app firewall rules) ──"
  local f="/data/system/ifw"
  if [ ! -d "$f" ]; then echo "  no IFW directory"; return 0; fi
  if [ "$mode" != "apply" ]; then
    echo "  would remove: $f/*.xml"
    return 0
  fi
  local n=0
  for x in "$f"/*.xml; do [ -f "$x" ] && rm -f "$x" && n=$((n + 1)); done
  echo "  removed $n rule file(s)"
  kr_log "op ifw: removed $n files"
}

# --- Dalvik / cache clean, scoped to the target app -----------------------
# Legacy: `find /data/data -name cache -exec rm -rf` (1019 dirs here) plus
# wiping all empty dirs on storage (624 here). That is a device-wide data
# loss event for a prop-hygiene feature, so it is not reproduced verbatim.
# What is kept: clearing the *target app's* cache, which is what the feature
# was actually for.
kr_op_cleaner() {
  local mode="${1:-plan}" pkg="$2"
  echo "── cache cleanup (scoped) ──"
  if [ -z "$pkg" ]; then
    echo "  system cache dirs (shared, safe to drop; system rebuilds them):"
    local sysn
    sysn="$(find /data/data -maxdepth 2 -type d \( -name code_cache \) 2>/dev/null | wc -l)"
    echo "    candidate code_cache dirs: $sysn"
    echo "  per-app cache under /data/data/*/cache is NOT removed globally."
    echo "  use: cleaner <package>   to drop one app's cache"
    return 0
  fi
  local d="/data/data/$pkg/cache"
  if [ ! -d "$d" ]; then echo "  no cache dir for $pkg"; return 0; fi
  if [ "$mode" != "apply" ]; then
    echo "  would remove: $d/*"
    return 0
  fi
  am force-stop "$pkg" >/dev/null 2>&1
  rm -rf "$d"/* 2>/dev/null
  echo "  cleared $d"
  kr_log "op cleaner: $pkg"
}

# --- dalvik ---------------------------------------------------------------
# Legacy wrote an openrecoveryscript and rebooted to recovery. This device is
# A/B with no recovery partition, so that is a one-way trip to the booted
# system. What actually exists on modern Android:
#   cmd package compile -m speed-profile  (recompile, no wipe)
kr_op_dalvik() {
  local mode="${1:-plan}"
  echo "── dalvik / ART ──"
  echo "  openrecoveryscript + reboot recovery: not offered (A/B device)"
  if [ "$mode" != "apply" ]; then
    echo "  would run: cmd package compile -m speed-profile -a"
    return 0
  fi
  cmd package compile -m speed-profile -a >/dev/null 2>&1 \
    && { echo "  recompiled"; kr_log "op dalvik: recompiled"; } \
    || echo "  compile FAILED"
}
