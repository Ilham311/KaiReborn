#!/system/bin/sh
# KaiReborn — root manager action button.
# Cycles the module mode: safe -> audit -> safe.
#   safe  : apply guarded property fixes
#   audit : observe only, never write
MODDIR="${0%/*}"
[ -n "$MODDIR" ] || MODDIR="/data/adb/modules/kaireborn"
. "$MODDIR/common.sh"

kr_init_dirs
cur="$(kr_mode)"
case "$cur" in
  safe)  echo "audit" > "$KR_MODE_FILE" ;;
  audit) echo "safe"  > "$KR_MODE_FILE" ;;
  *)     echo "safe"  > "$KR_MODE_FILE" ;;
esac
kr_log "action: mode $cur -> $(kr_mode)"
kr_set_description "[$( [ "$(kr_mode)" = safe ] && echo Active || echo Audit-only )] mode=$(kr_mode). See logs/boot.log"
echo "KaiReborn mode: $cur -> $(kr_mode)"
echo "Takes effect on next boot."
