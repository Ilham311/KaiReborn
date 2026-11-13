#!/system/bin/sh
# KaiReborn — shared platform layer.
# Sourced by post-fs-data.sh, service.sh and guard.sh. Never executed alone.

KR_STATE="$MODDIR/state"
KR_LOG="$MODDIR/logs"
KR_MARK="$KR_STATE/boot_ok"
KR_BOOTCOUNT="$KR_STATE/boot_count"
KR_MODE_FILE="$KR_STATE/mode"

kr_init_dirs() {
  mkdir -p "$KR_STATE" "$KR_LOG" 2>/dev/null
  [ -f "$KR_MODE_FILE" ] || echo "safe" > "$KR_MODE_FILE"
}

# --- platform detection -----------------------------------------------------
# One place, correct for Magisk / KernelSU / KernelSU-Next / APatch.
# We never touch `magisk` on a KSU box: on KSU `magisk -V` does not exist and
# under busybox ash `[ "" -lt N ]` is a hard error (bad number), which is
# exactly what made the legacy module behave differently per shell.

kr_root_impl() {
  if [ -n "$KSU" ] || [ -d /data/adb/ksu ]; then
    if [ -x /data/adb/ksud ]; then echo "ksu"; else echo "ksu-no-ksud"; fi
  elif [ -n "$APATCH" ] || [ -d /data/adb/ap ]; then
    echo "apatch"
  elif [ -d /data/adb/magisk ]; then
    echo "magisk"
  else
    echo "unknown"
  fi
}

# resetprop binary: prefer the root manager's own build (it is native to the
# running kernel/init), fall back to the root manager's busybox.
kr_resetprop() {
  # Explicit override wins. Used by the test harness and by anything exotic.
  [ -n "$KR_RESETPROP" ] && [ -x "$KR_RESETPROP" ] && { echo "$KR_RESETPROP"; return 0; }
  for c in \
    /data/adb/ksu/bin/resetprop \
    /data/adb/ap/bin/resetprop \
    /data/adb/magisk/resetprop \
    "$MODDIR/resetprop"
  do
    [ -x "$c" ] && { echo "$c"; return 0; }
  done
  return 1
}

kr_busybox() {
  for c in /data/adb/ksu/bin/busybox /data/adb/ap/bin/busybox /data/adb/magisk/busybox; do
    [ -x "$c" ] && { echo "$c"; return 0; }
  done
  command -v busybox 2>/dev/null && return 0
  return 1
}

# --- safe property primitives ----------------------------------------------
# Every write: delete first (Magisk v22.1 changelog: modifying device
# fingerprint without deleting the existing ro.* entry is itself a bootloop
# source), then set, then read back and verify. A failed verify is logged and
# skipped — never fatal.

kr_get() {
  local RP; RP="$(kr_resetprop)" || return 1
  "$RP" -v "$1" 2>/dev/null
}

kr_set() {
  local name="$1" value="$2" RP old
  RP="$(kr_resetprop)" || { kr_log "SKIP $name (no resetprop)"; return 1; }
  old="$("$RP" -v "$name" 2>/dev/null)"

  # Never invent a property that the ROM does not ship: on a stock ROM an
  # extra ro.* is itself a fingerprint tell.
  if [ -z "$old" ] && [ "$3" != "force" ]; then
    kr_log "SKIP $name (absent, not forced)"
    return 2
  fi
  [ "$old" = "$value" ] && return 0

  "$RP" -d "$name" >/dev/null 2>&1
  "$RP" -n "$name" "$value" >/dev/null 2>&1

  local now
  now="$("$RP" -v "$name" 2>/dev/null)"
  if [ "$now" = "$value" ]; then
    kr_log "SET  $name=$value (was '$old')"
    return 0
  fi
  kr_log "FAIL $name: wanted '$value' got '$now'"
  return 1
}

# Batch form: resetprop -f reads NAME=VALUE lines in one process.
# Measured cost: ~10.4 ms per spawn on this device, so 180 individual checks
# cost ~1.9 s of boot time. Batch keeps it to a handful of spawns.
kr_set_batch() {
  local file="$1" RP line
  RP="$(kr_resetprop)" || return 1
  [ -s "$file" ] || return 0
  "$RP" -f "$file" >/dev/null 2>&1 || { kr_log "FAIL batch $file"; return 1; }
  kr_log "BATCH applied $(wc -l < "$file") entries from ${file##*/}"
  return 0
}

kr_log() {
  kr_init_dirs
  echo "$(date '+%m-%d %H:%M:%S') [$$] $*" >> "$KR_LOG/boot.log"
  # keep one rotation
  if [ "$(wc -l < "$KR_LOG/boot.log" 2>/dev/null || echo 0)" -gt 800 ]; then
    tail -n 400 "$KR_LOG/boot.log" > "$KR_LOG/boot.log.tmp" 2>/dev/null
    mv -f "$KR_LOG/boot.log.tmp" "$KR_LOG/boot.log" 2>/dev/null
  fi
}

# --- boot loop guard --------------------------------------------------------
# Two consecutive boots that never reached service.sh -> disable ourselves and
# say why in module.prop, so the failure is visible instead of a silent loop.

kr_boot_begin() {
  kr_init_dirs
  local n=0
  [ -f "$KR_BOOTCOUNT" ] && n="$(cat "$KR_BOOTCOUNT" 2>/dev/null)"
  case "$n" in ''|*[!0-9]*) n=0 ;; esac
  n=$((n + 1))
  echo "$n" > "$KR_BOOTCOUNT"
  kr_log "boot_begin count=$n impl=$(kr_root_impl) mode=$(cat "$KR_MODE_FILE" 2>/dev/null)"

  if [ "$n" -ge 3 ]; then
    touch "$MODDIR/disable"
    kr_set_description "[Disabled] 3 boots without completion — see logs/boot.log"
    kr_log "ABORT: disabling module after $n incomplete boots"
    return 1
  fi
  return 0
}

kr_boot_ok() {
  kr_init_dirs
  echo 0 > "$KR_BOOTCOUNT"
  echo "$(date '+%s')" > "$KR_MARK"
  kr_log "boot_ok"
}

kr_set_description() {
  [ -f "$MODDIR/module.prop" ] || return 0
  grep -v '^description=' "$MODDIR/module.prop" > "$MODDIR/module.prop.tmp" 2>/dev/null
  echo "description=$1" >> "$MODDIR/module.prop.tmp"
  mv -f "$MODDIR/module.prop.tmp" "$MODDIR/module.prop" 2>/dev/null
}

kr_mode() { cat "$KR_MODE_FILE" 2>/dev/null || echo safe; }
