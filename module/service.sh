#!/system/bin/sh
# KaiReborn — late boot. Waits for boot_completed, then applies service props,
# user overrides, and writes the audit snapshot. No side effects on failure.

MODDIR="${0%/*}"
[ -n "$MODDIR" ] || MODDIR="/data/adb/modules/kaireborn"

[ -f "$MODDIR/common.sh" ] || exit 0
. "$MODDIR/common.sh"
[ -f "$MODDIR/guard.sh" ] || exit 0
. "$MODDIR/guard.sh"

kr_init_dirs

# Do not race init. sys.boot_completed is the only reliable signal.
i=0
while [ "$(getprop sys.boot_completed)" != "1" ]; do
  i=$((i + 1))
  [ "$i" -gt 180 ] && { kr_log "service: boot_completed timeout, aborting"; exit 0; }
  sleep 1
done

kr_guard_service

# User overrides written by the companion app, applied last so the user wins.
if [ -s "$KR_STATE/extra.prop" ]; then
  kr_log "service: applying user overrides"
  kr_set_batch "$KR_STATE/extra.prop"
fi

# Snapshot for `props_audit.sh` diffs across boots.
kr_guard_audit > "$KR_LOG/audit.txt" 2>/dev/null
kr_log "service: audit snapshot written"
