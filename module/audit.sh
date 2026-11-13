#!/system/bin/sh
# KaiReborn — read-only audit. Changes nothing. Safe to run any time.
# This is the "just take the log" entrypoint.
#
# Usage:
#   sh audit.sh            human readable
#   sh audit.sh --json     machine readable
#   sh audit.sh --to-file  write logs/audit-<ts>.txt

MODDIR="${0%/*}"
[ -n "$MODDIR" ] || MODDIR="/data/adb/modules/kaireborn"
. "$MODDIR/common.sh"
. "$MODDIR/guard.sh"

JSON=0
TOFILE=0
for a in "$@"; do
  [ "$a" = "--json" ] && JSON=1
  [ "$a" = "--to-file" ] && TOFILE=1
done

kr_init_dirs

emit() {
  if [ "$JSON" = "1" ]; then
    printf '"%s":"%s",' "$1" "$2"
  else
    printf '%-42s %s\n' "$1" "$2"
  fi
}

run() {
  [ "$JSON" = "1" ] && printf '{'
  emit platform "$(kr_root_impl)"
  emit shell "$(readlink -f /proc/$$/exe 2>/dev/null || echo sh)"
  emit mode "$(kr_mode)"
  emit resetprop "$(kr_resetprop 2>/dev/null || echo none)"
  emit page_size "$(getconf PAGE_SIZE 2>/dev/null)"
  emit boot_completed "$(getprop sys.boot_completed)"
  emit boot_count "$(cat "$KR_STATE/boot_count" 2>/dev/null)"

  local p
  for p in ro.build.type ro.build.tags ro.build.keys ro.debuggable ro.secure \
           ro.build.fingerprint ro.build.description ro.build.flavor \
           ro.product.name ro.crypto.state sys.oem_unlock_allowed \
           ro.oem_unlock_supported ro.boot.verifiedbootstate \
           ro.boot.vbmeta.device_state ro.boot.flash.locked ro.boot.veritymode \
           ro.boot.hwc ro.boot.hwcountry init.svc.flash_recovery \
           ro.build.selinux; do
    emit "$p" "$(kr_get "$p")"
  done

  [ "$JSON" = "1" ] && printf '"end":true}'
  [ "$JSON" = "1" ] && echo
}

if [ "$TOFILE" = "1" ]; then
  OUT="$KR_LOG/audit-$(date +%Y%m%d-%H%M%S).txt"
  run > "$OUT" 2>&1
  echo "written: $OUT"
elif [ "$JSON" = "1" ]; then
  run
else
  echo "=== KaiReborn audit (read-only) ==="
  run
  echo
  echo "=== drift: custom-ROM traces ==="
  local_rp="$(kr_resetprop)"
  if [ -n "$local_rp" ]; then
    "$local_rp" 2>/dev/null | grep -E 'lineage|aosp_|eng\.|dev-keys|test-keys|userdebug' \
      | head -40 || echo "  none found"
  fi
  echo
  echo "=== last boot log (tail) ==="
  tail -n 12 "$KR_LOG/boot.log" 2>/dev/null || echo "  no log yet"
fi
